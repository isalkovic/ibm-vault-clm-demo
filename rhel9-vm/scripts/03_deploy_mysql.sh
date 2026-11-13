#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 03_deploy_mysql.sh
# Purpose: Installs MySQL 8.0 Server and client packages on RHEL 9
# ==============================================================================

echo "--- [1/2] Installing MySQL 8.0 Server on RHEL 9 ---"
dnf install -y mysql-server mysql

# Start and enable mysqld service
systemctl enable --now mysqld

# Check status
if systemctl is-active --quiet mysqld; then
  echo "[+] mysqld service is active and running."
else
  echo "[-] Error starting mysqld.service" >&2
  exit 1
fi

echo "--- [2/2] Configuring Firewall for MySQL and Sidecar ---"
if systemctl is-active --quiet firewalld; then
  echo "[+] Opening firewall ports 3306 (MySQL) and 8002 (Sidecar API)..."
  firewall-cmd --permanent --add-port=3306/tcp --add-port=8002/tcp || true
  firewall-cmd --reload || true
fi

echo "[✓] MySQL 8.0 Server installed and running."
