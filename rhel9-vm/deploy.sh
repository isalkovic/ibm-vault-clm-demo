#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Master Deployment Script for Open Liberty & MySQL on RHEL 9 VM
# Purpose: Prepares RHEL 9 VM, installs Java 17, Open Liberty runtime, and MySQL 8.0
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================================="
echo "   RHEL 9 VM: CLM MIDDLEWARE DEPLOYMENT (Open Liberty & MySQL 8.0)"
echo "=========================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root (sudo ./deploy.sh)" >&2
  exit 1
fi

echo "[+] Step 1/3: Installing prerequisites and system packages..."
chmod +x "$SCRIPT_DIR"/scripts/*.sh

"$SCRIPT_DIR/scripts/01_deploy_liberty.sh"
"$SCRIPT_DIR/scripts/03_deploy_mysql.sh"

echo ""
echo "=========================================================================="
echo " [SUCCESS] RHEL 9 Middleware Deployment Completed!"
echo " Next step: Run './config.sh' to configure Vault PKI, certificates & TLS"
echo "=========================================================================="
