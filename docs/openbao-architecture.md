# OpenBao Architecture

Design of the lab's certificate authority and, later, its secrets store: where OpenBao runs, how the PKI hierarchy is laid out, and how clients get certificates and authenticate.

## References

- [OpenBao docs](https://openbao.org/docs/)
- [PKI secrets engine](https://openbao.org/docs/secrets/pki/)
- [ACME in the PKI engine](https://openbao.org/docs/secrets/pki/acme/)
- [AppRole auth](https://openbao.org/docs/auth/approle/)
- [Kubernetes auth](https://openbao.org/docs/auth/kubernetes/)

## Overview

OpenBao is the open-source (OpenSSF) fork of HashiCorp Vault, with the same model, API and CLI concepts. It is the lab's certificate authority: hosts request certificates over ACME and renew them on their own, so browser warnings go away without hand-issued certs. It will also hold the lab's credentials and API keys, so none of them live in plaintext in a config file, an Ansible variable or this repo.

It replaced a HashiCorp Vault VM (`vault.atlas.local`, `192.168.20.15`), retired in November 2026.

**Running:** OpenBao 2.7.2 on Debian 13, `bao-01.atlas.home.arpa` (`192.168.20.18`, VLAN 20), an unprivileged Proxmox LXC (CT 111) with 1 core, 1 GB RAM and 4 GB disk. UI and API on port 8200.

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Product | OpenBao | Open-source license; same concepts and API as Vault |
| Deployment | Single LXC on Proxmox, outside the Talos cluster | The CA and secrets store must not depend on the cluster they serve |
| Provisioning | Proxmox community script, not Terraform | Stateful; holds keys that can't be recreated from code |
| Storage | Integrated PebbleDB (`/opt/openbao/data`) | No external dependency; fine for one node |
| Unsealing | Auto-unseal at service start (single key on the LXC) | Acceptable for a home lab; survives reboots without manual steps |
| TLS | Certificate from its own intermediate CA, renewed by certbot over ACME | OpenBao serves a trusted cert like every other host |
| CA | Two-tier hierarchy | Mirrors the enterprise pattern; the root only signs the intermediate |
| Certificate issuance | ACME | Clients renew automatically; no hand-issued certs to track |
| Domain | `atlas.home.arpa` | RFC 8375 home-network domain; replaces `atlas.local` |

## PKI hierarchy

```text
Atlas Lab Root CA 2026                ← PKI mount: pki, 10 years
    │   (signs only the intermediate)
    └── Atlas Lab Intermediate CA     ← PKI mount: pki_int, 5 years
            │   (issues every lab certificate)
            └── <host>.atlas.home.arpa   90 days, role atlas-home-arpa, renewed over ACME
```

- **Role `atlas-home-arpa`:** subdomains of `atlas.home.arpa` only (no wildcards, bare domain or localhost), IP SANs allowed, 90 days, RSA 2048.
- **ACME directory:** `https://bao-01.atlas.home.arpa:8200/v1/pki_int/acme/directory`. No account pre-registration; a client proves control of the name over HTTP-01 (port 80) or DNS-01.
- **Root certificate:** `https://bao-01.atlas.home.arpa:8200/v1/pki/ca/pem` (public, no login). Clients only need to trust the root; the intermediate ships in every chain.

## Clients

| Client | How it gets certificates | Status |
|---|---|---|
| bao-01 | certbot over ACME, deploy hook reloads OpenBao | Running |
| pve-01 (Proxmox) | Built-in ACME (Datacenter → ACME) | Running |
| Other LXCs and VMs | certbot or acme.sh over ACME | Planned |
| Talos cluster | cert-manager ClusterIssuer pointing at the ACME directory | Planned, with the cluster rebuild |

## Auth methods

| Client | Auth method | Access | Status |
|---|---|---|---|
| Admin | Username / password | Full (admin policy) | Running |
| Automation (Claude Code) | AppRole, 1-hour tokens | Full for now; to be narrowed | Running |
| External Secrets Operator (Talos cluster) | Kubernetes auth | App secrets for cluster workloads | Planned |
| Ansible Automation Platform | AppRole | Playbook credentials | Planned |

- **AppRole:** a role ID and secret ID for machine clients, traded for a short-lived token on each login. Revoked by deleting the secret ID or the role.
- **Kubernetes auth:** pods prove who they are with their service account token, so there are no passwords to manage.

## Future capabilities

- **KV v2:** move lab credentials out of config files and into OpenBao.
- **Backups:** scheduled snapshots copied off the LXC.
- **Dynamic secrets:** short-lived credentials generated on demand and revoked automatically.
- **SSH secrets engine:** signed SSH certificates instead of `authorized_keys` files.
