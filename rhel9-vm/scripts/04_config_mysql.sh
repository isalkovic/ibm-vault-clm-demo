#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 04_config_mysql.sh
# Purpose: Configures MySQL TLS (SSL Required), creates CLM reload user,
#          installs Python CLM agent, and tests live ALTER INSTANCE RELOAD TLS.
# ==============================================================================

VAULT_ADDR="${VAULT_ADDR:-http://vault.clm-vault-demo.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
PKI_ROLE="${PKI_ROLE:-mysql-role}"

CERTS_DIR="/var/lib/mysql/certs"
mkdir -p "$CERTS_DIR"
chown -R mysql:mysql "$CERTS_DIR"
chmod 700 "$CERTS_DIR"

echo "--- [1/4] Configuring MySQL SSL/TLS in /etc/my.cnf.d/clm-tls.cnf ---"
cat <<'EOF' > /etc/my.cnf.d/clm-tls.cnf
[mysqld]
require_secure_transport = ON
ssl_ca = /var/lib/mysql/certs/ca.pem
ssl_cert = /var/lib/mysql/certs/server-cert.pem
ssl_key = /var/lib/mysql/certs/server-key.pem
tls_version = TLSv1.2,TLSv1.3
EOF

echo "--- [2/4] Setting up CLM reload user in MySQL ---"
# Create admin user for non-interactive ALTER INSTANCE RELOAD TLS via local socket
mysql -u root <<'EOF' || true
CREATE USER IF NOT EXISTS 'clm_admin'@'localhost' IDENTIFIED WITH auth_socket;
GRANT RELOAD, SYSTEM_VARIABLES_ADMIN ON *.* TO 'clm_admin'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "--- [3/4] Creating CLM MySQL Agent Microservice Daemon ---"
cat <<'EOF' > /usr/local/bin/clm-mysql-agent.py
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

PORT = int(os.environ.get("AGENT_PORT", "8002"))
VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault.clm-vault-demo.svc.cluster.local:8200")
VAULT_TOKEN = os.environ.get("VAULT_TOKEN", "root")
ROLE_NAME = os.environ.get("PKI_ROLE", "mysql-role")
COMMON_NAME = os.environ.get("COMMON_NAME", "mysql-rhel.clm.internal")
ALT_NAMES = os.environ.get("ALT_NAMES", "localhost,127.0.0.1")

CERTS_DIR = "/var/lib/mysql/certs"

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
    print(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}] [MySQLAgent] {msg}", flush=True)

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

def parse_x509_pem(pem_str):
    res = {"valid_from": "", "valid_to": "", "serial": "", "issuer": "", "subject": ""}
    if not pem_str:
        return res
    tmp = "/tmp/mysql_inspect.pem"
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

def reload_mysql_tls():
    try:
        cmd = ["mysql", "-u", "clm_admin", "-e", "ALTER INSTANCE RELOAD TLS;"]
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log_msg("Executed 'ALTER INSTANCE RELOAD TLS;' - MySQL TLS context updated with Zero Downtime!")
        return True
    except Exception as e:
        # Fallback to root socket
        try:
            subprocess.run(["mysql", "-e", "ALTER INSTANCE RELOAD TLS;"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            log_msg("Executed 'ALTER INSTANCE RELOAD TLS;' via root socket - MySQL TLS updated!")
            return True
        except Exception as e2:
            log_msg(f"Warning: ALTER INSTANCE RELOAD TLS returned: {e2}")
            return False

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
        log_msg("Vault not available; generating initial bootstrap certificate...")
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout", "/tmp/mysql_boot_key.pem",
            "-out", "/tmp/mysql_boot_cert.pem", "-days", "1", "-nodes", "-subj", f"/CN={COMMON_NAME}"
        ], check=True)
        with open("/tmp/mysql_boot_cert.pem") as f: cert = f.read()
        with open("/tmp/mysql_boot_key.pem") as f: key = f.read()
        ca = cert
        serial = "BOOTSTRAP-INIT"

    os.makedirs(CERTS_DIR, exist_ok=True)
    
    cert_file = f"{CERTS_DIR}/server-cert.pem"
    key_file = f"{CERTS_DIR}/server-key.pem"
    ca_file = f"{CERTS_DIR}/ca.pem"
    serial_file = f"{CERTS_DIR}/serial.txt"

    with open(f"{cert_file}.tmp", "w") as f: f.write(cert)
    with open(f"{key_file}.tmp", "w") as f: f.write(key)
    with open(f"{ca_file}.tmp", "w") as f: f.write(ca)
    with open(f"{serial_file}.tmp", "w") as f: f.write(serial)

    os.replace(f"{cert_file}.tmp", cert_file)
    os.replace(f"{key_file}.tmp", key_file)
    os.replace(f"{ca_file}.tmp", ca_file)
    os.replace(f"{serial_file}.tmp", serial_file)

    for p in [cert_file, key_file, ca_file, serial_file]:
        os.chmod(p, 0o600)
        try:
            import shutil
            shutil.chown(p, user="mysql", group="mysql")
        except Exception:
            pass

    # Trigger Zero-Downtime Hot Reload
    reload_mysql_tls()

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

    log_msg(f"MySQL TLS certificate updated! (Serial: {CERT_META['serial']})")
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
                    "workload": "mysql-rhel",
                    "name": "MySQL 8.0 on RHEL 9",
                    "scenario": "RHEL 9 VM: MySQL Database TLS (0600 mode)",
                    "ca_provider": "Vault Internal PKI (/v1/pki_internal)",
                    "keystore_format": "X.509 PEM (/var/lib/mysql/certs/)",
                    "reload_mechanism": "ALTER INSTANCE RELOAD TLS; (Zero Downtime)",
                    "serial": CERT_META["serial"],
                    "valid_from": CERT_META["valid_from"],
                    "valid_to": CERT_META["valid_to"],
                    "expires_in_sec": expires_in,
                    "rotation_interval_seconds": CONFIG["interval_seconds"],
                    "status": CERT_META["status"],
                    "last_renewed": CERT_META["last_renewed"],
                    "host": COMMON_NAME,
                    "port": 3306
                }
            self.send_json(data)
        elif clean_path == "/health":
            self.send_json({"status": "UP", "workload": "mysql-rhel"})
        else:
            self.send_error(404, "Endpoint not found")

    def do_POST(self):
        clean_path = self.path.split("?")[0]
        if clean_path == "/renew":
            log_msg("On-demand renewal requested via Agent REST API...")
            ok, res = issue_and_apply_cert()
            if ok:
                self.send_json({"success": True, "serial": res, "message": f"MySQL TLS cert renewed (Serial: {res})"})
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
            log_msg(f"Rotation timer reached ({interval}s). Renewing MySQL certificate...")
            issue_and_apply_cert()

if __name__ == "__main__":
    issue_and_apply_cert()
    t = threading.Thread(target=rotation_worker, daemon=True)
    t.start()
    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer(("0.0.0.0", PORT), AgentHandler)
    log_msg(f"MySQL CLM Agent listening on port {PORT}...")
    server.serve_forever()
EOF

chmod +x /usr/local/bin/clm-mysql-agent.py

echo "--- [4/4] Creating and starting systemd service for MySQL CLM Agent ---"
cat <<'EOF' > /etc/systemd/system/clm-mysql-agent.service
[Unit]
Description=Vault CLM Agent for MySQL (RHEL 9)
After=network.target mysqld.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/clm-mysql-agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart mysqld
systemctl enable --now clm-mysql-agent.service

echo "[✓] MySQL 8.0 SSL/TLS & CLM Agent configured and running under systemd."
