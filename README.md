# Certificate Lifecycle Management (CLM) Demo on Red Hat OpenShift

This repository contains the complete Proof of Value (PoV) and Demo environment for **Certificate Lifecycle Management (CLM)** with **HashiCorp Vault** as the central cryptographic control plane, running on **Red Hat OpenShift Container Platform (OCP)**.

---

## 🏛️ Architecture & Scenarios Matrix

| Scenario # | Workload / App | Platform | Certificate Authority (CA) | Keystore Format | Zero-Downtime Reload Hook |
|---|---|---|---|---|---|
| **Scenario 1** | **Open Liberty** | **Red Hat OpenShift** | **Vault Internal PKI** (`pki_internal`) | **PKCS12 (`key.p12`)** | Open Liberty `dynamicUpdate="true"` in `server.xml` |
| **Scenario 2** | **Apache Tomcat** | **Red Hat OpenShift** | **Vault Public CA Proxy** (`pki_external`) | **PEM / PKCS12** | Sidecar triggers dynamic Tomcat `SSLHostConfig` rebind |
| **Scenario 3** | **NGINX Reverse Proxy** | **Red Hat OpenShift** | **Vault Native ACME Server** (`/v1/pki/acme`) | **X.509 PEM** | Certbot deploy hook triggers `nginx -s reload` |
| **Scenario 6** | **PostgreSQL DB** | **Red Hat OpenShift** | **Vault Internal PKI** (`pki_internal`) | **X.509 PEM (`0600`)** | Sidecar triggers SQL `SELECT pg_reload_conf();` |
| **Scenario 7** | **Code / Artifact Signing**| **CI/CD Pipeline** | **Vault Transit Engine** (`/transit`) | **RSA-4096 / SHA-256** | Private keys never leave Vault; sign/verify via API |
| **Scenario 8** | **Open Liberty on VM** | **RHEL 9 VM (Standalone)** | **Vault Internal PKI** (`pki_internal`) | **PKCS12 (`key.p12`)** | `clm-liberty-agent` systemd daemon + `dynamicUpdate="true"` |
| **Scenario 9** | **MySQL 8.0 on VM** | **RHEL 9 VM (Standalone)** | **Vault Internal PKI** (`pki_internal`) | **X.509 PEM (`0600`)** | `clm-mysql-agent` daemon + `ALTER INSTANCE RELOAD TLS;` |

---

## 📂 Project Structure

```
clm-openshift-demo/
├── deploy.sh                     # Master OpenShift deployment script
├── teardown.sh                   # Cleanup script (deletes pods and namespace)
├── README.md                     # Architecture and demo execution guide
├── scripts/
│   ├── 00_prereqs.sh             # Validates OpenShift CLI and login status
│   ├── 01_vault_init_pki.sh      # Initializes Vault PKI, ACME, Transit, & K8s Auth
│   ├── 02_demo_code_signing.sh   # Executes Scenario 7 (Artifact/JAR signing & tampering demo)
│   └── 03_live_monitor.sh        # Real-time multi-workload certificate rotation watcher
├── rhel9-vm/                     # RHEL 9 Standalone VM Deployments (Open Liberty & MySQL)
│   ├── deploy.sh                 # Installs Open Liberty runtime, Java 17, and MySQL 8.0 on RHEL 9
│   ├── config.sh                 # Sets up TLS certificates, keystores, and systemd rotation daemons
│   ├── teardown.sh               # Stops daemons, removes packages, and cleans directories
│   ├── README.md                 # Complete RHEL 9 VM setup and live rotation guide
│   └── scripts/                  # Individual deployment, configuration, and verification scripts
└── k8s/
    ├── 00_namespace_rbac.yaml    # OpenShift Namespace, ServiceAccounts, RBAC bindings
    ├── 01_vault.yaml             # HashiCorp Vault Server Deployment & OpenShift Route
    ├── 02_liberty.yaml           # Scenario 1: Open Liberty + Vault PKI PKCS12 Keystore & UI
    ├── 03_tomcat.yaml            # Scenario 2: Apache Tomcat + Pattern A: Vault Public CA Proxy (Let's Encrypt/DigiCert) & UI
    ├── 04_nginx_acme.yaml        # Scenario 3: NGINX + Vault Native ACME Server & UI
    ├── 05_postgres.yaml          # Scenario 6: PostgreSQL Database + TLS pg_reload_conf
    └── 06_clm_dashboard.yaml     # Central CLM Dashboard & Control Center UI / REST API
```

---

## 🚀 Quick Start Guide

### Prerequisites
1. Access to an OpenShift 4.x cluster.
2. `oc` command-line tool installed and logged in (`oc login`).

### 1. Deploy the Environment
Run the master deploy script:
```bash
chmod +x deploy.sh teardown.sh scripts/*.sh
./deploy.sh
```

This script will:
1. Create the `clm-vault-demo` project and necessary ServiceAccounts with `restricted-v2` SCC compliance.
2. Deploy HashiCorp Vault and initialize Root/Intermediate PKI, ACME endpoints, Transit keys, and Kubernetes Auth.
3. Deploy all 4 running containerized workloads (Open Liberty, Apache Tomcat, NGINX, PostgreSQL).
4. Configure **5-minute rotation intervals** (TTL: 10m, rotation every 300s) so certificate renewals and reloads happen smoothly during your demo.

---

### 2. Live Demo Presentation Workflows

#### A. Multi-Workload Live Certificate Rotation Monitor
Open a terminal and run:
```bash
./scripts/03_live_monitor.sh
```
* **What to observe:** Watch the serial numbers update in real-time every 5 minutes across Open Liberty, Tomcat, NGINX, and PostgreSQL without dropping connections or restarting the pods.

#### B. Scenario 7: Code / JAR Signing & Tampering Protection
Open another terminal and run:
```bash
./scripts/02_demo_code_signing.sh
```
* **What to observe:**
  1. A sample Java JAR / binary artifact is hashed with SHA-256.
  2. The hash is sent to Vault Transit Engine, which signs it with an HSM/Transit-protected RSA-4096 private key.
  3. Signature is verified successfully.
  4. The script simulates a malicious supply chain tampering attempt (modifying 1 byte), and shows Vault instantly rejecting the signature.

#### C. Central CLM Monitoring & Management Dashboard (Nadzorni Centar)
Access the central control UI:
```bash
oc get route clm-dashboard -n clm-vault-demo -o jsonpath='{.spec.host}'
```
* **Central CLM Dashboard URL:** `https://clm-dashboard-clm-vault-demo.apps.<cluster>/`

**Dashboard Capabilities:**
1. **Real-time Certificate Overview:** Live serial numbers, validity windows, countdown progress bars, and hot-reload mechanisms for Open Liberty, Apache Tomcat, NGINX, PostgreSQL, and Vault Transit.
2. **On-Demand Immediate Renewal ("Obnovi certifikat odmah"):** Triggers instant certificate rotation and hot-reload with zero downtime directly from the UI.
3. **Dynamic Scheduling ("Postavi interval rotacije"):** Change rotation intervals (1m, 3m, 5m, 10m, 1h, custom) on the fly without re-deploying pods.
4. **Live TLS Probing ("Testiraj TLS vezu"):** Executes live socket TLS handshakes against services to verify on-the-wire certificates.
5. **Interactive Code Signing & Tamper Demo:** Test Scenario 7 software supply chain signing and simulate tamper attacks with instant cryptographic rejection.
6. **Central Audit Log:** Visual history of all issuance, renewal, and verification events.

#### D. Visual Workload Endpoints
* **Open Liberty:** `https://liberty-clm-vault-demo.apps.<cluster>/`
* **Apache Tomcat:** `https://tomcat-clm-vault-demo.apps.<cluster>/`
* **NGINX Proxy:** `https://nginx-clm-vault-demo.apps.<cluster>/`
* **Vault Console:** `https://vault-clm-vault-demo.apps.<cluster>/ui`

---

### 3. Cleanup & Teardown
When the demo is complete, clean up all cluster resources with:
```bash
./teardown.sh
```
