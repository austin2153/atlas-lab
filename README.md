# Atlas Lab

**[→ Lab Overview](https://austin2153.github.io/atlas-talos/)** — live visualization of the lab: network, hosts, address plan, Kubernetes platform.

A self-hosted homelab built on Proxmox VE, running a Talos Linux Kubernetes cluster, HashiCorp Vault, GitOps tooling, and supporting infrastructure. This repo contains the Terraform code, Kubernetes platform manifests, runbooks, and documentation for the full lab.

---

## Lab Infrastructure

| Component | Details |
|---|---|
| **Hypervisor** | Proxmox VE 9.2 — single node, VLAN-segmented network |
| **Kubernetes** | Talos Linux v1.12 — 1 control plane, 1 worker (2nd planned) |
| **Secrets & PKI** | HashiCorp Vault 2.2.1 — Raft storage, KV v2, PKI CA (in progress) |
| **DNS** | Pi-hole on VLAN 20 — all `*.atlas.local` names |
| **Networking** | UniFi Home Cloud Gateway Ultra — VLAN 20 (lab), VLAN 10 (IoT), VLAN 30 (home, planned) |
| **GitOps** | ArgoCD — auto-discovers and deploys everything under `platform/` |
| **Platform** | Kratix + Flux — internal platform engineering framework |
| **Load Balancer** | MetalLB — L2 mode, pool `192.168.20.50–99` |
| **TLS** | cert-manager — transitioning from self-signed CA to Vault PKI |

---

## Repository Structure

```
atlas-talos/
├── docs/
│   ├── index.html                     # Live lab overview (GitHub Pages)
│   ├── talos-cluster-architecture.md  # Talos cluster design decisions
│   ├── atlas-rack-design.md           # Physical rack and network redesign plan
│   ├── credential-map.md              # All credential files and where they live
│   └── runbooks/
│       ├── vault-install.md           # HashiCorp Vault install and configuration
│       ├── proxmox-install.md         # Proxmox host setup and rebuild guide
│       └── unifi-access.md            # UniFi controller API access
├── platform/                          # Kubernetes platform manifests (GitOps via ArgoCD)
│   ├── appset.yaml                    # Root ApplicationSet — auto-discovers subfolders
│   ├── cert-manager/                  # TLS certificate management
│   ├── flux/                          # GitOps operator watching state/
│   ├── kratix/                        # Platform engineering framework + Proxmox VM promise
│   ├── local-path-provisioner/        # Default StorageClass for node-local PVs
│   ├── metallb/                       # L2 load balancer
│   └── vcsim/                         # VMware vCenter simulator instances (vcenter-01, vcenter-02)
├── scripts/
│   └── check-lab-overview.py          # Validates index.html against the live lab
├── state/                             # Kratix writes workload manifests here; Flux applies them
└── terraform/
    ├── providers.tf                   # Terraform Cloud backend + provider version pins
    ├── variables.tf                   # All input variables
    ├── terraform.tfvars               # Your actual values (gitignored — never commit this)
    ├── locals.tf                      # Computed locals (worker node map, naming)
    ├── proxmox-image.tf               # Downloads Talos ISO to Proxmox storage
    ├── proxmox-vms.tf                 # Control plane + worker VM definitions
    ├── talos.tf                       # Talos config generation, apply, and bootstrap
    └── outputs.tf                     # talosconfig + kubeconfig outputs
```

---

## Talos Cluster

The Kubernetes cluster runs on Talos Linux — an immutable, API-driven OS with no SSH or shell. All configuration is applied via the Talos API and managed by Terraform.

See [docs/talos-cluster-architecture.md](docs/talos-cluster-architecture.md) for full design decisions, network layout, and platform component details.

### Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init
terraform plan
terraform apply
```

After apply, save and merge credentials:

```bash
terraform output -raw kubeconfig > ~/.kube/atlas-talos.kubeconfig
terraform output -raw talosconfig > ~/.talos/atlas-talos.talosconfig
kubectl config delete-context admin@atlas 2>/dev/null; kubectl config delete-cluster atlas 2>/dev/null; kubectl config delete-user admin@atlas 2>/dev/null; true
KUBECONFIG=~/.kube/config:~/.kube/atlas-talos.kubeconfig kubectl config view --flatten > ~/.kube/config-merged && mv ~/.kube/config-merged ~/.kube/config
kubectl config use-context admin@atlas
kubectl get nodes
```

> **Rebuilding?** VMs use pinned MAC addresses so DHCP reservations stay valid across destroys. Re-run the credential commands above after every apply to clear stale certificates.

### Platform Components

| Component | Version | Purpose |
|---|---|---|
| local-path-provisioner | v0.0.30 | Default StorageClass using node-local disk |
| MetalLB | v0.15.3 | L2 load balancer (pool: 192.168.20.50–99) |
| cert-manager | v1.20.2 | TLS certificate management |
| Flux | v2.8.5 | GitOps operator — watches `state/` and applies Kratix-written manifests |
| Kratix | v0.125.0 | Platform engineering framework; provisions infrastructure on demand |
| vcsim | latest | VMware vCenter simulator instances for testing |

---

## HashiCorp Vault

Vault runs on its own Alpine Linux VM (`vault.atlas.local`, `192.168.20.15`) outside the Kubernetes cluster — deliberately, so it doesn't depend on the cluster to function. It serves as the lab-wide secrets store and Certificate Authority.

See [docs/runbooks/vault-install.md](docs/runbooks/vault-install.md) for the full install and configuration runbook.

**Current state:**
- Vault 2.2.1 running, initialized and unsealed
- KV v2 secrets engine enabled at `secret/`
- Automated daily snapshots configured
- PKI hierarchy (Root CA + Intermediate CA) in progress

---

## Teardown

```bash
cd terraform
terraform destroy
```
