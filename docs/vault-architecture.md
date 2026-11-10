# HashiCorp Vault Architecture

Design of the lab's secrets store and certificate authority: why Vault runs where it does, how the PKI hierarchy is laid out, and how clients authenticate.

## References

- [Vault docs](https://developer.hashicorp.com/vault/docs)
- [Integrated (Raft) storage](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [PKI secrets engine](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [AppRole auth](https://developer.hashicorp.com/vault/docs/auth/approle)
- [Kubernetes auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)

## Overview

Vault holds the lab's credentials, API keys and certificates, so none of them live in plaintext in a config file, an Ansible variable or this repo. It is also the lab's certificate authority: services get certificates from Vault, browser warnings go away, and the setup mirrors how Vault PKI is used in enterprise environments.

**Running:** Vault Community 2.2.1 on Alpine Linux, `vault.atlas.local` (`192.168.20.15`, VLAN 20), a single Proxmox VM with 1 vCPU, 1 GB RAM and 16 GB disk.

## Community vs. Enterprise

Everything here runs on the free Community edition. The architecture (PKI hierarchy, KV v2, AppRole, Kubernetes auth, Raft storage) is the same as Enterprise. Enterprise adds features for operating at scale across teams and datacenters: namespaces, DR and performance replication, Sentinel policies, control groups, HSM-based unseal and FIPS 140-2. The one Enterprise feature the lab would have used is scheduled Raft snapshots (`snapshot-auto`); a cron job does the same job instead.

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Edition | Community | No Enterprise features needed |
| Deployment | Single VM on Proxmox, outside the Talos cluster | Vault holds the cluster's own secrets, so it must not depend on the cluster |
| Provisioning | By hand (`qm create`), not Terraform | Vault is stateful and holds secrets that can't be recreated from code; an accidental `terraform destroy` would be unrecoverable |
| OS | Alpine Linux | Minimal footprint and attack surface |
| Storage | Integrated Raft | No external dependency; single-node Raft is fine for one node |
| HA | Single node for now | All VMs share one host anyway; grows to three nodes with more hardware |
| Unsealing | Manual (3 of 5 Shamir keys) | Auto-unseal (Azure Key Vault) is planned once the basics are settled |
| TLS | Self-signed bootstrap cert, replaced by a Vault-issued cert | Gets Vault running so PKI can be configured, then Vault serves its own cert |
| CA | Vault PKI, two-tier hierarchy | Mirrors the enterprise pattern and avoids a separate CA server |
| Backups | Daily Raft snapshot by cron, 7 days kept | `snapshot-auto` is Enterprise-only; an off-VM copy is planned |
| Unseal keys and root token | Kept outside the repo | The repo is public |

## PKI hierarchy

```text
Atlas Lab Root CA                     ← PKI mount: pki
    (mount disabled after signing the intermediate; never used day to day)
        │
        └── Atlas Lab Intermediate CA ← PKI mount: pki_int
                (active; issues all lab certificates)
                    │
                    ├── vault.atlas.local
                    ├── proxmox.atlas.local
                    └── other lab services
```

Clients only need to trust `Atlas Lab Root CA`; the intermediate is included in every certificate's chain. Certificates issued by hand last one year and are renewed by re-issuing from the `pki_int` role.

**Planned:** cert-manager in the cluster gets a Vault ClusterIssuer (in `platform/cert-manager/`), so cluster certificates come from the intermediate CA and the current self-signed `atlas-ca` issuer is retired.

## Clients and auth methods

| Client | Auth method | Reads | Status |
|---|---|---|---|
| Admin at the terminal | Username / password | Everything (admin policy) | Running |
| Snapshot cron job | Token with a snapshot-only policy | Raft snapshots | Running |
| External Secrets Operator (Talos cluster) | Kubernetes auth | App secrets for cluster workloads | Planned |
| Ansible Automation Platform | AppRole | Playbook credentials | Planned |
| Home Assistant | AppRole | Smart home credentials | Planned |

- **Kubernetes auth:** pods prove who they are with their service account token, so there are no passwords to manage. External Secrets Operator reads only the paths its policy allows.
- **AppRole:** a role ID and secret ID for machine clients outside the cluster, each role with a tight policy.
- **Username / password:** for interactive admin use.

## Future capabilities

- **Vault Agent:** auto-renews certificates on infrastructure hosts and reloads services.
- **Dynamic secrets:** short-lived credentials generated on demand and revoked automatically.
- **Transit engine:** encryption as a service, without apps handling keys.
- **SSH secrets engine:** signed SSH certificates instead of `authorized_keys` files.
- **Auto-unseal with Azure Key Vault:** no manual unseal after a reboot.
