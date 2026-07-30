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

# Step 1: Check if any ingress in ping-cloud has critical snippet annotations
echo "Searching for critical snippet annotations on ingresses..."

has_snippets=false
for annotation in "${SNIPPET_ANNOTATIONS[@]}"; do
  count=$(kubectl get ingress -n ping-cloud -o json | \
    jq --arg ann "$annotation" '[.items[] | select(.metadata.annotations[$ann] != null)] | length')
  if [[ "${count}" -gt 0 ]]; then
    echo "Found annotation '${annotation}' on ${count} ingress(es)"
    has_snippets=true
  fi
done

if [[ "${has_snippets}" == "false" ]]; then
  echo "No critical snippet annotations found. No action required."
  exit 0
fi

# Step 2: For each nginx namespace, check settings and add patch to custom-patches.yaml if needed
for ns in "${NAMESPACES[@]}"; do
  echo ""
  echo "Checking nginx-configuration in namespace: ${ns}"

  if ! kubectl get configmap nginx-configuration -n "${ns}" >/dev/null 2>&1; then
    echo "  -> ConfigMap nginx-configuration not found in ${ns}. Skipping."
    continue
  fi

  allow_snippet=$(kubectl get configmap nginx-configuration -n "${ns}" \
    -o jsonpath='{.data.allow-snippet-annotations}' 2>/dev/null || echo "")
  risk_level=$(kubectl get configmap nginx-configuration -n "${ns}" \
    -o jsonpath='{.data.annotations-risk-level}' 2>/dev/null || echo "")

  echo "  allow-snippet-annotations: '${allow_snippet}'"
  echo "  annotations-risk-level: '${risk_level}'"

  if [[ "${allow_snippet}" == "true" && "${risk_level}" == "Critical" ]]; then
    echo "  -> Already correctly configured. No action required."
    continue
  fi

  echo "  -> Adding patch to ${CUSTOM_PATCHES}"

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
