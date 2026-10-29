# Atlas Lab

**[→ Lab Overview](https://austin2153.github.io/atlas-talos/)** — live visualization of the lab: network, hosts, address plan, Kubernetes platform.

A self-hosted homelab built on a single Proxmox VE node, running a Talos Linux Kubernetes cluster, HashiCorp Vault, and a full GitOps platform stack. Built as a hands-on environment for learning and demonstrating enterprise infrastructure patterns at home-lab scale.

---

## Stack

| Layer | Technology |
|---|---|
| Hypervisor | Proxmox VE 9.2 |
| Kubernetes OS | Talos Linux v1.12 — immutable, API-driven, no SSH |
| Infrastructure as Code | Terraform — provisions VMs, cluster config, and bootstrap |
| GitOps | ArgoCD — auto-discovers and deploys everything under `platform/` |
| Platform Engineering | Kratix + Flux — promise-based internal platform framework |
| Secrets & PKI | HashiCorp Vault 2.2.1 — KV v2, Raft storage, CA hierarchy |
| Load Balancer | MetalLB — L2 mode, dedicated IP pool |
| TLS | cert-manager — transitioning to Vault PKI |
| DNS | Pi-hole — all `*.atlas.local` names |
| Networking | UniFi Home Cloud Gateway Ultra — VLAN-segmented |

---

## Docs

- [Lab Overview](https://austin2153.github.io/atlas-talos/) — live network and host visualization
- [Talos Cluster Architecture](docs/talos-cluster-architecture.md) — design decisions and platform details
- [HashiCorp Vault Runbook](docs/runbooks/vault-install.md) — install, PKI, secrets, auth methods
- [Proxmox Runbook](docs/runbooks/proxmox-install.md) — host setup and rebuild guide
