#!/usr/bin/env bash
set -euo pipefail

# Script: teardown.sh
# Purpose: Delete all resources and clean up OpenShift project for CLM Demo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="clm-vault-demo"

echo "=========================================================================="
echo "   TEARING DOWN CERTIFICATE LIFECYCLE MANAGEMENT (CLM) DEMO"
echo "=========================================================================="

echo "[+] Deleting OpenShift workloads and services..."
oc delete -f "$SCRIPT_DIR/k8s/06_clm_dashboard.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/05_postgres.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/04_nginx_acme.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/03_tomcat.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/02_liberty.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/01_vault.yaml" --ignore-not-found=true
oc delete -f "$SCRIPT_DIR/k8s/00_namespace_rbac.yaml" --ignore-not-found=true

echo "[+] Deleting namespace $NAMESPACE..."
oc delete namespace "$NAMESPACE" --ignore-not-found=true

echo "[+] Teardown completed successfully!"
