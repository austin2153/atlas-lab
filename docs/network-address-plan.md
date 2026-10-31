# Network Address Plan

IP address reference for the atlas lab — subnets, DHCP ranges, static assignments, and reserved pools across all VLANs. Update this file whenever a static IP is added or a reservation changes.

---

## VLANs

| VLAN | Name | Subnet | Gateway | Purpose |
|---|---|---|---|---|
| 1 | Management | `192.168.0.0/24` | `192.168.0.1` | Network gear only — gateway, switch, APs. No Wi-Fi. |
| 10 | IoT | `192.168.10.0/24` | `192.168.10.1` | Smart speakers, Hue lighting, 2.4 GHz only |
| 20 | Atlas Lab | `192.168.20.0/24` | `192.168.20.1` | Proxmox host, VMs, Kubernetes cluster, MetalLB |
| 30 | Home | `192.168.30.0/24` | `192.168.30.1` | Phones, laptops, TVs, consoles, printer |

---

## VLAN 1 — Management (`192.168.0.0/24`)

DHCP managed by the UniFi gateway. Static assignments for infrastructure gear only.

### Static assignments

| IP | Hostname | Device | Notes |
|---|---|---|---|
| `192.168.0.1` | — | UniFi Home Cloud Gateway Ultra | Gateway / router / firewall |
| `192.168.0.2` | — | UniFi 8-port PoE switch | |
| `192.168.0.100` | `proxmox` / `proxmox.atlas.local` | Proxmox VE 9 host | Management interface |
| `192.168.0.101` | `atlas-pihole` / `atlas-pihole.atlas.local` | Pi-hole (LXC 102) | DNS — currently on management VLAN, moves to VLAN 20 in planned network redesign |

### DHCP range

| Range | Purpose |
|---|---|
| `192.168.0.150–254` | DHCP — management clients (rare, break-glass access) |

---

## VLAN 10 — IoT (`192.168.10.0/24`)

DHCP managed by the UniFi gateway.

### Address ranges

| Range | Purpose |
|---|---|
| `192.168.10.2–.49` | Static — IoT infrastructure (Home Assistant, future) |
| `192.168.10.100–254` | DHCP — IoT devices (smart speakers, Hue, etc.) |

### Static assignments

| IP | Hostname | Role |
|---|---|---|
| `192.168.10.10` | `home-assistant.atlas.local` | Home Assistant OS VM |

---

## VLAN 20 — Atlas Lab (`192.168.20.0/24`)

DNS: Pi-hole at `192.168.0.101` (current) → `192.168.20.3` (after planned network redesign)

All `*.atlas.local` DNS records are managed in Pi-hole.

### Address ranges

| Range | Purpose | Capacity | Next available |
|---|---|---|---|
| `192.168.20.1` | Gateway (UniFi) | — | — |
| `192.168.20.2–.49` | VMs and LXC containers (static) | 48 | `.16` |
| `192.168.20.50–.99` | Kubernetes service IPs (MetalLB) | 50 | `.51` |
| `192.168.20.100–.254` | DHCP — lab Wi-Fi clients | dynamic | — |

### Static assignments — VMs and containers

| IP | Hostname | VM/LXC ID | Role | Notes |
|---|---|---|---|---|
| `192.168.20.3` | `atlas-pihole.atlas.local` | LXC 102 | Pi-hole DNS | Reserved for planned network redesign; currently on `192.168.0.101` |
| `192.168.20.10` | `talos-cp.atlas.local` | VM 200 | Talos control plane | Static in Talos machine config |
| `192.168.20.11` | `talos-worker-01.atlas.local` | VM 201 | Talos worker | Static in Talos machine config |
| `192.168.20.13` | `talos-worker-02.atlas.local` | VM 202 | Talos worker — planned | Reserved; pending M920q hardware |
| `192.168.20.15` | `vault.atlas.local` | VM 203 | HashiCorp Vault | Alpine Linux, Raft storage |

### MetalLB service IPs (Kubernetes)

MetalLB pool: `192.168.20.50–192.168.20.99`. IPs are pinned in each service manifest — never assign a VM or container in this range.

| IP | Service | Namespace | Notes |
|---|---|---|---|
| `192.168.20.50` | ArgoCD | `argocd` | Pinned via `spec.loadBalancerIP` |
| `192.168.20.52` | vcsim vcenter-01 | `vcsim` | VMware vCenter simulator |
| `192.168.20.53` | vcsim vcenter-02 | `vcsim` | VMware vCenter simulator |

---

## VLAN 30 — Home (`192.168.30.0/24`)

DHCP managed by the UniFi gateway. No static assignments currently.

### DHCP range

| Range | Purpose |
|---|---|
| `192.168.30.100–254` | DHCP — phones, laptops, TVs, consoles, printer |

---

## DNS

All `*.atlas.local` records are local DNS entries managed in Pi-hole. The full list is in Pi-hole's custom DNS config (`/etc/pihole/custom.list` or via the Pi-hole admin UI).

| Hostname | IP | Notes |
|---|---|---|
| `proxmox.atlas.local` | `192.168.0.100` | Proxmox web UI |
| `atlas-pihole.atlas.local` | `192.168.0.101` | Pi-hole admin UI |
| `talos-cp.atlas.local` | `192.168.20.10` | Talos API endpoint |
| `talos-worker-01.atlas.local` | `192.168.20.11` | |
| `talos-worker-02.atlas.local` | `192.168.20.13` | Planned |
| `vault.atlas.local` | `192.168.20.15` | Vault UI and API |
| `home-assistant.atlas.local` | `192.168.10.10` | Home Assistant |

---

## Planned network redesign

Pending arrival of the M920q, the plan is to move the entire Proxmox host (and Pi-hole) onto VLAN 20 untagged:

- Proxmox host moves from `192.168.0.100` → `192.168.20.5`
- Pi-hole moves from `192.168.0.101` → `192.168.20.3`
- VLAN 1 becomes management-only (gateway, switch, APs only)
- Home devices move to VLAN 30
- Talos VMs drop their VLAN tag (`vlan_id` unset in Terraform)

Until then the current split setup remains in place.
