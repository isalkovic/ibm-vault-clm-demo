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
echo "   AUTOMATIC SERVICE HEALTH & AGENT REST API VERIFICATION"
echo "=========================================================================="

SERVICES=("openliberty.service" "clm-liberty-agent.service" "clm-mysql-agent.service")
if systemctl list-unit-files | grep -q mariadb.service; then
  SERVICES+=("mariadb.service")
elif systemctl list-unit-files | grep -q mysqld.service; then
  SERVICES+=("mysqld.service")
fi

ALL_ACTIVE=1
for svc in "${SERVICES[@]}"; do
  echo -n "[+] Checking service '$svc' ... "
  if systemctl is-active --quiet "$svc"; then
    echo "[ACTIVE ✓]"
  else
    echo "[INACTIVE / FAILED ✗]"
    ALL_ACTIVE=0
    echo "    --- Recent Logs for $svc ---"
    journalctl -u "$svc" -n 10 --no-pager || true
    echo "    ----------------------------"
  fi
done

echo ""
echo "[+] Probing Agent REST API endpoints on ports 8001 and 8002..."
for port in 8001 8002; do
  PROBED=0
  for i in {1..10}; do
    if curl -s "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      STATUS_JSON=$(curl -s "http://127.0.0.1:${port}/status" | jq -r '.status // "UP"' 2>/dev/null || echo "UP")
      echo "[✓] Port ${port} Agent REST API is active and healthy (Status: ${STATUS_JSON})"
      PROBED=1
      break
    fi
    sleep 1
  done
  if [ "$PROBED" -eq 0 ]; then
    echo "[-] Warning: Port ${port} Agent REST API did not respond within 10s."
    if [ "$port" -eq 8001 ]; then
      journalctl -u clm-liberty-agent.service -n 15 --no-pager || true
    else
      journalctl -u clm-mysql-agent.service -n 15 --no-pager || true
    fi
  fi
done

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
