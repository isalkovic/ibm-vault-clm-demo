#!/usr/bin/env bash
set -euo pipefail

# Script: 00_prereqs.sh
# Purpose: Check OpenShift CLI (oc) login status, cluster connectivity, and tools.

echo "[+] Checking CLI prerequisites..."

if ! command -v oc >/dev/null 2>&1; then
  echo "[-] Error: 'oc' (OpenShift CLI) command is not installed or not in PATH."
  echo "    Please install OpenShift CLI from Red Hat Console or brew/dnf."
  exit 1
fi

echo "[+] Verifying OpenShift Cluster login..."
CURRENT_USER=$(oc whoami 2>/dev/null || true)

if [ -z "$CURRENT_USER" ]; then
  echo "[-] Error: You are not currently logged into an OpenShift cluster."
  echo "    Please login using 'oc login --server=<cluster-api-url> --token=<token>' and rerun."
  exit 1
fi

echo "[+] Logged in as: $CURRENT_USER"
CLUSTER_SERVER=$(oc whoami --show-server 2>/dev/null || true)
echo "[+] Target OpenShift Cluster: $CLUSTER_SERVER"

echo "[+] Prerequisites check passed!"
