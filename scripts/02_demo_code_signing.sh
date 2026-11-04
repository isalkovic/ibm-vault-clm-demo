#!/usr/bin/env bash
set -euo pipefail

# Script: 02_demo_code_signing.sh
# Purpose: Demonstrate Scenario 7 - Automated Artifact / JAR Signing & Verification using Vault Transit Engine.

NAMESPACE="${NAMESPACE:-clm-vault-demo}"
VAULT_POD=$(oc get pod -n "$NAMESPACE" -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$VAULT_POD" ]; then
  echo "[-] Error: Vault pod not found in namespace $NAMESPACE"
  exit 1
fi

echo "================================================================="
echo "   SCENARIO 7: ARTIFACT & JAR CODE SIGNING VIA VAULT TRANSIT"
echo "================================================================="

echo "[+] Step 1: Generating Sample Software Artifact (sample-app-v1.0.jar)..."
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

SAMPLE_FILE="$WORKDIR/sample-app-v1.0.jar"
echo "Enterprise Application Binary v1.0.0 - Build Date: $(date)" > "$SAMPLE_FILE"
echo "Artifact Size: $(wc -c < "$SAMPLE_FILE") bytes"
ORIGINAL_HASH=$(sha256sum "$SAMPLE_FILE" | awk '{print $1}')
echo "Artifact SHA-256 Hash: $ORIGINAL_HASH"

echo ""
echo "[+] Step 2: Requesting Cryptographic Signature from Vault Transit Engine..."
INPUT_B64=$(base64 < "$SAMPLE_FILE" | tr -d '\n')

SIGN_RESP=$(oc exec -n "$NAMESPACE" "$VAULT_POD" -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
vault write -format=json transit/sign/release-code-signer \
  input='$INPUT_B64' \
  signature_algorithm=pkcs1v15 \
  hash_algorithm=sha2-256
")

SIGNATURE=$(echo "$SIGN_RESP" | grep -o '"signature": *"[^"]*' | cut -d'"' -f4)
echo "Received Vault Signature: $SIGNATURE"
echo "Key: release-code-signer (RSA-4096 stored securely in Vault, Private Key never leaves Vault)"

echo ""
echo "[+] Step 3: Verifying Signature against Original Artifact..."
VERIFY_RESP=$(oc exec -n "$NAMESPACE" "$VAULT_POD" -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
vault write -format=json transit/verify/release-code-signer \
  input='$INPUT_B64' \
  signature='$SIGNATURE' \
  signature_algorithm=pkcs1v15 \
  hash_algorithm=sha2-256
")

IS_VALID=$(echo "$VERIFY_RESP" | grep -o '"valid": *[^,]*' | cut -d: -f2 | tr -d ' ')
if [ "$IS_VALID" = "true" ]; then
  echo ">>> [SUCCESS] Artifact Signature is VALID! Verified against Vault Public Key."
else
  echo ">>> [FAILURE] Artifact Signature Verification Failed!"
  exit 1
fi

echo ""
echo "[+] Step 4: Simulating Malicious Tampering / Supply Chain Attack..."
echo "MALICIOUS PAYLOAD" >> "$SAMPLE_FILE"
TAMPERED_B64=$(base64 < "$SAMPLE_FILE" | tr -d '\n')

TAMPER_VERIFY_RESP=$(oc exec -n "$NAMESPACE" "$VAULT_POD" -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
vault write -format=json transit/verify/release-code-signer \
  input='$TAMPERED_B64' \
  signature='$SIGNATURE' \
  signature_algorithm=pkcs1v15 \
  hash_algorithm=sha2-256 || true
")

IS_TAMPER_VALID=$(echo "$TAMPER_VERIFY_RESP" | grep -o '"valid": *[^,]*' | cut -d: -f2 | tr -d ' ' || echo "false")
if [ "$IS_TAMPER_VALID" != "true" ]; then
  echo ">>> [SUCCESS] Tampering Detected! Verification REJECTED (valid=false)."
else
  echo ">>> [ERROR] Tampered file was unexpectedly marked valid!"
  exit 1
fi

echo ""
echo "================================================================="
echo "   SCENARIO 7 DEMONSTRATION COMPLETE - ALL CHECKS PASSED!"
echo "================================================================="
