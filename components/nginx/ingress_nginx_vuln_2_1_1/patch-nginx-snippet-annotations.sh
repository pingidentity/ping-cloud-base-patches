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

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required. Install it (e.g., 'brew install yq')." >&2
  exit 1
fi

current_context=$(kubectl config current-context 2>/dev/null || true)
if [[ -z "${current_context}" ]]; then
  echo "ERROR: no kubectl context set. Run 'tsh kube login <cluster>' first." >&2
  exit 1
fi

if ! kubectl get namespaces --request-timeout=5s >/dev/null 2>&1; then
  echo "ERROR: context '${current_context}' is set but the cluster is unreachable." >&2
  echo "       Re-authenticate with Teleport: tsh kube login <cluster>" >&2
  exit 1
fi

echo "Connected to context: ${current_context}"
echo ""

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

# Only patch controllers that actually serve a snippet-annotated ingress.
# P1AS convention: ingress-nginx-public → "nginx-public", ingress-nginx-private → "nginx-private".
NS_TO_CLASS_KEYS=("ingress-nginx-public" "ingress-nginx-private")
NS_TO_CLASS_VALS=("nginx-public"         "nginx-private")

class_for_ns() {
  local target="$1" i
  for i in "${!NS_TO_CLASS_KEYS[@]}"; do
    if [[ "${NS_TO_CLASS_KEYS[$i]}" == "${target}" ]]; then
      echo "${NS_TO_CLASS_VALS[$i]}"
      return 0
    fi
  done
  return 1
}

NS_NEEDS_PATCH=()
AMBIGUOUS_INGRESSES=()

ns_needs_patch() {
  local target="$1" n
  for n in "${NS_NEEDS_PATCH[@]}"; do
    [[ "${n}" == "${target}" ]] && return 0
  done
  return 1
}

# Build the (ingress-name, class) list for ingresses in ping-cloud that carry at least
# one snippet annotation. class = spec.ingressClassName OR legacy
# `kubernetes.io/ingress.class` annotation OR empty when neither is set.
while IFS=$'\t' read -r ing_name ing_class; do
  [[ -z "${ing_name}" ]] && continue
  if [[ -z "${ing_class}" ]]; then
    AMBIGUOUS_INGRESSES+=("${ing_name}")
    continue
  fi
  for i in "${!NS_TO_CLASS_KEYS[@]}"; do
    if [[ "${NS_TO_CLASS_VALS[$i]}" == "${ing_class}" ]]; then
      candidate="${NS_TO_CLASS_KEYS[$i]}"
      if ! ns_needs_patch "${candidate}"; then
        NS_NEEDS_PATCH+=("${candidate}")
      fi
    fi
  done
done < <(kubectl get ingress -n ping-cloud -o json | jq -r '
  .items[]
  | select(
      .metadata.annotations["nginx.ingress.kubernetes.io/configuration-snippet"] != null
      or .metadata.annotations["nginx.ingress.kubernetes.io/server-snippet"]     != null
      or .metadata.annotations["nginx.ingress.kubernetes.io/location-snippet"]   != null
      or .metadata.annotations["nginx.ingress.kubernetes.io/stream-snippet"]     != null
    )
  | [
      .metadata.name,
      (.spec.ingressClassName // .metadata.annotations["kubernetes.io/ingress.class"] // "")
    ]
  | @tsv')

if [[ ${#AMBIGUOUS_INGRESSES[@]} -gt 0 ]]; then
  echo ""
  echo "${RED}WARNING${RESET}: the following snippet-annotated ingresses have no ingress"
  echo "class set (neither spec.ingressClassName nor kubernetes.io/ingress.class):"
  for ing in "${AMBIGUOUS_INGRESSES[@]}"; do
    echo "  - ${ing}"
  done
  echo "These ingresses will NOT be attributed to any controller. Determine which"
  echo "controller (public or private) serves them and either set the class on the"
  echo "ingress or re-run this script after doing so. Skipping."
fi

if [[ ${#NS_NEEDS_PATCH[@]} -eq 0 ]]; then
  echo ""
  echo "No snippet-annotated ingress targets a known controller namespace. No patch required."
  exit 0
fi

echo ""
echo "=== Controller namespaces that need patching (scoped by ingress class) ==="
for ns in "${NS_NEEDS_PATCH[@]}"; do
  echo "  - ${ns} (class: $(class_for_ns "${ns}"))"
done

# Step 2 + 3: For each nginx namespace, inspect nginx-configuration and, if needed,
# append the minimal patch to custom-patches.yaml. Expected normal case is that
# allow-snippet-annotations is already "true" (otherwise nginx would be ignoring
# the snippet today) — only annotations-risk-level: "Critical" needs to be added.
for ns in "${NAMESPACES[@]}"; do
  echo ""
  echo "=== Namespace: ${ns} ==="

  if ! ns_needs_patch "${ns}"; then
    echo "  -> No snippet-annotated ingress targets class '$(class_for_ns "${ns}")'. Skipping to avoid unnecessary attack-surface increase."
    continue
  fi

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

  # Determine which keys need to be written for this namespace.
  keys_to_set=()
  [[ "${allow_snippet}" != "true" ]] && keys_to_set+=("allow-snippet-annotations=true")
  [[ "${risk_level}"    != "Critical" ]] && keys_to_set+=("annotations-risk-level=Critical")

  # Check whether custom-patches.yaml already has a ConfigMap/nginx-configuration
  # document for this namespace. If yes, merge keys in place (preserving any other
  # keys the existing patch already sets). If no, append a new document.
  existing_doc_index=$(NS="${ns}" yq eval-all '
      select(
        .kind == "ConfigMap" and
        .metadata.name == "nginx-configuration" and
        .metadata.namespace == strenv(NS)
      ) | document_index' "${CUSTOM_PATCHES}" | head -1)

  if [[ -n "${existing_doc_index}" ]]; then
    echo "  -> Existing nginx-configuration patch for ${ns} found at document ${existing_doc_index}. Merging keys in place."
    for kv in "${keys_to_set[@]}"; do
      key="${kv%%=*}"
      val="${kv#*=}"
      DOC_IDX="${existing_doc_index}" KEY="${key}" VAL="${val}" yq eval -i '
        (select(document_index == (strenv(DOC_IDX) | tonumber)).data[strenv(KEY)]) = strenv(VAL)
      ' "${CUSTOM_PATCHES}"
      echo "     merged: ${key}: \"${val}\""
    done
  else
    echo "  -> Appending new patch document to ${CUSTOM_PATCHES}"
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
      for kv in "${keys_to_set[@]}"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        printf '  %s: "%s"\n' "${key}" "${val}"
      done
    } >> "${CUSTOM_PATCHES}"
  fi

  echo "  -> Patch written for ${ns}."
done

echo ""
echo "=== Reminder ==="
echo "Review the diff on ${CUSTOM_PATCHES} — any pre-existing nginx-configuration"
echo "patch for the same namespace was merged in place, so other keys it sets"
echo "should still be present. After committing and syncing ArgoCD, re-run the"
echo "Pre-check commands above and verify the server-block count and hostname"
echo "list are unchanged."
