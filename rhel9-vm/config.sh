#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Master Configuration Script for Open Liberty & MySQL on RHEL 9 VM
# Purpose: Configures Vault PKI integration, issues initial TLS certificates,
#          configures dynamic keystores & SSL, and enables rotation daemons.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================================="
echo "   RHEL 9 VM: CLM CERTIFICATE & TLS CONFIGURATION"
echo "=========================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root (sudo ./config.sh)" >&2
  exit 1
fi

chmod +x "$SCRIPT_DIR"/scripts/*.sh

"$SCRIPT_DIR/scripts/02_config_liberty.sh"
"$SCRIPT_DIR/scripts/04_config_mysql.sh"

echo ""
echo "=========================================================================="
echo " [SUCCESS] RHEL 9 Certificate Lifecycle Management Configured!"
echo " "
echo " Active Workloads & Endpoints on this RHEL 9 VM:"
echo "  1. Open Liberty HTTPS : https://$(hostname -I | awk '{print $1}'):9443/"
echo "     - Liberty Sidecar API: http://$(hostname -I | awk '{print $1}'):8001/status"
echo "     - Reload Hook: Open Liberty dynamicUpdate='true' (Zero Downtime)"
echo "  2. MySQL 8.0 TLS Server: $(hostname -I | awk '{print $1}'):3306 (SSL Required)"
echo "     - MySQL Sidecar API: http://$(hostname -I | awk '{print $1}'):8002/status"
echo "     - Reload Hook: ALTER INSTANCE RELOAD TLS; (Zero Downtime)"
echo " "
echo " Run './scripts/05_test_rotation.sh' to inspect live rotation and test hooks."
echo "=========================================================================="
