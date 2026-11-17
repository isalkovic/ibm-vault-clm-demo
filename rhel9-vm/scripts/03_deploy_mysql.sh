#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 03_deploy_mysql.sh
# Purpose: Installs MySQL 8.0 Server and client packages on RHEL 9
# ==============================================================================

echo "--- [1/2] Verifying / Installing MySQL 8.0 Server ---"
if rpm -q mysql-server >/dev/null 2>&1; then
  INSTALLED_PKG=$(rpm -q mysql-server)
  echo "[+] Detected existing MySQL Server package: $INSTALLED_PKG"
  echo "[+] Reusing existing MySQL 8.0 installation."
else
  echo "[+] Installing MySQL 8.0 Server via dnf..."
  dnf install -y mysql-server mysql
fi

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
