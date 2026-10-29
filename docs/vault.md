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

```bash
vault secrets enable -path=secret kv-v2

# Test
vault kv put secret/test message="hello from vault"
vault kv get secret/test
vault kv metadata delete secret/test
```

Organise secrets by consumer:
```
secret/aap/          # AAP playbook credentials
secret/atlas-ai/     # atlas-ai secrets
secret/cluster/      # Kubernetes app secrets (read by External Secrets Operator)
secret/home-assistant/
```

---

### Step 8b — Configure automated snapshots

Vault's built-in snapshot scheduler creates and rotates backups automatically. Run this once after Vault is initialized:

```bash
# Daily snapshots, keep 7
vault write sys/storage/raft/snapshot-auto/config/daily \
  interval="24h" \
  retain=7 \
  path_prefix="/opt/vault/snapshots"

# Weekly snapshots, keep 4
vault write sys/storage/raft/snapshot-auto/config/weekly \
  interval="168h" \
  retain=4 \
  path_prefix="/opt/vault/snapshots"
```

Create the snapshot directory on the VM:

```sh
mkdir -p /opt/vault/snapshots
chown vault:vault /opt/vault/snapshots
```

Verify snapshots are being created (check after 24 hours):

```bash
vault list sys/storage/raft/snapshot-auto/config   # shows daily, weekly
ls -lh /opt/vault/snapshots
```

**Copying snapshots off the VM** (future state — do this once the Crucial SSD enclosure arrives):

Add a cron job on the Proxmox host to pull snapshots from the Vault VM daily and sync to OneDrive weekly:

```sh
# /etc/cron.d/vault-snapshots on the Proxmox host
0 3 * * * root rsync -a root@192.168.20.15:/opt/vault/snapshots/ /mnt/crucial-ssd/backups/vault/
0 4 * * 0 root rclone sync /mnt/crucial-ssd/backups/vault/ onedrive:atlas-lab/vault-snapshots/
```

> Until the SSD enclosure arrives, take manual snapshots to your Mac occasionally as a stopgap:
> ```bash
> vault operator raft snapshot save ~/vault-snapshot-$(date +%Y%m%d).snap
> ```

---

### Step 9 — Build the PKI hierarchy

This is where Vault becomes the lab's CA. Two steps: root CA, then intermediate CA.

#### 9a — Root CA (`pki` mount)

```bash
# Enable the root PKI mount with a 10-year max TTL
vault secrets enable -path=pki pki
vault secrets tune -max-lease-ttl=87600h pki

# Generate the root CA key and cert (stays inside Vault — never exported)
vault write -format=json pki/root/generate/internal \
  common_name="Atlas Lab Root CA" \
  ttl=87600h \
  key_type=rsa \
  key_bits=4096 \
  | jq -r '.data.certificate' > /tmp/atlas-lab-root-ca.crt

# Configure CRL and issuing URLs
vault write pki/config/urls \
  issuing_certificates="https://vault.atlas.local:8200/v1/pki/ca" \
  crl_distribution_points="https://vault.atlas.local:8200/v1/pki/crl"
```

#### 9b — Intermediate CA (`pki_int` mount)

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

```bash
vault write -format=json pki_int/issue/atlas-lab \
  common_name="vault.atlas.local" \
  alt_names="vault" \
  ip_sans="192.168.20.15" \
  ttl=8760h \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
open('/opt/vault/tls/vault.crt','w').write(d['certificate']+'\n'+d['ca_chain'][0])
open('/opt/vault/tls/vault.key','w').write(d['private_key'])
"
chown root:root /opt/vault/tls/vault.crt
chown root:vault /opt/vault/tls/vault.key
chmod 644 /opt/vault/tls/vault.crt
chmod 640 /opt/vault/tls/vault.key
rc-service vault restart
```

Remove `VAULT_SKIP_VERIFY` from `/etc/profile` and from your laptop's shell. From now on Vault's cert is signed by the intermediate and clients that trust the root CA will verify it cleanly.

---

### Step 10 — Trust the root CA on your Mac

Download the root cert and add it to the macOS System keychain:

```bash
curl -sk https://vault.atlas.local:8200/v1/pki/ca/pem -o ~/Downloads/atlas-lab-root-ca.crt
# pki mount is disabled — fetch from the file saved in Step 9a instead:
# scp root@vault.atlas.local:/tmp/... no — use the copy saved during Step 9a
```

> Save `atlas-lab-root-ca.crt` during Step 9a — you'll need it for this step. Keep it (it's a public cert, not a key).

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain atlas-lab-root-ca.crt
```

After this, every browser on your Mac trusts any cert signed by the intermediate. Proxmox, Pi-hole, and Vault's UI will load without warnings once they each have a cert (done individually as you get to each service).

---

### Step 11 — AppRole auth for AAP and atlas-ai

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

# Get credentials for each (store encrypted, same as unseal keys)
vault read auth/approle/role/aap/role-id
vault write -f auth/approle/role/aap/secret-id
vault read auth/approle/role/atlas-ai/role-id
vault write -f auth/approle/role/atlas-ai/secret-id
```

---

### Step 12 — Kubernetes auth and External Secrets Operator

> **TODO:** Add `platform/external-secrets/` to the repo. Do this as a separate task once Vault is running.

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443" \
  kubernetes_ca_cert=@<(kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}') \
  disable_iss_validation=true
```

External Secrets Operator then uses a `SecretStore` pointing at `https://vault.atlas.local:8200`, authenticated via Kubernetes auth.

---

### Step 13 — Point cert-manager at Vault PKI (retire atlas-ca)

cert-manager supports Vault as an issuer natively (no ACME needed — it uses the Vault API directly).

> **TODO:** Update `platform/cert-manager/cluster-issuer.yaml` to add a `Vault` ClusterIssuer pointing at `pki_int/sign/atlas-lab`. This is a separate commit — do it once Vault is running and the PKI hierarchy is verified.

After this, new certificates requested inside the cluster come from `Atlas Lab Intermediate CA` instead of `atlas-ca`. The old `atlas-ca` ClusterIssuer and its self-signed chain can be removed.

---

## Cert renewal

Certs issued with `ttl=8760h` expire after one year. Renew by re-running the `pki_int/issue/atlas-lab` command for that service and restarting it. Add calendar reminders.

For services using cert-manager (cluster Ingresses), renewal is automatic once the Vault issuer is configured.

## Open items

- [ ] Add `platform/external-secrets/` to the cluster (Step 12)
- [ ] Update `platform/cert-manager/cluster-issuer.yaml` to use Vault PKI issuer (Step 13)
- [ ] Issue certs for Proxmox and Pi-hole web UIs from Vault PKI and install them
- [ ] Decide on auto-unseal once comfortable with the manual workflow
- [ ] Raft snapshot off-VM copy (rsync to Crucial SSD + rclone to OneDrive) once the SSD enclosure arrives — commands are in Step 8b
- [ ] Home Assistant AppRole when HA joins the lab VLAN
