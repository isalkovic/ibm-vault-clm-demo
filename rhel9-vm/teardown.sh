#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Master Teardown Script for Open Liberty & MySQL on RHEL 9 VM
# Purpose: Stops daemons, cleans up certificates, keystores, databases & packages
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================================="
echo "   RHEL 9 VM: CLM TEARDOWN & CLEANUP"
echo "=========================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root (sudo ./teardown.sh)" >&2
  exit 1
fi

chmod +x "$SCRIPT_DIR"/scripts/*.sh
"$SCRIPT_DIR/scripts/06_teardown_all.sh"

echo ""
echo "=========================================================================="
echo " [SUCCESS] RHEL 9 VM Cleaned up successfully."
echo "=========================================================================="
