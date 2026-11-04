#!/usr/bin/env bash
set -euo pipefail

# Script: deploy.sh
# Purpose: Master deployment script for Certificate Lifecycle Management (CLM) Demo on Red Hat OpenShift.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="clm-vault-demo"

echo "=========================================================================="
echo "   DEPLOYING CERTIFICATE LIFECYCLE MANAGEMENT (CLM) DEMO ON OPENSHIFT"
echo "=========================================================================="

echo ""
echo "[Step 1/5] Checking cluster connectivity..."
"$SCRIPT_DIR/scripts/00_prereqs.sh"

echo ""
echo "[Step 2/5] Creating OpenShift Project, ServiceAccounts & RBAC..."
oc apply -f "$SCRIPT_DIR/k8s/00_namespace_rbac.yaml"

echo ""
echo "[Step 3/5] Deploying HashiCorp Vault Server..."
oc apply -f "$SCRIPT_DIR/k8s/01_vault.yaml"

echo "[+] Waiting for Vault pod to enter Ready state..."
oc rollout status deployment/vault -n "$NAMESPACE" --timeout=120s

echo ""
echo "[Step 4/5] Initializing Vault PKI, ACME Server, Transit Engine & K8s Auth..."
"$SCRIPT_DIR/scripts/01_vault_init_pki.sh"

echo ""
echo "[Step 5/5] Deploying Target Workload Scenarios..."
echo "  -> Deploying Scenario 1: Open Liberty (Internal Vault PKI)..."
oc apply -f "$SCRIPT_DIR/k8s/02_liberty.yaml"

echo "  -> Deploying Scenario 2: Apache Tomcat (Let's Encrypt Staging + Vault Sync)..."
oc apply -f "$SCRIPT_DIR/k8s/03_tomcat.yaml"

echo "  -> Deploying Scenario 3: NGINX Reverse Proxy (Vault Native ACME)..."
oc apply -f "$SCRIPT_DIR/k8s/04_nginx_acme.yaml"

echo "  -> Deploying Scenario 6: PostgreSQL Database (TLS Rotation & pg_reload_conf)..."
oc apply -f "$SCRIPT_DIR/k8s/05_postgres.yaml"

echo "  -> Deploying Central CLM Monitoring & Management Dashboard..."
oc apply -f "$SCRIPT_DIR/k8s/06_clm_dashboard.yaml"

echo ""
echo "[+] Waiting for workload deployments to complete rollout..."
oc rollout status deployment/liberty -n "$NAMESPACE" --timeout=240s || true
oc rollout status deployment/tomcat -n "$NAMESPACE" --timeout=240s || true
oc rollout status deployment/nginx -n "$NAMESPACE" --timeout=240s || true
oc rollout status deployment/postgres -n "$NAMESPACE" --timeout=240s || true
oc rollout status deployment/clm-dashboard -n "$NAMESPACE" --timeout=120s || true

echo ""
echo "=========================================================================="
echo "   CLM DEMO ENVIRONMENT SUCCESSFULLY DEPLOYED ON OPENSHIFT!"
echo "=========================================================================="
echo ""
echo "Exposed OpenShift Routes in namespace $NAMESPACE:"
oc get routes -n "$NAMESPACE" || true
echo ""
echo "Central CLM Dashboard URL:"
DASH_ROUTE=$(oc get route clm-dashboard -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "clm-dashboard-clm-vault-demo.apps.<cluster>")
echo "   👉 https://$DASH_ROUTE/"
echo ""
echo "To run the Live Certificate Rotation Monitor CLI:"
echo "   ./scripts/03_live_monitor.sh"
echo ""
echo "To execute Scenario 7 (Artifact / Code Signing Demo):"
echo "   ./scripts/02_demo_code_signing.sh"
echo ""
echo "To teardown environment:"
echo "   ./teardown.sh"
echo "=========================================================================="
