# Home Assistant

Home Assistant is an open-source home automation platform that integrates with thousands of smart home devices — lights, switches, sensors, locks, climate, media players, and more. It runs locally, keeping all automation logic and device data on-premises.

**Target:** `home-assistant.atlas.local` running as a VM on Proxmox, on VLAN 10 (IoT network).

## Reference

| Resource | Link |
|---|---|
| Home Assistant docs | https://www.home-assistant.io/docs/ |
| Home Assistant OS installation | https://www.home-assistant.io/installation/linux |
| HAOS VM image (KVM/QEMU) | https://github.com/home-assistant/operating-system/releases |
| Integrations catalog | https://www.home-assistant.io/integrations/ |
| Community forum | https://community.home-assistant.io/ |

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Deployment | Home Assistant OS VM on Proxmox | Full OS flavor gives Supervisor, Add-ons, automatic updates, and backups — the recommended install method |
| Flavor | Home Assistant OS (HAOS) | Container flavor lacks Supervisor and Add-ons; HAOS is the best-supported path |
| Network | VLAN 10 (IoT) | Direct layer-2 access to IoT devices; avoids mDNS/discovery issues that occur when crossing VLANs |
| Provisioning | Manual Proxmox VM + HAOS image | Outside the Kubernetes GitOps flow; same pattern as the Vault VM |
| DNS | `home-assistant.atlas.local` → `192.168.10.10` via Pi-hole | Same pattern as all other `*.atlas.local` names |
| IP | `192.168.10.10` (static, reserved in network address plan) | Low end of VLAN 10 static range `.2–.49` |

---

## Why not Kubernetes?

Home Assistant was initially considered for the Kubernetes cluster but a VM is the better fit:

- **IoT devices are on VLAN 10** — the cluster runs on VLAN 20. mDNS and local device discovery do not cross VLANs without a proxy, making cluster deployment fragile.
- **USB passthrough** — Zigbee/Z-Wave dongles are straightforward to pass to a VM; passing USB to a Kubernetes pod requires host-level configuration.
- **Home Assistant OS** — the full HAOS flavor (recommended) is not suitable for containers. The Container flavor lacks the Supervisor and Add-ons ecosystem.
- **Operational simplicity** — HAOS handles its own updates, backups, and add-on management. No manifests to maintain.

---

## Step 1 — Download the HAOS KVM image

On the Proxmox host, download the latest HAOS `.qcow2` image for KVM/QEMU:

```bash
# Check https://github.com/home-assistant/operating-system/releases for latest version
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100
wget -O /var/lib/vz/images/haos.qcow2 \
  https://github.com/home-assistant/operating-system/releases/download/<version>/haos_ova-<version>.qcow2.xz
# Extract
unxz /var/lib/vz/images/haos.qcow2.xz
```

## Step 2 — Create the VM in Proxmox

Recommended specs:

| Setting | Value |
|---|---|
| Name | `home-assistant` |
| OS | Linux 6.x kernel |
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | Import from HAOS qcow2 image (32 GB grows as needed) |
| Network | VirtIO NIC, tagged to VLAN 10 |
| BIOS | OVMF (UEFI) |

Import the disk:

```bash
qm importdisk <vmid> /var/lib/vz/images/haos.qcow2 local-lvm
```

Set the imported disk as the boot disk in the VM hardware settings.

## Step 3 — Configure network for VLAN 10

In the Proxmox VM network settings, set the NIC's VLAN tag to `10`. This places the VM directly on the IoT network — Home Assistant will get a DHCP address from the VLAN 10 range and have full layer-2 access to IoT devices.

## Step 4 — First boot and onboarding

Start the VM and navigate to `http://homeassistant.local:8123` (mDNS) or the DHCP-assigned IP. Complete the onboarding wizard:

1. Create admin account
2. Set home location (used for sun-based automations and weather)
3. Home Assistant will auto-discover devices on VLAN 10

## Step 5 — Pin the IP and add DNS entry

Once the VM has a DHCP address, reserve it in Pi-hole and add a DNS record:

```bash
# Add DNS record
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 \
  "pct exec 102 -- pihole-FTL --config dns.hosts '<IP> home-assistant.atlas.local'"
```

## Step 6 — Configure integrations

> TODO: Document specific integrations as they are set up

Planned integrations:

| Integration | Type | Notes |
|---|---|---|
| Philips Hue | IP (bridge) | Hue bridge on VLAN 10 or reachable from it |
| UniFi | IP | UniFi controller at `192.168.0.1` — may need VLAN 10 → VLAN 1 firewall rule |

## Step 7 — Add to Homepage dashboard (future)

Once Homepage is re-enabled, add a Home Assistant tile. Homepage has a native Home Assistant widget that shows entity counts and optionally specific entity states.

## Open items

| Item | Status |
|---|---|
| Download HAOS image and create VM | TODO |
| Configure VLAN 10 NIC | TODO |
| Onboarding | TODO |
| Pin IP + DNS entry | TODO |
| Philips Hue integration | TODO |
| UniFi integration | TODO |
| Homepage widget | TODO |
