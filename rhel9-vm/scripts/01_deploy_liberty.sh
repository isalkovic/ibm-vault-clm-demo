#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 01_deploy_liberty.sh
# Purpose: Installs OpenJDK 17, Open Liberty Runtime, and creates liberty user/service
# ==============================================================================

echo "--- [1/2] Installing Java 17 & System Utilities on RHEL 9 ---"
dnf install -y java-17-openjdk java-17-openjdk-devel curl wget unzip jq openssl python3 python3-pip python3-cryptography python3-requests

echo "--- [2/2] Installing Open Liberty Runtime ---"
WLP_INSTALL_DIR="/opt/ol"
WLP_HOME="$WLP_INSTALL_DIR/wlp"
LIBERTY_VERSION="24.0.0.12"
LIBERTY_ZIP="openliberty-runtime-${LIBERTY_VERSION}.zip"
LIBERTY_URL="https://repo1.maven.org/maven2/io/openliberty/openliberty-runtime/${LIBERTY_VERSION}/${LIBERTY_ZIP}"

# Create liberty service user if not present
if ! id -u wlp >/dev/null 2>&1; then
  useradd -r -m -d /opt/ol -s /sbin/nologin wlp
fi

mkdir -p "$WLP_INSTALL_DIR"

if [ ! -d "$WLP_HOME" ]; then
  echo "[+] Downloading Open Liberty ${LIBERTY_VERSION}..."
  wget -q -O "/tmp/${LIBERTY_ZIP}" "$LIBERTY_URL" || {
    echo "[-] Maven download failed, trying alternative download..."
    curl -sSL -o "/tmp/${LIBERTY_ZIP}" "https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/release/2024-12-04_1100/openliberty-runtime-24.0.0.12.zip"
  }
  echo "[+] Extracting Open Liberty to $WLP_INSTALL_DIR..."
  unzip -q -o "/tmp/${LIBERTY_ZIP}" -d "$WLP_INSTALL_DIR"
  rm -f "/tmp/${LIBERTY_ZIP}"
fi

# Ensure executable scripts and correct read permissions across WLP directory
chmod -R a+rX "$WLP_INSTALL_DIR"
chmod -R 755 "$WLP_HOME/bin" 2>/dev/null || true
chown -R wlp:wlp "$WLP_INSTALL_DIR"

# Create server instance if not present
SERVER_DIR="$WLP_HOME/usr/servers/clmServer"
if [ ! -d "$SERVER_DIR" ]; then
  echo "[+] Creating Open Liberty server 'clmServer'..."
  sudo -u wlp "$WLP_HOME/bin/server" create clmServer || "$WLP_HOME/bin/server" create clmServer
fi

chown -R wlp:wlp "$WLP_INSTALL_DIR"

# Open firewall ports if firewalld is active
if systemctl is-active --quiet firewalld; then
  echo "[+] Opening firewall ports 9443 and 8001 for Open Liberty & Sidecar..."
  firewall-cmd --permanent --add-port=9443/tcp --add-port=8001/tcp --add-port=9080/tcp || true
  firewall-cmd --reload || true
fi

echo "[✓] Open Liberty Runtime installed successfully at $WLP_HOME"
