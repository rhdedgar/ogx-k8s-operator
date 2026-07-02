#!/bin/bash

set -euo pipefail

# --- Configuration ---
# These values are shared with example-with-tls.yaml and deploy-tls-test.sh.

NAMESPACE="${NAMESPACE:-ogx-tls}"

# Service / DNS names (must match the Kubernetes Service names in the example YAML)
VLLM_SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-server-tls}"
OGX_SERVICE_NAME="${OGX_SERVICE_NAME:-ogx-tls-example-service}"

# CA details
CA_KEY="ca.key"
CA_CERT="ca.crt"
CA_SUBJECT="/C=US/ST=California/L=Los Angeles/O=Demo Corp/OU=OpenShift CA/CN=example-ca"

# Security configuration
KEY_SIZE=4096
CA_VALIDITY_DAYS=365
SERVER_VALIDITY_DAYS=90

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/tls-test-certs"

echo "================================================"
echo "WARNING: This script is for TESTING PURPOSES ONLY"
echo "Do NOT use these certificates in production!"
echo "================================================"
echo
echo "Namespace:         ${NAMESPACE}"
echo "vLLM Service:      ${VLLM_SERVICE_NAME}"
echo "OGX Service:       ${OGX_SERVICE_NAME}"
echo "Output directory:  ${OUT_DIR}"
echo

# Clean and create output directories
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/vllm" "${OUT_DIR}/ogx-server" "${OUT_DIR}/ca-bundle"

# --- 1. Create the Certificate Authority (CA) ---
echo "Generating CA private key and self-signed certificate..."

openssl genrsa -out "${OUT_DIR}/${CA_KEY}" ${KEY_SIZE} 2>/dev/null

openssl req -x509 -new -nodes -key "${OUT_DIR}/${CA_KEY}" \
  -sha256 -days ${CA_VALIDITY_DAYS} \
  -subj "${CA_SUBJECT}" \
  -out "${OUT_DIR}/${CA_CERT}"

cp "${OUT_DIR}/${CA_CERT}" "${OUT_DIR}/ca-bundle/ca-bundle.crt"

echo "CA created: ${OUT_DIR}/${CA_CERT}"

# --- Helper: generate a CA-signed server certificate ---
generate_server_cert() {
  local name="$1"        # e.g. "vllm" or "ogx-server"
  local service="$2"     # Kubernetes Service name
  local out_subdir="$3"  # output subdirectory under OUT_DIR

  local san_entries="DNS:${service},DNS:${service}.${NAMESPACE}.svc,DNS:${service}.${NAMESPACE}.svc.cluster.local"

  local key_file="${OUT_DIR}/${out_subdir}/tls.key"
  local csr_file="${OUT_DIR}/${out_subdir}/tls.csr"
  local cert_file="${OUT_DIR}/${out_subdir}/tls.crt"
  local ext_file="${OUT_DIR}/${out_subdir}/ext.cnf"

  echo "Generating ${name} server certificate (SANs: ${san_entries})..."

  openssl genrsa -out "${key_file}" ${KEY_SIZE} 2>/dev/null

  openssl req -new -nodes -key "${key_file}" \
    -subj "/CN=${service}" \
    -out "${csr_file}"

  cat > "${ext_file}" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${san_entries}
EOF

  openssl x509 -req -in "${csr_file}" \
    -CA "${OUT_DIR}/${CA_CERT}" -CAkey "${OUT_DIR}/${CA_KEY}" -CAcreateserial \
    -out "${cert_file}" -days ${SERVER_VALIDITY_DAYS} -sha256 \
    -extfile "${ext_file}"

  rm -f "${csr_file}" "${ext_file}"
  echo "  -> ${cert_file} (valid for ${SERVER_VALIDITY_DAYS} days)"
}

# --- 2. Generate server certificates ---
generate_server_cert "vLLM"       "${VLLM_SERVICE_NAME}" "vllm"
generate_server_cert "OGX Server" "${OGX_SERVICE_NAME}"  "ogx-server"

# --- Summary ---
echo
echo "All files created successfully!"
echo "------------------------------------"
echo "  CA Private Key:       ${OUT_DIR}/${CA_KEY}"
echo "  CA Certificate:       ${OUT_DIR}/${CA_CERT}"
echo "  CA Bundle:            ${OUT_DIR}/ca-bundle/ca-bundle.crt"
echo "  vLLM cert/key:        ${OUT_DIR}/vllm/tls.{crt,key}"
echo "  OGX Server cert/key:  ${OUT_DIR}/ogx-server/tls.{crt,key}"
echo "------------------------------------"
echo
echo "Security Reminders:"
echo "- Keep private keys secure and never commit them to version control"
echo "- Consider using cert-manager for production certificate management"
echo "- Rotate certificates regularly in production environments"
