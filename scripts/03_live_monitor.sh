#!/usr/bin/env bash
set -euo pipefail

# Script: 03_live_monitor.sh
# Purpose: Real-time Live Certificate Rotation and Expiration Inspector for all OpenShift scenarios.

NAMESPACE="${NAMESPACE:-clm-vault-demo}"

echo "=========================================================================="
echo "   OPENSHIFT CLM DEMO: LIVE CERTIFICATE ROTATION MONITOR"
echo "=========================================================================="
echo "Press [CTRL+C] to stop."
echo ""

while true; do
  CLEAR_SCREEN=$(clear 2>/dev/null || true)
  printf "%s\n" "$CLEAR_SCREEN"
  echo "=========================================================================="
  echo "   CLM LIVE INSPECTOR | Red Hat OpenShift (Namespace: $NAMESPACE)"
  echo "   Current Cluster Time: $(date)"
  echo "=========================================================================="
  echo ""

  # 1. Open Liberty Status
  LIBERTY_POD=$(oc get pod -n "$NAMESPACE" -l app=liberty -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$LIBERTY_POD" ]; then
    echo "--- [Scenario 1: Open Liberty (Internal Vault PKI)] ---"
    SERIAL=$(oc exec -n "$NAMESPACE" "$LIBERTY_POD" -c vault-cert-agent -- cat /config/resources/security/serial.txt 2>/dev/null || echo "Initializing...")
    echo "Pod: $LIBERTY_POD"
    echo "TLS Certificate Serial: $SERIAL"
    echo "Keystore Format: Native PEM (/config/resources/security/tls.crt, tls.key)"
    echo "Reload Mechanism: Open Liberty dynamicUpdate=true (Zero Downtime)"
  fi
  echo ""

  # 2. Apache Tomcat Status
  TOMCAT_POD=$(oc get pod -n "$NAMESPACE" -l app=tomcat -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$TOMCAT_POD" ]; then
    echo "--- [Scenario 2: Apache Tomcat (Let's Encrypt Staging / Certbot)] ---"
    SERIAL=$(oc exec -n "$NAMESPACE" "$TOMCAT_POD" -c certbot-sync-sidecar -- cat /usr/local/tomcat/conf/ssl/serial.txt 2>/dev/null || echo "Initializing...")
    echo "Pod: $TOMCAT_POD"
    echo "TLS Certificate Serial: $SERIAL"
    echo "Tracking: Synced to Vault Central KV Inventory (/v1/kv/data/certificates/tomcat/current)"
    echo "Reload Mechanism: Certbot Hook -> SSLHostConfig Live Refresh"
  fi
  echo ""

  # 3. NGINX Status
  NGINX_POD=$(oc get pod -n "$NAMESPACE" -l app=nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$NGINX_POD" ]; then
    echo "--- [Scenario 3: NGINX Proxy (Vault Native ACME Protocol)] ---"
    SERIAL=$(oc exec -n "$NAMESPACE" "$NGINX_POD" -c acme-renewal-sidecar -- cat /etc/nginx/ssl/serial.txt 2>/dev/null || echo "Initializing...")
    echo "Pod: $NGINX_POD"
    echo "TLS Certificate Serial: $SERIAL"
    echo "Protocol: ACME RFC 8555 Directory (Vault PKI ACME endpoint)"
    echo "Reload Mechanism: Graceful nginx -s reload"
  fi
  echo ""

  # 6. PostgreSQL Status
  PG_POD=$(oc get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$PG_POD" ]; then
    echo "--- [Scenario 6: PostgreSQL Database (TLS Rotation & pg_reload_conf)] ---"
    SERIAL=$(oc exec -n "$NAMESPACE" "$PG_POD" -c cert-rotation-sidecar -- cat /var/lib/pgsql/certs/serial.txt 2>/dev/null || echo "Initializing...")
    echo "Pod: $PG_POD"
    echo "TLS Certificate Serial: $SERIAL (Mode: SSL Required, 0600 permissions)"
    echo "Reload Mechanism: Vault Agent Sidecar -> SELECT pg_reload_conf()"
  fi
  echo ""

  echo "=========================================================================="
  echo "Auto-refreshing every 60 seconds... (Observe Serial numbers rolling over)"
  sleep 60
done
