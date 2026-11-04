#!/usr/bin/env bash
set -euo pipefail

# Script: 01_vault_init_pki.sh
# Purpose: Initialize HashiCorp Vault with Root & Intermediate PKI, ACME Server,
#          Transit Code Signing, KV Certificate Inventory, and Kubernetes Auth on OpenShift.

NAMESPACE="${NAMESPACE:-clm-vault-demo}"
VAULT_POD=$(oc get pod -n "$NAMESPACE" -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$VAULT_POD" ]; then
  echo "[-] Error: Vault pod not found in namespace $NAMESPACE"
  exit 1
fi

echo "[+] Target Vault Pod: $VAULT_POD in namespace $NAMESPACE"
echo "[+] Waiting for Vault to be ready..."
oc wait --for=condition=Ready pod/"$VAULT_POD" -n "$NAMESPACE" --timeout=60s

echo "[+] Executing Vault PKI and Engine Configuration..."

oc exec -n "$NAMESPACE" "$VAULT_POD" -- sh -c '
set -e
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

echo "=== 1. Enable KV Secrets Engine for Central Certificate Inventory ==="
vault secrets enable -path=kv kv-v2 || true

echo "=== 2. Setup Internal Root & Intermediate PKI Engines ==="
# 2.1 Root CA
vault secrets enable -path=pki_root pki || true
vault secrets tune -max-lease-ttl=87600h pki_root

vault write -field=certificate pki_root/root/generate/internal \
  common_name="Enterprise Demo Root CA" \
  issuer_name="root-ca" \
  ttl=87600h > /tmp/root_ca.crt

vault write pki_root/config/urls \
  issuing_certificates="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_root/ca" \
  crl_distribution_points="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_root/crl"

# 2.2 Intermediate CA
vault secrets enable -path=pki_internal pki || true
vault secrets tune -max-lease-ttl=43800h pki_internal

vault write -format=json pki_internal/intermediate/generate/internal \
  common_name="Enterprise Demo Intermediate CA" \
  issuer_name="intermediate-ca" \
  ttl=43800h > /tmp/intermediate.json

CSR=$(cat /tmp/intermediate.json | sed -n "s/.*\"csr\": *\"\(.*\)\".*/\1/p" | sed "s/\\\n/\n/g")

vault write -format=json pki_root/root/sign-intermediate \
  csr="$CSR" \
  format=pem_bundle \
  ttl=43800h > /tmp/signed_cert.json

SIGNED_CERT=$(cat /tmp/signed_cert.json | sed -n "s/.*\"certificate\": *\"\(.*\)\".*/\1/p" | sed "s/\\\n/\n/g")

vault write pki_internal/intermediate/set-signed certificate="$SIGNED_CERT"

vault write pki_internal/config/urls \
  issuing_certificates="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_internal/ca" \
  crl_distribution_points="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_internal/crl"

echo "=== 3. Configure PKI Roles with allow_any_name=true for OpenShift Routes ==="
# Role for Open Liberty (Scenario 1)
vault write pki_internal/roles/liberty-role \
  allow_any_name=true \
  allow_subdomains=true \
  allow_bare_domains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  max_ttl="30m" \
  ttl="10m"

# Role for Tomcat (Scenario 2)
vault write pki_internal/roles/tomcat-role \
  allow_any_name=true \
  allow_subdomains=true \
  allow_bare_domains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  max_ttl="30m" \
  ttl="10m"

# Role for PostgreSQL (Scenario 6)
vault write pki_internal/roles/postgres-role \
  allow_any_name=true \
  allow_subdomains=true \
  allow_bare_domains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  max_ttl="30m" \
  ttl="10m"

# Role for NGINX ACME (Scenario 3)
vault write pki_internal/roles/nginx-acme-role \
  allow_any_name=true \
  allow_subdomains=true \
  allow_bare_domains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  max_ttl="30m" \
  ttl="10m"

echo "=== 4. Configure Vault Native ACME Server (Scenario 3) ==="
vault write pki_internal/config/cluster \
  path="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_internal" \
  aia_path="http://vault.clm-vault-demo.svc.cluster.local:8200/v1/pki_internal" || true

vault write pki_internal/config/acme \
  enabled=true \
  allowed_roles="nginx-acme-role" \
  default_directory_policy="sign-verbatim" || true

echo "=== 5. Configure Transit Secrets Engine for Code / JAR Signing (Scenario 7) ==="
vault secrets enable -path=transit transit || true
vault write -f transit/keys/release-code-signer type=rsa-4096

echo "=== 6. Setup OpenShift Kubernetes Authentication ==="
vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Policies with complete permissions
vault policy write liberty-policy - <<EOF
path "pki_internal/issue/liberty-role" {
  capabilities = ["create", "update"]
}
path "pki_internal/cert/ca" {
  capabilities = ["read"]
}
path "kv/data/config/*" {
  capabilities = ["read"]
}
path "kv/data/triggers/*" {
  capabilities = ["read", "create", "update"]
}
path "kv/data/certificates/liberty/*" {
  capabilities = ["create", "update", "read"]
}
EOF

vault policy write tomcat-policy - <<EOF
path "pki_internal/issue/tomcat-role" {
  capabilities = ["create", "update"]
}
path "pki_internal/cert/ca" {
  capabilities = ["read"]
}
path "kv/data/config/*" {
  capabilities = ["read"]
}
path "kv/data/triggers/*" {
  capabilities = ["read", "create", "update"]
}
path "kv/data/certificates/tomcat/*" {
  capabilities = ["create", "update", "read"]
}
path "kv/metadata/certificates/tomcat/*" {
  capabilities = ["list", "read"]
}
EOF

vault policy write nginx-policy - <<EOF
path "pki_internal/issue/nginx-acme-role" {
  capabilities = ["create", "update"]
}
path "pki_internal/acme/*" {
  capabilities = ["create", "update", "read", "list"]
}
path "pki_internal/cert/ca" {
  capabilities = ["read"]
}
path "kv/data/config/*" {
  capabilities = ["read"]
}
path "kv/data/triggers/*" {
  capabilities = ["read", "create", "update"]
}
path "kv/data/certificates/nginx/*" {
  capabilities = ["create", "update", "read"]
}
EOF

vault policy write postgres-policy - <<EOF
path "pki_internal/issue/postgres-role" {
  capabilities = ["create", "update"]
}
path "pki_internal/cert/ca" {
  capabilities = ["read"]
}
path "kv/data/config/*" {
  capabilities = ["read"]
}
path "kv/data/triggers/*" {
  capabilities = ["read", "create", "update"]
}
path "kv/data/certificates/postgres/*" {
  capabilities = ["create", "update", "read"]
}
EOF

vault policy write signing-policy - <<EOF
path "transit/sign/release-code-signer" {
  capabilities = ["update"]
}
path "transit/verify/release-code-signer" {
  capabilities = ["update"]
}
path "transit/keys/release-code-signer" {
  capabilities = ["read"]
}
EOF

vault policy write dashboard-policy - <<EOF
path "pki_internal/*" {
  capabilities = ["create", "update", "read", "list", "delete"]
}
path "kv/*" {
  capabilities = ["create", "update", "read", "list", "delete"]
}
path "transit/*" {
  capabilities = ["create", "update", "read", "list"]
}
path "sys/health" {
  capabilities = ["read"]
}
EOF

# Bind Kubernetes Auth Roles to ServiceAccounts
vault write auth/kubernetes/role/liberty-role \
  bound_service_account_names=liberty-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=liberty-policy \
  ttl=1h

vault write auth/kubernetes/role/tomcat-role \
  bound_service_account_names=tomcat-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=tomcat-policy \
  ttl=1h

vault write auth/kubernetes/role/nginx-role \
  bound_service_account_names=nginx-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=nginx-policy \
  ttl=1h

vault write auth/kubernetes/role/postgres-role \
  bound_service_account_names=postgres-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=postgres-policy \
  ttl=1h

vault write auth/kubernetes/role/signing-role \
  bound_service_account_names=signing-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=signing-policy \
  ttl=1h

vault write auth/kubernetes/role/dashboard-role \
  bound_service_account_names=dashboard-sa \
  bound_service_account_namespaces=clm-vault-demo \
  policies=dashboard-policy \
  ttl=1h

echo "=== 7. Seed Initial Rotation Schedules ==="
vault kv put kv/config/schedules \
  liberty=300 \
  tomcat=300 \
  nginx=300 \
  postgres=300 \
  global=300

echo "=== Vault Initialization Complete! ==="
'

echo "[+] Vault PKI, ACME, Transit, and Auth successfully configured!"
