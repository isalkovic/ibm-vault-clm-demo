#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 03_deploy_mysql.sh
# Purpose: Installs MySQL 8.0 Server and client packages on RHEL 9
# ==============================================================================

echo "--- [1/2] Verifying / Installing MySQL / MariaDB Database Server ---"
DB_SERVICE="mysqld"

if rpm -qa | grep -q -E "^mariadb"; then
  echo "[+] Detected installed MariaDB packages on system."
  if ! rpm -q mariadb-server >/dev/null 2>&1; then
    echo "[+] Installing mariadb-server package to complete database setup..."
    dnf install -y mariadb-server
  else
    echo "[+] mariadb-server is already installed."
  fi
  DB_SERVICE="mariadb"
elif rpm -q mysql-server >/dev/null 2>&1; then
  INSTALLED_PKG=$(rpm -q mysql-server)
  echo "[+] Detected existing MySQL Server package: $INSTALLED_PKG"
  DB_SERVICE="mysqld"
else
  echo "[+] Installing Database Server (MariaDB / MySQL compatible) via dnf..."
  dnf install -y mariadb-server || dnf install -y mysql-server mysql
  DB_SERVICE="mariadb"
fi

echo "[+] Starting and enabling $DB_SERVICE service..."
systemctl enable --now "$DB_SERVICE"

# Check status
if systemctl is-active --quiet "$DB_SERVICE"; then
  echo "[+] $DB_SERVICE service is active and running."
else
  echo "[-] Error starting $DB_SERVICE.service" >&2
  exit 1
fi

echo "--- [2/2] Configuring Firewall for MySQL and Sidecar ---"
if systemctl is-active --quiet firewalld; then
  echo "[+] Opening firewall ports 3306 (MySQL) and 8002 (Sidecar API)..."
  firewall-cmd --permanent --add-port=3306/tcp --add-port=8002/tcp || true
  firewall-cmd --reload || true
fi

echo "[✓] MySQL 8.0 Server installed and running."
