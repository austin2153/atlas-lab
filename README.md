```
 ▗▄▖▗▄▄▄▖▗▖    ▗▄▖  ▗▄▄▖    ▗▖    ▗▄▖ ▗▄▄▖    ▗▄▄▄▄▄▄▄▄▄▖  ▄▄▄▄▖     ▄▄▖
▐▌ ▐▌ █  ▐▌   ▐▌ ▐▌▐▌       ▐▌   ▐▌ ▐▌▐▌ ▐▌   ▐▓▓▓▓▓▓▓▓▓▌▐██████▄▄▄▖   ▀▀▀▘   ▄▖
▐▛▀▜▌ █  ▐▌   ▐▛▀▜▌ ▝▀▚▖    ▐▌   ▐▛▀▜▌▐▛▀▚▖   ▐░░░░░░░░░▌▐█████▀▀▀▀▀▀▘  ▄▄▄▄▖  ▀▘
▐▌ ▐▌ █  ▐▙▄▄▖▐▌ ▐▌▗▄▄▞▘    ▐▙▄▄▖▐▌ ▐▌▐▙▄▞▘   ▐▄▄▄▄▄▄▄▄▄▌  ▀▀▀▀▘     ▀▀▘
```

**[→ Lab Overview](https://austin2153.github.io/atlas-lab/)** — live visualization of the lab: network, hosts, address plan, and Kubernetes platform. Built in vanilla HTML/SVG and automatically validated against the live lab by a Python script.

A self-hosted homelab built on a single Proxmox VE node, running a Talos Linux Kubernetes cluster, an OpenBao certificate authority, and a full GitOps platform stack. Built as a hands-on environment for learning and demonstrating enterprise infrastructure patterns at home-lab scale.

---

## What This Demonstrates

- **Infrastructure as Code** — Proxmox VMs provisioned end-to-end with Terraform, state managed in Terraform Cloud
- **Immutable infrastructure** — Talos Linux: no SSH, no package manager, API-only cluster management
- **GitOps** — ArgoCD ApplicationSet auto-discovers and deploys platform components from Git
- **Platform engineering** — Kratix promise-based framework provisions on-demand infrastructure (Proxmox VMs) from Kubernetes resource requests
- **PKI and secrets** — OpenBao with a two-tier CA hierarchy and ACME, so hosts renew their own certificates
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
| Secrets & PKI | OpenBao 2.7.2 — two-tier CA hierarchy, ACME |
| Load Balancer | MetalLB — L2 mode, dedicated IP pool |
| TLS | cert-manager — moving to OpenBao ACME |
| DNS | Pi-hole — all `*.atlas.local` names |
| Networking | UniFi Home Cloud Gateway Ultra — VLAN-segmented |

---

## Status

| Area | Status |
|---|---|
| Talos Kubernetes cluster | Running — 1 control plane, 1 worker |
| ArgoCD + GitOps platform | Running |
| OpenBao PKI | Running — root and intermediate CA, ACME issuing for Proxmox and LXCs |
| Second worker node | Planned — pending hardware (M920q + RAM) |
| Ansible Automation Platform | Planned |

---

## Docs

- [Lab Overview](https://austin2153.github.io/atlas-lab/) — live network and host visualization
- [Talos Architecture](docs/talos-architecture.md) — design decisions and platform details
- [ArgoCD](docs/argocd.md) — GitOps setup: install, repo credential, ApplicationSet
- [OpenBao Architecture](docs/openbao-architecture.md) — design, PKI hierarchy, ACME, auth methods
- [Obsidian MCP](https://austin2153.github.io/atlas-lab/obsidian-mcp.html) — self-hosted MCP server: Cloudflare tunnel and Syncthing design
- [Homepage](docs/homepage.md) — service dashboard: manifests, widget secrets, troubleshooting
