#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 06_teardown_all.sh
# Purpose: Stops all services and cleanly removes configurations and middleware
# ==============================================================================

echo "--- [1/3] Stopping and disabling RHEL 9 systemd services ---"
systemctl stop clm-liberty-agent.service 2>/dev/null || true
systemctl disable clm-liberty-agent.service 2>/dev/null || true

systemctl stop openliberty.service 2>/dev/null || true
systemctl disable openliberty.service 2>/dev/null || true

systemctl stop clm-mysql-agent.service 2>/dev/null || true
systemctl disable clm-mysql-agent.service 2>/dev/null || true

systemctl stop mysqld 2>/dev/null || true

echo "--- [2/3] Removing systemd unit files and agent binaries ---"
rm -f /etc/systemd/system/openliberty.service
rm -f /etc/systemd/system/clm-liberty-agent.service
rm -f /etc/systemd/system/clm-mysql-agent.service
rm -f /usr/local/bin/clm-liberty-agent.py
rm -f /usr/local/bin/clm-mysql-agent.py
rm -f /etc/my.cnf.d/clm-tls.cnf

systemctl daemon-reload

echo "--- [3/3] Removing middleware installations and certificates ---"
rm -rf /opt/ol
rm -rf /var/lib/mysql/certs
rm -rf /tmp/clm_p12
rm -rf /tmp/clmApp_build
rm -rf /var/log/clm-liberty
rm -rf /var/log/clm-mysql

echo "[✓] RHEL 9 VM Teardown and Cleanup completed."
