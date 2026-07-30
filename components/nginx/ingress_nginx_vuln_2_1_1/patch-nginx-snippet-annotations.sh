#!/bin/bash

set -e

CSR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSR_BASE="${CSR_PATH}/k8s-configs/base"
CUSTOM_PATCHES="${CSR_BASE}/custom-patches.yaml"
NAMESPACES=("ingress-nginx-public" "ingress-nginx-private")

if [[ ! -f "${CUSTOM_PATCHES}" ]]; then
  echo "ERROR: ${CUSTOM_PATCHES} not found. Ensure this script is run from the CSR root." >&2
  exit 1
fi

SNIPPET_ANNOTATIONS=(
  "nginx.ingress.kubernetes.io/configuration-snippet"
  "nginx.ingress.kubernetes.io/server-snippet"
  "nginx.ingress.kubernetes.io/location-snippet"
  "nginx.ingress.kubernetes.io/stream-snippet"
)

RED=$'\e[1;31m'
RESET=$'\e[0m'

# Pre-check: capture the current server-block count and hostname list from nginx.conf.
# Record these outputs — after ArgoCD sync + pod rollout, re-run the same commands and
# confirm the count and hostname list have not changed (no ingress dropped).
echo "=== Pre-check: nginx.conf server blocks (record for post-check comparison) ==="
for ns in "${NAMESPACES[@]}"; do
  echo ""
  echo "--- ${ns} ---"
  count=$(kubectl -n "${ns}" exec deployment/nginx-ingress-controller -q -- \
    cat nginx.conf 2>/dev/null | grep -c "## start server" || echo "0")
  echo "server-block count: ${count}"
  kubectl -n "${ns}" exec deployment/nginx-ingress-controller -q -- \
    cat nginx.conf 2>/dev/null | grep "## start server" || true
done
echo ""

# Step 1: Check if any ingress in ping-cloud has snippet annotations, and print a
# per-ingress present/absent matrix. `present` cells are highlighted in bold red so
# they don't get lost among many `absent` rows.
echo "=== Step 1: ingress snippet-annotation check (ping-cloud namespace) ==="
matrix=$(kubectl get ingress -n ping-cloud -o json | jq -r '
  ["INGRESS", "configuration-snippet", "server-snippet", "location-snippet", "stream-snippet"],
  (.items[] | [
    .metadata.name,
    (if .metadata.annotations["nginx.ingress.kubernetes.io/configuration-snippet"] != null then "present" else "absent" end),
    (if .metadata.annotations["nginx.ingress.kubernetes.io/server-snippet"]        != null then "present" else "absent" end),
    (if .metadata.annotations["nginx.ingress.kubernetes.io/location-snippet"]      != null then "present" else "absent" end),
    (if .metadata.annotations["nginx.ingress.kubernetes.io/stream-snippet"]        != null then "present" else "absent" end)
  ]) | @tsv' | column -t)

echo "${matrix}" | sed "s/present/${RED}present${RESET}/g"
echo ""

has_snippets=false
for annotation in "${SNIPPET_ANNOTATIONS[@]}"; do
  count=$(kubectl get ingress -n ping-cloud -o json | \
    jq --arg ann "$annotation" '[.items[] | select(.metadata.annotations[$ann] != null)] | length')
  if [[ "${count}" -gt 0 ]]; then
    has_snippets=true
  fi
done

if [[ "${has_snippets}" == "false" ]]; then
  echo "No snippet annotations found on any ingress. No ConfigMap patch required."
  exit 0
fi

# Step 2 + 3: For each nginx namespace, inspect nginx-configuration and, if needed,
# append the minimal patch to custom-patches.yaml. Expected normal case is that
# allow-snippet-annotations is already "true" (otherwise nginx would be ignoring
# the snippet today) — only annotations-risk-level: "Critical" needs to be added.
for ns in "${NAMESPACES[@]}"; do
  echo ""
  echo "=== Namespace: ${ns} ==="

  if ! kubectl get configmap nginx-configuration -n "${ns}" >/dev/null 2>&1; then
    echo "  -> ConfigMap nginx-configuration not found in ${ns}. Skipping."
    continue
  fi

  allow_snippet=$(kubectl get configmap nginx-configuration -n "${ns}" \
    -o jsonpath='{.data.allow-snippet-annotations}' 2>/dev/null || echo "")
  risk_level=$(kubectl get configmap nginx-configuration -n "${ns}" \
    -o jsonpath='{.data.annotations-risk-level}' 2>/dev/null || echo "")

  echo "  allow-snippet-annotations: '${allow_snippet}'"
  echo "  annotations-risk-level:    '${risk_level}'"

  if [[ "${allow_snippet}" == "true" && "${risk_level}" == "Critical" ]]; then
    echo "  -> Already fully configured. No action required."
    continue
  fi

  if [[ "${allow_snippet}" != "true" ]]; then
    echo ""
    echo "  ${RED}WARNING${RESET}: snippet annotations are present on ingresses but"
    echo "  allow-snippet-annotations is not 'true' in ${ns}. nginx is currently"
    echo "  ignoring those snippets. Applying this patch will start honoring them"
    echo "  and may change ingress behavior. Flag this to the team before merging."
  fi

  echo "  -> Appending patch to ${CUSTOM_PATCHES}"

  last_line=$(grep -v '^[[:space:]]*$' "${CUSTOM_PATCHES}" 2>/dev/null | tail -1 || true)
  {
    if [[ "${last_line}" != "---" ]]; then
      printf '\n---\n'
    else
      printf '\n'
    fi
    printf 'apiVersion: v1\n'
    printf 'kind: ConfigMap\n'
    printf 'metadata:\n'
    printf '  name: nginx-configuration\n'
    printf '  namespace: %s\n' "${ns}"
    printf 'data:\n'
    [[ "${allow_snippet}" != "true" ]] && printf '  allow-snippet-annotations: "true"\n'
    [[ "${risk_level}" != "Critical" ]] && printf '  annotations-risk-level: "Critical"\n'
  } >> "${CUSTOM_PATCHES}"

  echo "  -> Patch written for ${ns}."
done

echo ""
echo "=== Reminder ==="
echo "If an existing nginx-configuration ConfigMap patch already existed in"
echo "custom-patches.yaml, review the diff and consider merging keys into the"
echo "existing block instead of leaving two patches for the same ConfigMap."
echo "After committing and syncing ArgoCD, re-run the Pre-check commands above"
echo "and verify the server-block count and hostname list are unchanged."
