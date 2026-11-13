# Certificate Lifecycle Management (CLM) on Red Hat Enterprise Linux 9 (RHEL 9 VM)

This directory contains the complete automated deployment, configuration, live rotation testing, and teardown scripts for running **Open Liberty** and **MySQL 8.0** on a **Red Hat Enterprise Linux 9 (RHEL 9) Virtual Machine (VM)**, integrated with **HashiCorp Vault PKI** as the central cryptographic control plane.

---

## 🏛️ RHEL 9 VM Workload Matrix

| Workload | Runtime / Version | Certificate Authority (CA) | Keystore Format | Zero-Downtime Reload Mechanism | Sidecar REST Port |
|---|---|---|---|---|---|
| **Open Liberty** | Open Liberty 24.0.0.12 (Java 17) | Vault Internal PKI (`pki_internal`) | **PKCS12 Keystore (`key.p12`)** | `dynamicUpdate="true"` polled file monitor in `server.xml` | `8001` |
| **MySQL Database** | MySQL Server 8.0 (RHEL 9 AppStream) | Vault Internal PKI (`pki_internal`) | **X.509 PEM (0600 mode)** | SQL `ALTER INSTANCE RELOAD TLS;` without dropping connections | `8002` |

---

## 📂 Directory Structure

```
rhel9-vm/
├── deploy.sh                     # Master RHEL 9 deployment script (installs Open Liberty, Java 17, MySQL)
├── config.sh                     # Master configuration script (Vault integration, certs, systemd agents)
├── teardown.sh                   # Master teardown script (stops services, cleans certs and installations)
├── README.md                     # Step-by-step execution guide and architecture
└── scripts/
    ├── 01_deploy_liberty.sh      # Installs OpenJDK 17 and Open Liberty runtime
    ├── 02_config_liberty.sh      # Configures server.xml, PKCS12 keystore, and clm-liberty-agent systemd daemon
    ├── 03_deploy_mysql.sh        # Installs and enables MySQL 8.0 on RHEL 9
    ├── 04_config_mysql.sh        # Configures MySQL SSL required, reload user, and clm-mysql-agent systemd daemon
    ├── 05_test_rotation.sh       # Live verification and on-demand rotation tester
    └── 06_teardown_all.sh        # Full systemd and directory cleanup
```

---

## 🚀 Execution Guide on RHEL 9 VM

### Prerequisites
1. A fresh or existing **RHEL 9 VM** with root / sudo privileges.
2. Network connectivity to HashiCorp Vault (e.g. running on OpenShift or standalone).
3. Environment variables (optional, defaults to demo values):
   ```bash
   export VAULT_ADDR="http://<VAULT_IP_OR_HOSTNAME>:8200"
   export VAULT_TOKEN="root"
   ```

---

### Step 1: Deploy Middleware Runtimes
Run as root:
```bash
chmod +x deploy.sh config.sh teardown.sh scripts/*.sh
sudo ./deploy.sh
```
* **What it does:** Installs OpenJDK 17, downloads and unpacks Open Liberty 24.0.0.12 into `/opt/ol/wlp`, creates the non-privileged `wlp` user and `clmServer` instance, installs MySQL 8.0 Server via `dnf`, enables `mysqld.service`, and configures `firewalld` ports (9443, 9080, 3306, 8001, 8002).

---

### Step 2: Configure TLS Certificates & Vault Rotation Daemons
Run as root:
```bash
sudo ./config.sh
```
* **What it does:**
  1. **Open Liberty:** Configures `server.xml` with PKCS12 keystore (`key.p12`), enables `dynamicUpdate="true"` with `monitorInterval="2s"`, deploys an IBM Carbon styled sample application, and starts the `clm-liberty-agent.service` daemon (port 8001).
  2. **MySQL 8.0:** Sets `require_secure_transport = ON` in `/etc/my.cnf.d/clm-tls.cnf`, creates the local reload user `clm_admin@localhost`, establishes strict `0600` permissions on `/var/lib/mysql/certs/`, and starts the `clm-mysql-agent.service` daemon (port 8002).
  3. **Initial Issuance:** Both agents request fresh X.509 certificates from Vault PKI, write them to disk, and trigger zero-downtime runtime reloads.

---

### Step 3: Test and Inspect Live Rotations
Run the validation inspector:
```bash
./scripts/05_test_rotation.sh
```
* **What you will see:**
  * Status and active serial numbers for Open Liberty (`https://<RHEL_IP>:9443`) and MySQL (`<RHEL_IP>:3306`).
  * On-demand certificate renewal triggered via REST API.
  * Live OpenSSL TLS handshake verification against Open Liberty.
  * Live MySQL `SHOW STATUS LIKE 'Ssl_server_not_after'` proving zero-downtime TLS context reload via `ALTER INSTANCE RELOAD TLS;`.

---

### Step 4: Teardown & Cleanup
When the demo is complete, run:
```bash
sudo ./teardown.sh
```
* **What it does:** Stops and disables all systemd services (`openliberty.service`, `clm-liberty-agent.service`, `clm-mysql-agent.service`, `mysqld.service`), removes unit files, cleans up `/opt/ol` and `/var/lib/mysql/certs`, and restores the VM to its clean state.
