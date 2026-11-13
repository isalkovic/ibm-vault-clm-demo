#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 05_test_rotation.sh
# Purpose: Real-time CLI verification and live rotation test for RHEL 9 VM
# ==============================================================================

echo "=========================================================================="
echo "   RHEL 9 VM: CLM LIVE ROTATION & TLS VALIDATION INSPECTOR"
echo "=========================================================================="

echo ""
echo "--- [1/2] Testing Open Liberty on RHEL 9 (Port 9443 / Sidecar 8001) ---"
if curl -s http://127.0.0.1:8001/status > /dev/null 2>&1; then
  echo "[+] Querying Liberty CLM Agent status:"
  curl -s http://127.0.0.1:8001/status | jq . || curl -s http://127.0.0.1:8001/status
  echo ""
  echo "[+] Triggering On-Demand Certificate Renewal for Open Liberty..."
  RENEW_RESP=$(curl -s -X POST http://127.0.0.1:8001/renew)
  echo "Response: $RENEW_RESP"
  echo ""
  echo "[+] Testing Open Liberty Live TLS Handshake (Port 9443):"
  echo | openssl s_client -connect 127.0.0.1:9443 -servername localhost 2>/dev/null | openssl x509 -noout -serial -dates -issuer || true
else
  echo "[-] Open Liberty CLM Agent not reachable on port 8001."
fi

echo ""
echo "--- [2/2] Testing MySQL 8.0 on RHEL 9 (Port 3306 / Sidecar 8002) ---"
if curl -s http://127.0.0.1:8002/status > /dev/null 2>&1; then
  echo "[+] Querying MySQL CLM Agent status:"
  curl -s http://127.0.0.1:8002/status | jq . || curl -s http://127.0.0.1:8002/status
  echo ""
  echo "[+] Triggering On-Demand Certificate Renewal for MySQL..."
  RENEW_MYSQL=$(curl -s -X POST http://127.0.0.1:8002/renew)
  echo "Response: $RENEW_MYSQL"
  echo ""
  echo "[+] Querying MySQL Live TLS Status (ALTER INSTANCE RELOAD TLS test):"
  mysql -u clm_admin -e "SHOW STATUS LIKE 'Ssl_server_not_after'; SHOW STATUS LIKE 'Ssl_cipher'; SHOW STATUS LIKE 'Ssl_version';" 2>/dev/null || mysql -e "SHOW STATUS LIKE 'Ssl_server_not_after'; SHOW STATUS LIKE 'Ssl_cipher'; SHOW STATUS LIKE 'Ssl_version';" || true
else
  echo "[-] MySQL CLM Agent not reachable on port 8002."
fi

echo ""
echo "=========================================================================="
echo " [✓] RHEL 9 VM Live Rotation & Verification Complete!"
echo "=========================================================================="
