# Atlas Lab

**[→ Lab Overview](https://austin2153.github.io/atlas-talos/)** — live visualization of the lab: network, hosts, address plan, and Kubernetes platform. Built in vanilla HTML/SVG and automatically validated against the live lab by a Python script.

A self-hosted homelab built on a single Proxmox VE node, running a Talos Linux Kubernetes cluster, HashiCorp Vault, and a full GitOps platform stack. Built as a hands-on environment for learning and demonstrating enterprise infrastructure patterns at home-lab scale.

---

## What This Demonstrates

- **Infrastructure as Code** — Proxmox VMs provisioned end-to-end with Terraform, state managed in Terraform Cloud
- **Immutable infrastructure** — Talos Linux: no SSH, no package manager, API-only cluster management
- **GitOps** — ArgoCD ApplicationSet auto-discovers and deploys platform components from Git
- **Platform engineering** — Kratix promise-based framework provisions on-demand infrastructure (Proxmox VMs) from Kubernetes resource requests
- **Secrets management** — HashiCorp Vault with Raft storage, KV v2 secrets engine, automated snapshots, and a two-tier PKI CA hierarchy (in progress)
- **Network segmentation** — VLAN-separated lab, home, and IoT traffic on UniFi hardware

---

## Stack

| Layer | Technology |
|---|---|
| Hypervisor | Proxmox VE 9.2 (Lenovo ThinkCentre M920q) |
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

## Status

| Area | Status |
|---|---|
| Talos Kubernetes cluster | Running — 1 control plane, 1 worker |
| ArgoCD + GitOps platform | Running |
| HashiCorp Vault | Running — KV v2, snapshots, and two-tier PKI CA hierarchy |
| Vault PKI (CA hierarchy) | Running — root CA, intermediate CA, issuing role, Mac keychain trust |
| Second worker node | Planned — pending hardware (M920q + RAM) |
| Ansible Automation Platform | Planned |

---

## Docs

- [Lab Overview](https://austin2153.github.io/atlas-talos/) — live network and host visualization
- [Talos Cluster Architecture](docs/talos-cluster-architecture.md) — design decisions and platform details
- [HashiCorp Vault Runbook](docs/runbooks/vault-install.md) — install, PKI, secrets, auth methods
- [Proxmox Runbook](docs/runbooks/proxmox-install.md) — host setup and rebuild guide
