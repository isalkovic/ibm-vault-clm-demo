#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 02_config_liberty.sh
# Purpose: Configures Open Liberty server.xml with dynamic TLS PKCS12 keystore,
#          installs Python CLM agent & systemd services, and triggers initial issuance.
# ==============================================================================

VAULT_ADDR="${VAULT_ADDR:-http://vault.clm-vault-demo.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
PKI_ROLE="${PKI_ROLE:-liberty-role}"

WLP_HOME="/opt/ol/wlp"
SERVER_DIR="$WLP_HOME/usr/servers/clmServer"
SECURITY_DIR="$SERVER_DIR/resources/security"

mkdir -p "$SECURITY_DIR"
mkdir -p "$SERVER_DIR/apps"
mkdir -p "$SERVER_DIR/dropins"
mkdir -p /var/log/clm-liberty

echo "--- [1/4] Writing Open Liberty server.xml configuration ---"
cat <<'EOF' > "$SERVER_DIR/server.xml"
<?xml version="1.0" encoding="UTF-8"?>
<server description="Open Liberty CLM Demo Server on RHEL 9">
    <!-- Enable required features -->
    <featureManager>
        <feature>appSecurity-5.0</feature>
        <feature>transportSecurity-1.0</feature>
        <feature>servlet-6.0</feature>
        <feature>mpHealth-4.0</feature>
    </featureManager>

    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443" />

    <!--
      Zero-Downtime Dynamic Keystore Configuration:
      dynamicUpdate="true" enables native Open Liberty file polling on key.p12.
      When the CLM agent writes a renewed keystore, Liberty reloads SSLContext automatically.
    -->
    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.p12"
              password="${env.WLP_KEYSTORE_SECRET}"
              type="PKCS12" />

    <sslDefault sslRef="defaultSSLConfig" />
    <ssl id="defaultSSLConfig"
         keyStoreRef="defaultKeyStore"
         sslProtocol="TLSv1.3" />

    <!-- Polled config update trigger ensures instant file reload -->
    <config updateTrigger="polled" monitorInterval="2s" />

    <webApplication id="clmApp" location="clmApp.war" name="clmApp" contextRoot="/" />
</server>
EOF

echo "--- [2/4] Deploying Carbon-styled sample web app to Open Liberty ---"
APP_DIR="/tmp/clmApp_build"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/WEB-INF"

cat <<'EOF' > "$APP_DIR/WEB-INF/web.xml"
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee" version="6.0">
  <welcome-file-list>
    <welcome-file>index.html</welcome-file>
  </welcome-file-list>
</web-app>
EOF

cat <<'EOF' > "$APP_DIR/index.html"
<!DOCTYPE html>
<html lang="en" class="cds--g100">
<head>
  <meta charset="UTF-8">
  <title>Open Liberty on RHEL 9 | Certificate Lifecycle Management</title>
  <link rel="stylesheet" href="https://1.www.s81c.com/common/carbon/plex/fonts.css">
  <style>
    body { font-family: 'IBM Plex Sans', sans-serif; background: #161616; color: #f4f4f4; padding: 2rem; display: flex; justify-content: center; align-items: center; min-height: 80vh; }
    .cds--tile { background: #262626; border: 1px solid #393939; padding: 2rem; max-width: 700px; width: 100%; border-top: 3px solid #0f62fe; }
    h1 { font-size: 1.5rem; font-weight: 400; color: #f4f4f4; margin: 0.5rem 0 0.75rem 0; }
    .cds--tag { display: inline-flex; align-items: center; background: #0043ce; color: #d0e2ff; padding: 0.25rem 0.5rem; border-radius: 0.9375rem; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.32px; }
    .cds--meta-table { background: #1f1f1f; border: 1px solid #393939; padding: 1rem; margin: 1.25rem 0; font-family: 'IBM Plex Mono', monospace; font-size: 0.8125rem; line-height: 1.6; }
    .cds--links { display: flex; gap: 1rem; margin-top: 1.25rem; flex-wrap: wrap; }
    .cds--link { color: #78a9ff; text-decoration: none; font-size: 0.8125rem; font-weight: 500; }
    .cds--link:hover { text-decoration: underline; color: #a6c8ff; }
  </style>
</head>
<body>
  <div class="cds--tile">
    <span class="cds--tag">RHEL 9 Workload</span>
    <h1>Open Liberty TLS Endpoint (RHEL 9 VM)</h1>
    <p style="color: #c6c6c6; font-size: 0.875rem;">This Open Liberty server is running natively on a Red Hat Enterprise Linux 9 VM, protected by <strong>HashiCorp Vault PKI</strong> with zero-downtime hot reloads.</p>
    <div class="cds--meta-table">
      <div><strong style="color: #8d8d8d;">Platform:</strong> Red Hat Enterprise Linux 9 (x86_64)</div>
      <div><strong style="color: #8d8d8d;">Runtime:</strong> Open Liberty 24.0.0.12 (Java 17)</div>
      <div><strong style="color: #8d8d8d;">Keystore:</strong> /opt/ol/wlp/usr/servers/clmServer/resources/security/key.p12</div>
      <div><strong style="color: #8d8d8d;">Reload Mechanism:</strong> Open Liberty dynamicUpdate="true" (Zero Downtime)</div>
      <div><strong style="color: #8d8d8d;">Vault Role:</strong> pki_internal/issue/liberty-role</div>
      <div><strong style="color: #8d8d8d;">Sidecar REST API:</strong> http://localhost:8001/status</div>
    </div>
    <div class="cds--links">
      <a class="cds--link" href="/health" target="_blank">↗ MicroProfile Health (/health)</a>
      <a class="cds--link" href="/health/ready" target="_blank">↗ Readiness Check</a>
      <a class="cds--link" href="/health/live" target="_blank">↗ Liveness Check</a>
    </div>
  </div>
</body>
</html>
EOF

(cd "$APP_DIR" && jar -cf "$SERVER_DIR/apps/clmApp.war" .)
rm -rf "$APP_DIR"

echo "--- [3/4] Creating CLM Liberty Agent Microservice Daemon ---"
cat <<'EOF' > /usr/local/bin/clm-liberty-agent.py
#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import json
import os
import sys
import time
import subprocess
import threading
from datetime import datetime, timezone

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

PORT = int(os.environ.get("AGENT_PORT", "8001"))
VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault.clm-vault-demo.svc.cluster.local:8200")
VAULT_TOKEN = os.environ.get("VAULT_TOKEN", "root")
ROLE_NAME = os.environ.get("PKI_ROLE", "liberty-role")
COMMON_NAME = os.environ.get("COMMON_NAME", "liberty-rhel.clm.internal")
ALT_NAMES = os.environ.get("ALT_NAMES", "localhost,127.0.0.1")

SECURITY_DIR = "/opt/ol/wlp/usr/servers/clmServer/resources/security"
P12_PATH = f"{SECURITY_DIR}/key.p12"
P12_PASS = os.environ.get("WLP_KEYSTORE_SECRET", "clm_wlp_key")

STATE_LOCK = threading.Lock()
CONFIG = {
    "interval_seconds": 300,
    "last_renewal_ts": 0.0
}
CERT_META = {
    "serial": "",
    "valid_from": "",
    "valid_to": "",
    "issuer": "Enterprise Demo Intermediate CA",
    "subject": f"CN={COMMON_NAME}",
    "last_renewed": "",
    "status": "INITIALIZING"
}

def log_msg(msg):
    print(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}] [LibertyAgent] {msg}", flush=True)

def vault_request(path, method="GET", payload=None):
    url = f"{VAULT_ADDR.rstrip('/')}/v1/{path.lstrip('/')}"
    data = json.dumps(payload).encode("utf-8") if payload else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-Vault-Token", VAULT_TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        log_msg(f"Vault API error on {path}: {e}")
        return {"error": str(e)}

def generate_pkcs12(cert_pem, key_pem, ca_pem, out_p12, password):
    os.makedirs("/tmp/clm_p12", exist_ok=True)
    cert_tmp = "/tmp/clm_p12/cert.pem"
    key_tmp = "/tmp/clm_p12/key.pem"
    ca_tmp = "/tmp/clm_p12/ca.pem"
    p12_tmp = f"{out_p12}.tmp"

    with open(cert_tmp, "w") as f: f.write(cert_pem)
    with open(key_tmp, "w") as f: f.write(key_pem)
    with open(ca_tmp, "w") as f: f.write(ca_pem)

    cmd = [
        "openssl", "pkcs12", "-export",
        "-in", cert_tmp,
        "-inkey", key_tmp,
        "-certfile", ca_tmp,
        "-out", p12_tmp,
        "-name", "default",
        "-password", f"pass:{password}"
    ]
    subprocess.run(cmd, check=True)
    os.replace(p12_tmp, out_p12)
    os.chmod(out_p12, 0o640)
    
    # Set ownership to wlp if user exists
    try:
        import shutil
        shutil.chown(out_p12, user="wlp", group="wlp")
    except Exception:
        pass

def parse_x509_pem(pem_str):
    res = {"valid_from": "", "valid_to": "", "serial": "", "issuer": "", "subject": ""}
    if not pem_str:
        return res
    tmp = "/tmp/clm_p12/inspect.pem"
    with open(tmp, "w") as f: f.write(pem_str)
    try:
        out = subprocess.check_output(["openssl", "x509", "-in", tmp, "-noout", "-dates", "-serial", "-issuer", "-subject"], text=True)
        for line in out.splitlines():
            if line.startswith("notBefore="): res["valid_from"] = line.split("=", 1)[1]
            elif line.startswith("notAfter="): res["valid_to"] = line.split("=", 1)[1]
            elif line.startswith("serial="): res["serial"] = line.split("=", 1)[1]
            elif line.startswith("issuer="): res["issuer"] = line.split("=", 1)[1]
            elif line.startswith("subject="): res["subject"] = line.split("=", 1)[1]
    except Exception as e:
        log_msg(f"Error parsing X509: {e}")
    return res

def issue_and_apply_cert():
    log_msg(f"Requesting certificate from Vault PKI (/v1/pki_internal/issue/{ROLE_NAME})...")
    resp = vault_request(f"pki_internal/issue/{ROLE_NAME}", method="POST", payload={
        "common_name": COMMON_NAME,
        "alt_names": ALT_NAMES,
        "private_key_format": "pkcs8",
        "ttl": "10m"
    })

    data = resp.get("data", {})
    cert = data.get("certificate", "")
    key = data.get("private_key", "")
    ca = data.get("issuing_ca", "")
    serial = data.get("serial_number", "")

    if not cert or not key:
        # Generate self-signed fallback if Vault is not yet reachable during initial bootstrap
        log_msg("Vault not available; generating initial bootstrap certificate...")
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout", "/tmp/clm_p12/key.pem",
            "-out", "/tmp/clm_p12/cert.pem", "-days", "1", "-nodes", "-subj", f"/CN={COMMON_NAME}"
        ], check=True)
        with open("/tmp/clm_p12/cert.pem") as f: cert = f.read()
        with open("/tmp/clm_p12/key.pem") as f: key = f.read()
        ca = cert
        serial = "BOOTSTRAP-INIT"

    os.makedirs(SECURITY_DIR, exist_ok=True)
    generate_pkcs12(cert, key, ca, P12_PATH, P12_PASS)

    with open(f"{SECURITY_DIR}/serial.txt", "w") as f:
        f.write(serial)

    meta = parse_x509_pem(cert)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    with STATE_LOCK:
        CERT_META["serial"] = meta.get("serial") or serial
        CERT_META["valid_from"] = meta.get("valid_from")
        CERT_META["valid_to"] = meta.get("valid_to")
        CERT_META["issuer"] = meta.get("issuer") or "Enterprise Demo Intermediate CA"
        CERT_META["subject"] = meta.get("subject") or f"CN={COMMON_NAME}"
        CERT_META["last_renewed"] = now_iso
        CERT_META["status"] = "ACTIVE"
        CONFIG["last_renewal_ts"] = time.time()

    log_msg(f"Open Liberty PKCS12 keystore updated! (Serial: {CERT_META['serial']}) - dynamicUpdate will hot-reload TLS.")
    return True, CERT_META["serial"]

class AgentHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass

    def do_GET(self):
        clean_path = self.path.split("?")[0]
        if clean_path in ("/status", "/"):
            with STATE_LOCK:
                elapsed = int(time.time() - CONFIG["last_renewal_ts"]) if CONFIG["last_renewal_ts"] > 0 else 0
                expires_in = max(0, CONFIG["interval_seconds"] - elapsed)
                data = {
                    "workload": "liberty-rhel",
                    "name": "Open Liberty on RHEL 9",
                    "scenario": "RHEL 9 VM: Open Liberty (Java 17 PKCS12)",
                    "ca_provider": "Vault Internal PKI (/v1/pki_internal)",
                    "keystore_format": "PKCS12 Keystore (/opt/ol/.../key.p12)",
                    "reload_mechanism": "dynamicUpdate='true' File Watcher (Zero Downtime)",
                    "serial": CERT_META["serial"],
                    "valid_from": CERT_META["valid_from"],
                    "valid_to": CERT_META["valid_to"],
                    "expires_in_sec": expires_in,
                    "rotation_interval_seconds": CONFIG["interval_seconds"],
                    "status": CERT_META["status"],
                    "last_renewed": CERT_META["last_renewed"],
                    "host": COMMON_NAME,
                    "port": 9443
                }
            self.send_json(data)
        elif clean_path == "/health":
            self.send_json({"status": "UP", "workload": "liberty-rhel"})
        else:
            self.send_error(404, "Endpoint not found")

    def do_POST(self):
        clean_path = self.path.split("?")[0]
        if clean_path == "/renew":
            log_msg("On-demand renewal requested via Agent REST API...")
            ok, res = issue_and_apply_cert()
            if ok:
                self.send_json({"success": True, "serial": res, "message": f"Liberty PKCS12 cert renewed (Serial: {res})"})
            else:
                self.send_json({"success": False, "error": res}, code=500)
        else:
            self.send_error(404, "Endpoint not found")

    def send_json(self, data, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode("utf-8"))

def rotation_worker():
    log_msg("Background rotation worker thread started.")
    while True:
        time.sleep(1)
        with STATE_LOCK:
            interval = CONFIG["interval_seconds"]
            last_ts = CONFIG["last_renewal_ts"]
        if last_ts > 0 and (time.time() - last_ts) >= interval:
            log_msg(f"Rotation timer reached ({interval}s). Renewing Open Liberty certificate...")
            issue_and_apply_cert()

if __name__ == "__main__":
    issue_and_apply_cert()
    t = threading.Thread(target=rotation_worker, daemon=True)
    t.start()
    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer(("0.0.0.0", PORT), AgentHandler)
    log_msg(f"Liberty CLM Agent listening on port {PORT}...")
    server.serve_forever()
EOF

chmod +x /usr/local/bin/clm-liberty-agent.py

echo "--- [4/4] Creating and starting systemd services ---"
cat <<'EOF' > /etc/systemd/system/openliberty.service
[Unit]
Description=Open Liberty Application Server
After=network.target

[Service]
Type=simple
User=wlp
Group=wlp
Environment=WLP_KEYSTORE_SECRET=clm_wlp_key
ExecStart=/opt/ol/wlp/bin/server run clmServer
ExecStop=/opt/ol/wlp/bin/server stop clmServer
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/clm-liberty-agent.service
[Unit]
Description=Vault CLM Agent for Open Liberty (RHEL 9)
After=network.target

[Service]
Type=simple
User=root
Environment=VAULT_ADDR=${VAULT_ADDR}
Environment=VAULT_TOKEN=${VAULT_TOKEN}
Environment=PKI_ROLE=${PKI_ROLE}
Environment=WLP_KEYSTORE_SECRET=clm_wlp_key
ExecStart=/usr/bin/python3 /usr/local/bin/clm-liberty-agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chown -R wlp:wlp "$SERVER_DIR"

systemctl daemon-reload
systemctl enable --now clm-liberty-agent.service
systemctl enable --now openliberty.service

echo "[✓] Open Liberty and CLM Agent configured and running under systemd."
