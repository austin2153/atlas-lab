# HashiCorp Vault

## Reference

| Resource | Link |
|---|---|
| Vault docs | https://developer.hashicorp.com/vault/docs |
| Releases | https://releases.hashicorp.com/vault/ |
| Raft storage | https://developer.hashicorp.com/vault/docs/configuration/storage/raft |
| PKI secrets engine | https://developer.hashicorp.com/vault/docs/secrets/pki |
| AppRole auth | https://developer.hashicorp.com/vault/docs/auth/approle |
| Kubernetes auth | https://developer.hashicorp.com/vault/docs/auth/kubernetes |
| Snapshot auto | https://developer.hashicorp.com/vault/docs/commands/operator/raft#snapshot-auto |
| Alpine Linux wiki | https://wiki.alpinelinux.org/ |

**Currently installed:** Vault v2.2.1 on Alpine Linux 3.24 (`vault.atlas.local`, `192.168.20.15`)

To check the installed version on the VM:
```bash
ssh root@vault.atlas.local vault version
```

To find the latest release before upgrading:
```bash
curl -s https://releases.hashicorp.com/vault/ | grep -oE 'vault/[0-9]+\.[0-9]+\.[0-9]+' | head -1
```

---

Vault is the lab's secrets store and PKI. It holds credentials, API keys, and certificates so they never live in plaintext in a config file, a Git repo, or an Ansible variable. It also acts as the lab's Certificate Authority — every service in the lab gets a cert from Vault, browser warnings go away, and the whole thing mirrors how Vault PKI is used in enterprise environments.

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Edition | Community (open source) | No enterprise features needed |
| Deployment | Single VM on Proxmox | Outside the Talos cluster: Vault holds the cluster's own secrets, so it must not depend on the cluster to function |
| OS | Alpine Linux | Minimal footprint; no unnecessary attack surface |
| Storage | Integrated (Raft) | No external dependency; single-node Raft is fine for one node |
| HA | Single node for now | All Proxmox VMs are on the same host anyway; scale to three with Tiny #2/#3 |
| Unsealing | Manual for now | Revisit once comfortable with Vault; auto-unseal (cloud KMS, TPM) can be added later |
| TLS bootstrap | Temporary self-signed cert | Gets Vault running so PKI can be configured; replaced by a Vault-issued cert in the same session |
| PKI / CA | Vault PKI secrets engine, two-tier hierarchy | Vault issues all lab certs; mirrors the real enterprise pattern; one less VM vs a separate CA |
| CA hierarchy | `Atlas Lab Root CA` → `Atlas Lab Intermediate CA` | Root CA mount is disabled after signing the intermediate; day-to-day issuance uses the intermediate only |
| IP address | `192.168.20.15` (static, set on the machine) | Outside the DHCP range (.100–.254); no reservation needed |
| Hostname | `vault.atlas.local` | |
| Gateway | `192.168.20.1` | |
| DNS | `192.168.0.101` (Pi-hole), `1.1.1.1` fallback | Change DNS to `192.168.20.3` after the M920q cutover |
| Subnet | `192.168.20.0/24` | |
| VLAN | 20 (Atlas Lab) — no VLAN config needed on the VM | Switch port handles it |
| Auth methods | Kubernetes auth, AppRole, username/password | See [Auth methods](#auth-methods) below |
| Unseal keys / root token | Stored in a local encrypted file; **never committed to this repo** | The repo is public |
| Backups | Raft snapshot-auto (built into Vault) + rsync off-VM | Vault schedules and rotates snapshots automatically; copying them off the VM to the Crucial SSD and OneDrive is a separate script (future state — waiting on the SSD enclosure) |
| Automation | Manual runbook (this doc) | Do it by hand first, understand each step; automate later via `ansible-collection-lab` |

## PKI hierarchy

```
Atlas Lab Root CA                 ← Vault PKI mount: pki
    (disabled after signing intermediate — key never used day-to-day)
        │
        └── Atlas Lab Intermediate CA    ← Vault PKI mount: pki_int
                (active; issues all lab certs)
                    │
                    ├── vault.atlas.local
                    ├── proxmox.atlas.local
                    ├── atlas-pihole.atlas.local
                    ├── llm.atlas.local
                    ├── cluster Ingresses (via cert-manager ACME)
                    └── everything else in the lab
```

Clients only need to trust `Atlas Lab Root CA`. The intermediate is included in every cert's chain automatically so browsers and tools see the full path.

Replacing `atlas-ca`: once cert-manager is pointed at Vault PKI via ACME, `atlas-ca` is retired.

## Who uses Vault

| Client | Auth method | What it reads |
|---|---|---|
| External Secrets Operator (Talos cluster) | Kubernetes auth | App secrets for workloads running in the cluster |
| AAP | AppRole | Playbook credentials (infra passwords, API keys) |
| atlas-ai Ansible | AppRole | GPU box credentials, service API keys |
| Austin (terminal) | Username / password | Admin access for managing secrets |
| Home Assistant | AppRole (future) | Smart home credentials |

## Auth methods

**Kubernetes auth** — pods prove identity using their Kubernetes service account token, already on every pod. External Secrets Operator uses this to pull only the secrets it is allowed to read. No passwords to manage.

**AppRole** — a Role ID (username) and Secret ID (password) for machine clients outside the cluster. AAP and atlas-ai Ansible each get their own role with a tight policy — AAP's AppRole can only read playbook credentials, nothing else.

**Username/password** — for you at the terminal:
```bash
vault login -method=userpass username=austin
```

## VM spec

| Parameter | Value |
|---|---|
| VM ID | 203 |
| Hostname | `vault` / `vault.atlas.local` |
| IP | `192.168.20.15` (static) |
| vCPU | 1 |
| RAM | 1 GB |
| Disk | 16 GB on `CRUCIAL_SSD_512GB` |
| OS | Alpine Linux (latest stable) |

> **Not yet provisioned.** The VM will be added to `terraform/proxmox-vms.tf` following the pattern in that file. Terraform changes are a separate commit once the runbook is validated by hand first.

---

## Runbook

Work through these steps in order. Each step has a verification command.

### Prerequisites
- Proxmox host up and reachable at `192.168.0.100`
- Talos cluster running (`kubectl get nodes` shows Ready)
- cert-manager deployed and `atlas-ca` ClusterIssuer exists
- You can reach `192.168.20.x` (laptop on the lab network or via break-glass port)
- Vault CLI installed on your Mac: `brew install vault`

---

### Step 1 — Provision the VM

VM 203 was created via the Proxmox CLI (not Terraform — Vault is stateful and holds secrets that can't be recreated from code; accidental destroy would be catastrophic):

```bash
qm create 203 \
  --name vault \
  --memory 1024 \
  --cores 1 \
  --net0 virtio,bridge=vmbr0,tag=20 \
  --scsihw virtio-scsi-single \
  --scsi0 CRUCIAL_SSD_512GB:16,format=raw,iothread=1,discard=on \
  --ide2 local:iso/alpine-virt-3.24.0-x86_64.iso,media=cdrom \
  --boot order=ide2 \
  --ostype l26 \
  --machine q35 \
  --bios ovmf \
  --efidisk0 CRUCIAL_SSD_512GB:1,format=raw,pre-enrolled-keys=0 \
  --startup order=2,up=30 \
  --tags vault
```

After install, update boot order to disk: `qm set 203 --boot order=scsi0` and eject ISO: `qm set 203 --ide2 none,media=cdrom`.

---

### Step 2 — Install Alpine Linux

Boot from the ISO and run:

```sh
setup-alpine
```

Key answers:
- **Hostname:** `vault`
- **Interface:** `eth0`, static, IP `192.168.20.15`, netmask `255.255.255.0`, gateway `192.168.20.1`
- **DNS:** `192.168.0.101`, search domain `atlas.local`
- **SSH server:** `openssh`, allow root SSH login: `yes`
- **Disk:** install to `sda`, `sys` mode

> **Note on VLAN:** The VLAN 20 tag is set on the Proxmox NIC (`tag=20`), so Alpine sees a plain untagged `eth0` — no VLAN config needed inside the VM.

After reboot:
```bash
ssh root@vault.atlas.local   # should connect
```

---

### Step 3 — Install Vault

```sh
# Install base packages
apk add curl wget jq tzdata unzip

# Download and install the Vault binary from HashiCorp
# Check https://releases.hashicorp.com/vault/ for the latest version before running
VAULT_VERSION=2.2.1
wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -O /tmp/vault.zip
unzip -q /tmp/vault.zip -d /root   # extract to /root — Alpine's /tmp tmpfs is too small for the binary
mv /root/vault /usr/local/bin/vault
chmod +x /usr/local/bin/vault
rm /tmp/vault.zip
vault version

# Create a dedicated system user (no login shell, no password, no home dir created)
adduser -S -D -H -h /opt/vault vault

# Create directory structure per HashiCorp's deployment guide
mkdir -p /opt/vault/data /opt/vault/tls /opt/vault/snapshots /etc/vault.d

# data/ and snapshots/ are owned fully by vault
chown -R vault:vault /opt/vault/data /opt/vault/snapshots

# tls/: certs are readable by all (0644), private key is root-owned but vault-readable (0640)
chown root:vault /opt/vault/tls
chmod 750 /opt/vault/tls
```

---

### Step 4 — Bootstrap TLS (temporary self-signed cert)

This cert is only used to get Vault running. It will be replaced in Step 9 with a cert issued by Vault's own PKI.

```sh
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /opt/vault/tls/vault.key \
  -out /opt/vault/tls/vault.crt \
  -days 365 \
  -subj "/CN=vault.atlas.local" \
  -addext "subjectAltName=DNS:vault.atlas.local,DNS:vault,IP:192.168.20.15"

# Cert readable by all; key owned by root but readable by vault group only
chown root:root /opt/vault/tls/vault.crt
chown root:vault /opt/vault/tls/vault.key
chmod 644 /opt/vault/tls/vault.crt
chmod 640 /opt/vault/tls/vault.key
```

---

### Step 5 — Configure and start Vault

Create `/etc/vault.d/vault.hcl`:

```hcl
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-01"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
}

api_addr      = "https://vault.atlas.local:8200"
cluster_addr  = "https://vault.atlas.local:8201"
disable_mlock = true   # required for Raft/integrated storage per HashiCorp docs
ui            = true
log_level     = "info"
```

Create `/etc/init.d/vault`:

```sh
#!/sbin/openrc-run
name="vault"
command="/usr/local/bin/vault"
command_args="server -config=/etc/vault.d/vault.hcl"
command_user="vault"
command_background=true
pidfile="/run/vault/vault.pid"

export VAULT_ADDR="https://vault.atlas.local:8200"
```

```sh
# /run/ is a tmpfs (RAM-based, wiped on reboot) and owned by root.
# The vault user can't write directly to /run/, so we need a subdirectory it owns.
# On Ubuntu/RHEL the official Vault package handles this via systemd tmpfiles.d automatically.
# On Alpine we do it manually with a local.d startup script that recreates the directory on every boot.
mkdir -p /run/vault
chown vault:vault /run/vault

# Create the boot script that recreates /run/vault/ after every reboot
cat > /etc/local.d/vault-run.start << EOF
#!/bin/sh
mkdir -p /run/vault
chown vault:vault /run/vault
EOF
chmod +x /etc/local.d/vault-run.start
rc-update add local default

chmod +x /etc/init.d/vault
rc-update add vault default
rc-service vault start
rc-service vault status
```

Add to `/etc/profile` (so the CLI works from the shell):

```sh
export VAULT_ADDR=https://vault.atlas.local:8200
export VAULT_SKIP_VERIFY=true   # only until the self-signed cert is replaced in Step 9
```

From your laptop:
```bash
export VAULT_ADDR=https://vault.atlas.local:8200
export VAULT_SKIP_VERIFY=true
vault status   # Initialized: false, Sealed: true
```

---

### Step 6 — Initialize and unseal

#### What is unsealing?

Vault uses **Shamir's Secret Sharing** to protect the master encryption key that unlocks all your secrets:

- When Vault initializes, it generates a master key and mathematically splits it into 5 pieces (unseal keys). No single piece can reconstruct the master key — you need at least 3 of the 5.
- The master key is **never stored on disk** — only the 5 encrypted shares are.
- When Vault starts or restarts, it loads encrypted data from disk but cannot decrypt it until enough unseal keys are provided. It is "sealed" — a locked safe with no one holding the combination.
- Each `vault operator unseal` provides one share. After 3 shares, Vault reconstructs the master key in memory, decrypts its storage, and begins serving requests.
- If someone stole the server or disk, they would get only encrypted data — useless without 3 of the 5 unseal keys.
- **The trade-off:** every reboot requires manually running `vault operator unseal` three times. This is intentional. Auto-unseal (via a cloud KMS) can be added later once you're comfortable with the manual workflow.

#### Initialization (done once, the first time only)

```bash
vault operator init
```

Output:
```
Unseal Key 1: ...
Unseal Key 2: ...
Unseal Key 3: ...
Unseal Key 4: ...
Unseal Key 5: ...

Initial Root Token: hvs.xxxxxxxxxxxxxxxxxxxxxxxx
```

**Save these immediately** to a file outside the repo with restricted permissions:

```bash
# Save to ~/.vault-init (never inside the git repo)
chmod 600 ~/.vault-init
```

#### Unseal (run after every reboot)

Provide any 3 of the 5 keys — run this command 3 times, pasting a different key each time:

```bash
vault operator unseal   # run 3 times with 3 different keys
vault status            # Sealed: false when done
```

> Every reboot requires running `vault operator unseal` three times before Vault accepts requests. The unseal keys are in `~/.vault-init`.

---

### Step 7 — First login and userpass auth

```bash
vault login   # paste the root token

# Enable userpass and create your login
vault auth enable userpass

# Write the admin policy
cat > admin.hcl <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
vault policy write admin admin.hcl

vault write auth/userpass/users/austin \
  password="<choose a strong password>" \
  policies="admin"

# From now on use your own credentials, not the root token
vault login -method=userpass username=austin
```

---

### Step 8 — Enable KV secrets engine

A secrets engine is a plugin inside Vault that knows how to store, generate, or vend a particular type of secret. Vault ships with many engines — KV for static secrets, PKI for certificates, AWS for dynamic IAM credentials, and so on. You enable an engine at a path, and everything under that path is handled by that engine.

The KV (key-value) secrets engine is the simplest and most commonly used — it's Vault's general-purpose store for static secrets: passwords, API keys, tokens, and any other values that don't need to be dynamically generated. KV v2 adds versioning, so every time you update a secret the previous value is retained and can be recovered if needed.

Mounting it at `secret/` is the conventional path. The folder structure underneath is up to you — organising by consumer keeps policies clean and makes it easy to grant a service access to only its own secrets.

```bash
vault secrets enable -path=secret kv-v2

# Test it works
vault kv put secret/test message="hello from vault"
vault kv get secret/test
vault kv metadata delete secret/test
```

Planned folder structure by consumer:
```
secret/aap/             # AAP playbook credentials
secret/atlas-ai/        # atlas-ai secrets
secret/talos-cluster/   # Talos Kubernetes app secrets (read by External Secrets Operator)
secret/home-assistant/  # Home Assistant credentials
```

---

### Step 8b — Configure automated snapshots

Vault's Raft storage is entirely in-memory backed by an on-disk log at `/opt/vault/data`. If the VM is lost or the data directory is corrupted, everything is gone — all secrets, PKI keys, auth config. Snapshots are the safety net.

A snapshot is a point-in-time copy of the entire Raft state. You can restore from one with `vault operator raft snapshot restore` to bring Vault back to exactly how it was at that moment.

> **Note:** Vault's built-in snapshot scheduler (`sys/storage/raft/snapshot-auto`) is an enterprise-only feature and is not available in Vault Community edition. We use a cron job instead.

The snapshot directory was created on the VM during setup:

```sh
mkdir -p /opt/vault/snapshots
chown vault:vault /opt/vault/snapshots
```

#### Cron-based snapshots on the Vault VM

A cron job runs as the vault user to take daily snapshots at 2:00 AM and prune old ones, keeping 7 days of history.

> Alpine Linux does not use `/etc/cron.d/` — per-user crontabs live in `/etc/crontabs/<user>`.

The file is at `/etc/crontabs/vault` (chmod 600):

```sh
# Vault Raft Snapshot Schedule
# Runs daily at 2:00 AM as the vault user
#
# Takes a point-in-time snapshot of Vault's entire Raft state (secrets, PKI,
# policies, auth config) and saves it to /opt/vault/snapshots/ with a
# datestamped filename (e.g. vault-20261029.snap).
#
# Retention: keeps the last 7 days of snapshots, deletes anything older.
#
# To restore from a snapshot:
#   vault operator raft snapshot restore /opt/vault/snapshots/vault-YYYYMMDD.snap
#
# Note: Vault's built-in snapshot scheduler (sys/storage/raft/snapshot-auto)
# is enterprise-only. This cron job is the community edition alternative.
#
# VAULT_SKIP_VERIFY is set inline because the TLS cert is self-signed until
# Step 10 replaces it with a Vault-issued cert.

0 2 * * * VAULT_ADDR=https://vault.atlas.local:8200 VAULT_SKIP_VERIFY=true vault operator raft snapshot save /opt/vault/snapshots/vault-$(date +%Y%m%d).snap && find /opt/vault/snapshots -name '*.snap' -mtime +7 -delete
```

#### Snapshot token setup

The cron job runs as the `vault` OS user, which has no Vault token by default. We give it a dedicated token with a minimal policy — least privilege means it can only take snapshots, nothing else in Vault.

**1. Create the snapshot policy:**

```bash
vault policy write snapshot - << 'EOF'
# Grants permission to take a Raft snapshot only.
# Attached to the snapshot-agent token used by the cron job on the Vault VM.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOF
```

**2. Create a long-lived token with only that policy and save it to the VM:**

```bash
# Create the token (1 year TTL, non-renewable so it doesn't silently expire)
vault token create -policy=snapshot -ttl=8760h -no-default-policy -display-name=snapshot-agent -format=json \
  | jq -r '.auth.client_token' \
  | ssh -i ~/.ssh/proxmox-claude root@192.168.20.15 \
    "cat > /etc/vault.d/snapshot-token && chmod 600 /etc/vault.d/snapshot-token && chown vault:vault /etc/vault.d/snapshot-token"
```

**3. Update the cron job to use the token:**

Edit `/etc/crontabs/vault` on the Vault VM to source the token file:

```sh
0 2 * * * VAULT_ADDR=https://vault.atlas.local:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=$(cat /etc/vault.d/snapshot-token) vault operator raft snapshot save /opt/vault/snapshots/vault-$(date +%Y%m%d).snap && find /opt/vault/snapshots -name '*.snap' -mtime +7 -delete
```

Verify snapshots are being created (check after 24 hours):

```bash
ls -lh /opt/vault/snapshots
```

Take a manual snapshot at any time from the Mac:

```bash
vault operator raft snapshot save ~/vault-snapshot-$(date +%Y%m%d).snap
```

**Copying snapshots off the VM** (future state — do this once the Crucial SSD enclosure arrives):

Add a cron job on the Proxmox host to pull snapshots from the Vault VM daily and sync to OneDrive weekly:

```sh
# /etc/cron.d/vault-snapshots on the Proxmox host
0 3 * * * root rsync -a root@192.168.20.15:/opt/vault/snapshots/ /mnt/crucial-ssd/backups/vault/
0 4 * * 0 root rclone sync /mnt/crucial-ssd/backups/vault/ onedrive:atlas-lab/vault-snapshots/
```

---

### Step 9 — Build the PKI hierarchy

This is where Vault becomes the lab's Certificate Authority. Every service in the lab will get a TLS certificate from Vault, signed by a trusted CA — so browser warnings go away and service-to-service communication can be properly verified.

The design follows the enterprise two-tier pattern:

- **Root CA** (`pki` mount) — the trust anchor. Its key never leaves Vault and the mount is disabled after signing the intermediate, so it can't be used day-to-day. Think of it as the offline root.
- **Intermediate CA** (`pki_int` mount) — signs all the actual service certificates. If it were ever compromised, you revoke it and issue a new one from the root without throwing away the whole chain.

Any client that trusts the Root CA will automatically trust certificates issued by the intermediate — which means trusting every service in the lab. You'll install the root CA cert into your Mac's keychain and into the cluster so everything verifies cleanly.

Two steps: root CA first, then intermediate CA.

#### 9a — Root CA (`pki` mount)

This step enables the PKI secrets engine, sets a 10-year max TTL (the root CA's own lifetime — 10 years is standard because the root is the trust anchor; if it expires, every cert it ever signed becomes untrusted), and generates the Root CA key and certificate entirely inside Vault. Using `internal` means the private key is generated in Vault's encrypted storage and never exported — it never touches disk. The public certificate is piped out to a temp file you'll need in Step 9e to install into your Mac's keychain and the cluster.

The last command configures the URLs Vault embeds in every certificate it issues: one pointing to where clients can download the CA cert (`issuing_certificates`) and one pointing to the Certificate Revocation List (`crl_distribution_points`). Any client that receives a cert from this CA knows exactly where to go to verify it.

```bash
# Enable the PKI secrets engine at pki/
vault secrets enable -path=pki pki

# Set a 10-year max TTL — the root CA will use the full lifetime
vault secrets tune -max-lease-ttl=87600h pki

# Generate the Root CA key and cert inside Vault (key never leaves Vault's storage)
# The public cert is saved to a temp file — needed in Step 9e for keychain install
vault write -format=json pki/root/generate/internal \
  common_name="Atlas Lab Root CA" \
  ttl=87600h \
  key_type=rsa \
  key_bits=4096 \
  | jq -r '.data.certificate' > /tmp/atlas-lab-root-ca.crt

# Configure the URLs Vault embeds in every issued certificate
vault write pki/config/urls \
  issuing_certificates="https://vault.atlas.local:8200/v1/pki/ca" \
  crl_distribution_points="https://vault.atlas.local:8200/v1/pki/crl"
```

#### 9b — Intermediate CA (`pki_int` mount)

The intermediate CA is what actually signs day-to-day certificates for lab services. The root CA (Step 9a) signs the intermediate exactly once, then gets disabled — so if the intermediate were ever compromised, you revoke it and issue a new one from the root without touching anything that already trusts the root.

The signing flow has three parts: generate a Certificate Signing Request (CSR) on the intermediate mount, bring that CSR to the root CA to get it signed, then import the signed certificate back into the intermediate mount. Both keys stay inside Vault the entire time — only the CSR and signed cert move between mounts as files. The temp files are removed at the end since they're no longer needed once the intermediate mount has its signed cert.

```bash
# Enable the intermediate PKI mount with a 5-year max TTL
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate the intermediate CSR (key stays inside Vault)
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="Atlas Lab Intermediate CA" \
  key_type=rsa \
  key_bits=4096 \
  | jq -r '.data.csr' > /tmp/pki_int.csr

# Sign the intermediate with the root CA
vault write -format=json pki/root/sign-intermediate \
  csr=@/tmp/pki_int.csr \
  common_name="Atlas Lab Intermediate CA" \
  ttl=43800h \
  | jq -r '.data.certificate' > /tmp/pki_int.crt

# Import the signed cert back into the intermediate mount
vault write pki_int/intermediate/set-signed certificate=@/tmp/pki_int.crt

# Configure URLs for the intermediate
vault write pki_int/config/urls \
  issuing_certificates="https://vault.atlas.local:8200/v1/pki_int/ca" \
  crl_distribution_points="https://vault.atlas.local:8200/v1/pki_int/crl"

# Clean up temp files
rm /tmp/pki_int.csr /tmp/pki_int.crt
```

#### 9c — Disable the root CA mount

The root CA key is now only needed to sign a new intermediate (rare). Disable the mount so it can't issue anything day-to-day:

```bash
vault secrets disable pki   # re-enable only when signing a new intermediate
```

> This is the homelab equivalent of locking the root CA offline. The key never leaves Vault's storage, but the mount is inactive.

#### 9d — Create an issuing role on the intermediate

An issuing role is a named policy that controls what the intermediate CA is allowed to sign. Vault won't issue any certificate without one — the role is the gatekeeper. It defines which domains are permitted, how long certificates can live, and what key types are allowed.

For the lab, one role covers everything: `atlas-local`, scoped to `*.atlas.local`. This is the role cert-manager will reference in Step 10 when it requests TLS certificates for cluster services. Any request that doesn't match the role's rules gets rejected by Vault before a cert is ever issued.

```bash
vault write pki_int/roles/atlas-lab \
  allowed_domains="atlas.local" \
  allow_subdomains=true \
  allow_bare_domains=false \
  max_ttl=8760h \   # 1 year max; shorter is better for automated clients
  key_type=rsa \
  key_bits=2048
```

#### 9e — Issue Vault's own cert and replace the bootstrap cert

Right now Vault is serving a self-signed TLS certificate — the one it generated at install time with no CA behind it. That's why `VAULT_SKIP_VERIFY=true` has been set everywhere: nothing trusts it. This step fixes that by using the intermediate CA we just built to issue a proper cert for Vault itself.

The command asks the intermediate to issue a cert for `vault.atlas.local`, saves both the cert and the intermediate CA chain into the file Vault serves for TLS, then restarts Vault so it picks up the new cert. After the restart, any client that trusts the root CA (which you'll install in Step 10) will verify Vault's cert cleanly — no more skip-verify workaround.

The cert file gets both the server cert and the intermediate CA cert concatenated together. That's called a full chain — it lets clients that only have the root CA cert walk the full path to Vault's cert without needing to fetch the intermediate separately.

```bash
# Issue the cert and save the raw JSON response (run on your Mac)
vault write -format=json pki_int/issue/atlas-lab \
  common_name="vault.atlas.local" \
  ip_sans="192.168.20.15" \
  ttl=8760h > /tmp/vault-cert.json

# Extract the cert chain and private key (Alpine has no python3 — use jq)
jq -r '.data.certificate' /tmp/vault-cert.json > /tmp/vault.crt
jq -r '.data.ca_chain[0]' /tmp/vault-cert.json >> /tmp/vault.crt
jq -r '.data.private_key' /tmp/vault-cert.json > /tmp/vault.key

# Copy to the Vault VM
scp -i ~/.ssh/proxmox-claude /tmp/vault.crt /tmp/vault.key root@192.168.20.15:/opt/vault/tls/

# Set permissions and restart (run on Vault VM or via SSH)
chown root:root /opt/vault/tls/vault.crt
chown root:vault /opt/vault/tls/vault.key
chmod 644 /opt/vault/tls/vault.crt
chmod 640 /opt/vault/tls/vault.key
rc-service vault restart
```

Remove `VAULT_SKIP_VERIFY` from `/etc/profile` and from your laptop's shell. From now on Vault's cert is signed by the intermediate and clients that trust the root CA will verify it cleanly.

---

### Step 10 — Trust the root CA on your Mac

The root CA cert was saved to `/tmp/atlas-lab-root-ca.crt` during Step 9a. Installing it into the macOS System keychain tells every app on your Mac — browsers, curl, the Vault CLI — to trust any certificate signed by this CA. Once done, `VAULT_SKIP_VERIFY` is no longer needed anywhere and Vault's UI will show a green padlock.

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/atlas-lab-root-ca.crt
```

After this, every browser on your Mac trusts any cert signed by the intermediate. Services get certs individually as you work through them — see the next section.

---

### Step 11 — Issue certs for lab services

Now that Vault is the lab CA, any running service can get a proper TLS cert from it. The pattern is the same for every service: issue the cert from the intermediate, install it on the service, restart. No more browser warnings.

#### Proxmox

```bash
# Issue the cert (run on your Mac)
vault write -format=json pki_int/issue/atlas-lab \
  common_name="proxmox.atlas.local" \
  ip_sans="192.168.0.100" \
  ttl=8760h > /tmp/proxmox-cert.json

jq -r '.data.certificate + "\n" + .data.ca_chain[0]' /tmp/proxmox-cert.json > /tmp/proxmox.crt
jq -r '.data.private_key' /tmp/proxmox-cert.json > /tmp/proxmox.key

# Copy to Proxmox host
scp -i ~/.ssh/proxmox-claude /tmp/proxmox.crt /tmp/proxmox.key root@192.168.0.100:/etc/pve/local/

# On Proxmox: rename to match what the UI expects and restart the proxy
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 '
  mv /etc/pve/local/proxmox.crt /etc/pve/local/pveproxy-ssl.pem
  mv /etc/pve/local/proxmox.key /etc/pve/local/pveproxy-ssl.key
  systemctl restart pveproxy
'
```

#### Pi-hole

```bash
# Issue the cert (run on your Mac)
vault write -format=json pki_int/issue/atlas-lab \
  common_name="pihole.atlas.local" \
  ip_sans="192.168.0.101" \
  ttl=8760h > /tmp/pihole-cert.json

jq -r '.data.certificate + "\n" + .data.ca_chain[0]' /tmp/pihole-cert.json > /tmp/pihole.crt
jq -r '.data.private_key' /tmp/pihole-cert.json > /tmp/pihole.key

# Copy to the Pi-hole LXC via Proxmox
pct push 102 /tmp/pihole.crt /etc/pihole/tls.crt
pct push 102 /tmp/pihole.key /etc/pihole/tls.key
```

> Pi-hole TLS configuration depends on the web server it's using (lighttpd by default). Update the lighttpd config to point at these files and restart.

---

### Step 12 — AppRole auth (AAP and atlas-ai)

> **Prereq: AAP and atlas-ai must be stood up before running this step.**

AppRole is how automated services authenticate to Vault without a username/password. Each service gets a role-id (like a username) and a secret-id (like a password), which it uses to obtain a short-lived token. The token is scoped to a policy that limits exactly what secrets it can read.

```bash
vault auth enable approle

# Create policies
cat > aap-policy.hcl <<EOF
path "secret/data/aap/*" { capabilities = ["read"] }
path "secret/metadata/aap/*" { capabilities = ["list"] }
EOF
vault policy write aap-policy aap-policy.hcl

cat > atlas-ai-policy.hcl <<EOF
path "secret/data/atlas-ai/*" { capabilities = ["read"] }
path "secret/metadata/atlas-ai/*" { capabilities = ["list"] }
EOF
vault policy write atlas-ai-policy atlas-ai-policy.hcl

# Create roles
vault write auth/approle/role/aap \
  token_policies="aap-policy" \
  token_ttl=1h token_max_ttl=24h

vault write auth/approle/role/atlas-ai \
  token_policies="atlas-ai-policy" \
  token_ttl=1h token_max_ttl=24h

# Get credentials for each (store in ~/.vault-init or equivalent)
vault read auth/approle/role/aap/role-id
vault write -f auth/approle/role/aap/secret-id
vault read auth/approle/role/atlas-ai/role-id
vault write -f auth/approle/role/atlas-ai/secret-id
```

---

### Step 13 — Kubernetes auth and External Secrets Operator

> **Prereq: External Secrets Operator must be deployed to the cluster. Add `platform/external-secrets/` to the repo first.**

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443" \
  kubernetes_ca_cert=@<(kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}') \
  disable_iss_validation=true
```

External Secrets Operator then uses a `SecretStore` pointing at `https://vault.atlas.local:8200`, authenticated via Kubernetes auth.

---

### Step 14 — Point cert-manager at Vault PKI (retire atlas-ca)

> **Prereq: Steps 12–13 complete. Update `platform/cert-manager/cluster-issuer.yaml` to add the Vault ClusterIssuer.**

cert-manager supports Vault as an issuer natively — no ACME needed, it uses the Vault API directly. After this, new certificates requested inside the cluster come from `Atlas Lab Intermediate CA` instead of `atlas-ca`. The old `atlas-ca` ClusterIssuer and its self-signed chain can be removed.

---

## Cert renewal

Certs issued manually (Proxmox, Pi-hole) expire after one year. Renew by re-running the `pki_int/issue/atlas-lab` command for that service and restarting it.

For services using cert-manager (cluster Ingresses), renewal is automatic once the Vault issuer is configured in Step 14.

## Open items

- [ ] Issue cert for Pi-hole web UI (Step 11)
- [ ] Stand up AAP, then run Step 12
- [ ] Add `platform/external-secrets/` to the cluster, then run Step 13
- [ ] Update `platform/cert-manager/cluster-issuer.yaml` to use Vault PKI issuer (Step 14)
- [ ] Decide on auto-unseal once comfortable with the manual workflow
- [ ] Raft snapshot off-VM copy (rsync to Crucial SSD + rclone to OneDrive) once the SSD enclosure arrives — commands are in Step 8b
- [ ] Home Assistant AppRole when HA joins the lab VLAN

## Future capabilities to explore

These are Vault features not currently configured in the lab but worth pursuing as the platform matures:

| Capability | What it does | Why it's interesting |
|---|---|---|
| **Vault Agent** | Daemon that runs on each host, auto-renews certs and secrets, triggers service reloads | Removes manual cert renewal for Proxmox, Pi-hole, and other infrastructure hosts |
| **Dynamic secrets** | Vault generates short-lived credentials on demand (database passwords, AWS keys) and revokes them automatically | Nothing long-lived sitting in config files — secrets exist only while needed |
| **Transit engine** | Encryption-as-a-service — apps encrypt/decrypt data without ever handling keys | Useful for atlas-ai or any service that needs to store sensitive data |
| **SSH secrets engine** | Issues signed SSH certificates instead of managing authorized_keys files | Centralized SSH access control across all lab hosts |
| **Auto-unseal** | Vault unseals itself on restart using a key stored in an external provider (cloud KMS, another Vault instance) | Removes the need to manually unseal after every reboot |
| **Vault Agent Injector** | Kubernetes mutating webhook that injects secrets directly into pod filesystems via Vault Agent sidecars | Alternative to External Secrets Operator for getting secrets into cluster workloads |
| **TOTP secrets engine** | Vault generates TOTP codes (like Google Authenticator) — useful for storing and generating 2FA codes centrally | Interesting for lab service accounts that require MFA |
