# atlas-talos

**[→ Atlas Lab Overview](https://austin2153.github.io/atlas-talos/)** — live visualization of the lab: network, hosts, address plan, Kubernetes platform.

Terraform code to deploy a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on a Proxmox VE server.

See [docs/talos-cluster-architecture.md](docs/talos-cluster-architecture.md) for design decisions, network layout, and rationale.

## Cluster Overview

| Role | Hostname | IP |
|---|---|---|
| Control Plane | `talos-cp.atlas.local` | `192.168.20.10` |
| Worker | `talos-worker-01.atlas.local` | `192.168.20.11` |
| Worker *(planned)* | `talos-worker-02.atlas.local` | `192.168.20.13` |

## Prerequisites

### Tools

Install the following on your local machine:

```bash
brew install terraform talosctl kubectl
```

### Authenticate to Terraform Cloud

```bash
terraform login
```

## Repository Structure

```
atlas-talos/
├── README.md
├── .gitignore
├── .yamllint                    # yamllint config for CI manifest validation
├── .github/
│   └── workflows/
│       ├── terraform.yml        # Terraform fmt + validate on push
│       └── manifests.yml        # YAML lint + kubeconform on platform/ changes
├── docs/
│   └── architecture.md          # Design decisions and architecture overview
├── platform/
│   ├── appset.yaml              # Root ApplicationSet — auto-discovers subfolders
│   ├── cert-manager/
│   │   ├── cert-manager.yaml    # cert-manager v1.20.2 upstream manifest
│   │   └── cluster-issuer.yaml  # Self-signed CA chain (selfsigned → root CA → atlas-ca)
│   ├── flux/
│   │   ├── flux.yaml            # Flux v2.8.5 upstream manifest
│   │   ├── gitrepository.yaml   # Flux GitRepository watching atlas-talos main
│   │   └── flux-kustomization.yaml  # Flux Kustomization applying state/ to cluster
│   ├── kratix/
│   │   ├── kratix.yaml          # Kratix v0.125.0 upstream manifest
│   │   ├── git-state-store.yaml # GitStateStore pointing at state/ in this repo
│   │   ├── destination.yaml     # Registers local cluster as Kratix destination
│   │   └── promises/
│   │       └── proxmox-vm/      # Promise: provision Proxmox VMs on demand
│   ├── local-path-provisioner/
│   │   └── local-path-storage.yaml  # StorageClass + provisioner (Talos-patched)
│   ├── metallb/
│   │   ├── metallb-native.yaml  # MetalLB v0.15.3 upstream manifest
│   │   └── l2-config.yaml       # L2 advertisement pool (192.168.20.50-99)
│   └── vcsim/
│       ├── namespace.yaml       # Namespace for vcsim instances
│       └── vcsim-instances.yaml # VMware vCenter simulator deployments
├── state/                       # Kratix writes workload manifests here; Flux applies them
│   └── .gitkeep
└── terraform/
    ├── providers.tf              # TF Cloud backend + provider version pins
    ├── variables.tf              # All input variables
    ├── terraform.tfvars          # Your actual values (gitignored — never commit this)
    ├── locals.tf                 # Computed locals
    ├── proxmox-image.tf          # Download Talos ISO to Proxmox storage
    ├── proxmox-vms.tf            # Control plane + worker VM resources
    ├── talos.tf                  # Talos config generation, apply, and bootstrap
    └── outputs.tf                # talosconfig + kubeconfig outputs
```

## Configuration

Copy and fill in your values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### Key Variables

| Variable | Description | Example |
|---|---|---|
| `proxmox_endpoint` | Proxmox API URL | `https://192.168.0.100:8006` |
| `proxmox_api_token` | Proxmox API token | `terraform@pve!mytoken=...` |
| `proxmox_node` | Proxmox node name | `proxmox` |
| `cluster_name` | Talos cluster name | `atlas` |
| `control_plane_ip` | Control plane static IP | `192.168.20.10` |
| `worker_ips` | List of worker static IPs | `["192.168.20.11"]` |
| `gateway` | VLAN 20 gateway | `192.168.20.1` |
| `dns_server` | DNS server IP (Pi-hole) | `192.168.0.101` |
| `dns_fallback_server` | Fallback DNS if Pi-hole is down | `1.1.1.1` |

## Deployment

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

After a successful apply, save credentials and merge into your default kubeconfig:

```bash
terraform output -raw kubeconfig > ~/.kube/atlas-talos.kubeconfig
terraform output -raw talosconfig > ~/.talos/atlas-talos.talosconfig
# Remove stale entries (required on rebuild — new cluster has new certificates)
kubectl config delete-context admin@atlas 2>/dev/null; kubectl config delete-cluster atlas 2>/dev/null; kubectl config delete-user admin@atlas 2>/dev/null; true
# Merge and switch
KUBECONFIG=~/.kube/config:~/.kube/atlas-talos.kubeconfig kubectl config view --flatten > ~/.kube/config-merged && mv ~/.kube/config-merged ~/.kube/config
kubectl config use-context admin@atlas
kubectl get nodes
```

> **Rebuilding the cluster?** The VMs use pinned MAC addresses (`BC:24:11:00:02:00` for the control plane, `BC:24:11:00:02:01` for worker-01, etc.), so your DHCP reservations in UniFi remain valid across destroys. After `terraform apply`, re-run all the commands above — the delete step clears stale certificates from the previous cluster.

## Platform Layer (GitOps)

After the cluster is running, the platform layer is managed via [ArgoCD](https://argo-cd.readthedocs.io/) and GitOps. Everything under `platform/` is auto-discovered and deployed.

### ArgoCD Setup

Install ArgoCD:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

Create an SSH deploy key and add the public key to GitHub as a read-only deploy key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/argocd-atlas-talos -N "" -C "argocd-atlas-talos"
```

Create the repo secret in the cluster:

```bash
kubectl create secret generic atlas-talos-repo -n argocd \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd-atlas-talos \
  --from-literal=url=git@github.com:austin2153/atlas-talos.git \
  --from-literal=type=git
kubectl label secret atlas-talos-repo -n argocd argocd.argoproj.io/secret-type=repository
```

Apply the root ApplicationSet:

```bash
kubectl apply -f platform/appset.yaml
```

From this point, any new folder added under `platform/` will be auto-discovered and deployed by ArgoCD within ~3 minutes.

### Platform Components

| Component | Version | Purpose |
|---|---|---|
| local-path-provisioner | v0.0.30 | Default StorageClass using node-local disk |
| MetalLB | v0.15.3 | L2 load balancer (pool: 192.168.20.50–99) |
| cert-manager | v1.20.2 | TLS certificate management with self-signed CA chain |
| Flux | v2.8.5 | GitOps operator — watches `state/` and applies Kratix-written manifests |
| Kratix | v0.125.0 | Platform engineering framework; writes desired state to `state/` via GitStateStore |
| vcsim | latest | VMware vCenter simulator instances for testing (vcenter-01, vcenter-02) |

### Kratix Promises

Promises are defined under `platform/kratix/promises/`. Each promise is a Kratix CRD that, when a resource is requested, triggers a workflow to fulfill it.

| Promise | Description |
|---|---|
| `proxmox-vm` | Provisions a Proxmox VM on demand via a Python-based workflow |

### Kratix Setup Notes

Kratix requires write access to this repo to push manifests into `state/`. A GitHub fine-grained PAT (`kratix-state-writer`) with **Contents: Read and write** scope is stored as a Kubernetes secret in `kratix-platform-system`. This secret is created imperatively and is not committed to Git.

```bash
kubectl create secret generic kratix-state-writer \
  --namespace kratix-platform-system \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-pat>
```

### Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Get the admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

Then open https://localhost:8080 (admin / password from above).

## Teardown

```bash
cd terraform
terraform destroy
```
