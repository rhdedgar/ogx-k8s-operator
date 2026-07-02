#!/bin/bash

set -euo pipefail

# --- Configuration ---
NAMESPACE="${NAMESPACE:-ogx-tls}"
VLLM_SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-server-tls}"
OGX_SERVICE_NAME="${OGX_SERVICE_NAME:-ogx-tls-example-service}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/tls-test-certs"
EXAMPLE_YAML="${SCRIPT_DIR}/example-with-tls.yaml"

VLLM_TLS_SECRET="vllm-inference-tls"
OGX_TLS_SECRET="ogx-server-tls"
CA_BUNDLE_CM="custom-ca-bundle"

# --- Detect CLI (oc or kubectl) ---
if command -v oc &>/dev/null; then
  CLI=oc
elif command -v kubectl &>/dev/null; then
  CLI=kubectl
else
  echo "ERROR: neither oc nor kubectl found in PATH" >&2
  exit 1
fi

echo "Using CLI:       ${CLI}"
echo "Namespace:       ${NAMESPACE}"
echo "Example YAML:    ${EXAMPLE_YAML}"
echo

# --- 1. Create namespace if needed ---
if ! ${CLI} get namespace "${NAMESPACE}" &>/dev/null; then
  echo "Creating namespace ${NAMESPACE}..."
  ${CLI} create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# --- 2. Generate certificates ---
echo
echo "Generating test certificates..."
NAMESPACE="${NAMESPACE}" \
  VLLM_SERVICE_NAME="${VLLM_SERVICE_NAME}" \
  OGX_SERVICE_NAME="${OGX_SERVICE_NAME}" \
  "${SCRIPT_DIR}/generate_certificates.sh"

for f in "${CERT_DIR}/vllm/tls.crt" "${CERT_DIR}/vllm/tls.key" \
         "${CERT_DIR}/ogx-server/tls.crt" "${CERT_DIR}/ogx-server/tls.key" \
         "${CERT_DIR}/ca-bundle/ca-bundle.crt"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: expected certificate file not found: $f" >&2
    exit 1
  fi
done
echo "All certificate files verified."

# --- 3. Create TLS secrets ---
echo
echo "Creating TLS secrets..."

${CLI} delete secret "${VLLM_TLS_SECRET}" -n "${NAMESPACE}" --ignore-not-found
${CLI} create secret tls "${VLLM_TLS_SECRET}" \
  --cert="${CERT_DIR}/vllm/tls.crt" \
  --key="${CERT_DIR}/vllm/tls.key" \
  -n "${NAMESPACE}"

${CLI} delete secret "${OGX_TLS_SECRET}" -n "${NAMESPACE}" --ignore-not-found
${CLI} create secret tls "${OGX_TLS_SECRET}" \
  --cert="${CERT_DIR}/ogx-server/tls.crt" \
  --key="${CERT_DIR}/ogx-server/tls.key" \
  -n "${NAMESPACE}"

echo "TLS secrets created."

# --- 4. Create CA bundle ConfigMap ---
echo
echo "Creating CA bundle ConfigMap..."

${CLI} delete configmap "${CA_BUNDLE_CM}" -n "${NAMESPACE}" --ignore-not-found
${CLI} create configmap "${CA_BUNDLE_CM}" \
  --from-file=ca-bundle.crt="${CERT_DIR}/ca-bundle/ca-bundle.crt" \
  -n "${NAMESPACE}"

echo "CA bundle ConfigMap created."

# --- 5. Apply the example resources ---
echo
echo "Applying example-with-tls.yaml..."
${CLI} apply -f "${EXAMPLE_YAML}" -n "${NAMESPACE}"

# --- 6. Wait for vLLM mock to be ready ---
echo
echo "Waiting for vLLM mock server to become ready (timeout 120s)..."
${CLI} rollout status deployment/vllm-server-tls -n "${NAMESPACE}" --timeout=120s

echo
echo "============================================"
echo "TLS test environment deployed successfully!"
echo "============================================"
echo
echo "Resources in namespace '${NAMESPACE}':"
echo "  - Secret:     ${VLLM_TLS_SECRET}  (vLLM server cert)"
echo "  - Secret:     ${OGX_TLS_SECRET}   (OGX server cert)"
echo "  - ConfigMap:  ${CA_BUNDLE_CM}     (CA bundle for trust)"
echo "  - Deployment: vllm-server-tls     (mock vLLM with HTTPS)"
echo "  - Service:    vllm-server-tls     (port 8000)"
echo "  - CR:         ogx-tls-example"
echo
echo "Verify with:"
echo "  ${CLI} get pods -n ${NAMESPACE}"
echo "  ${CLI} get ogxserver -n ${NAMESPACE}"
echo
echo "Cleanup:"
echo "  ${CLI} delete -f ${EXAMPLE_YAML} -n ${NAMESPACE}"
echo "  ${CLI} delete secret ${VLLM_TLS_SECRET} ${OGX_TLS_SECRET} -n ${NAMESPACE}"
echo "  ${CLI} delete configmap ${CA_BUNDLE_CM} -n ${NAMESPACE}"
echo "  rm -rf ${CERT_DIR}"
