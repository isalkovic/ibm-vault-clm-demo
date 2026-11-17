#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 03_deploy_mysql.sh
# Purpose: Installs MySQL 8.0 Server and client packages on RHEL 9
# ==============================================================================

echo "--- [1/2] Verifying / Installing MySQL / MariaDB Database Server ---"
DB_SERVICE="mysqld"

if rpm -q mariadb-server >/dev/null 2>&1 || rpm -q mariadb >/dev/null 2>&1; then
  MARIADB_PKG=$(rpm -q mariadb-server 2>/dev/null || rpm -q mariadb)
  echo "[+] Detected installed MariaDB package: $MARIADB_PKG"
  if ! rpm -q mariadb-server >/dev/null 2>&1; then
    echo "[+] Installing mariadb-server to complement existing mariadb installation..."
    dnf install -y mariadb-server
  fi
  DB_SERVICE="mariadb"
elif rpm -q mysql-server >/dev/null 2>&1; then
  INSTALLED_PKG=$(rpm -q mysql-server)
  echo "[+] Detected existing MySQL Server package: $INSTALLED_PKG"
  DB_SERVICE="mysqld"
else
  echo "[+] Installing Database Server via dnf..."
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
