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
| Provisioning | Proxmox community script | Handles VM creation, image download, and disk import in one command; VLAN tag set manually after |
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

## Step 1 — Run the community script

The [Proxmox VE Helper Scripts](https://community-scripts.org/scripts?q=home+ass&preview=haos-vm) project maintains a HAOS VM installer that handles image download, VM creation, and disk import automatically.

In the Proxmox shell (via the web UI or SSH), run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh)"
```

When prompted, choose **Default** settings. The script will:
- Download the latest HAOS qcow2 image
- Create the VM with 2 CPU, 4 GB RAM, 32 GB disk, OVMF (UEFI)
- Import and attach the disk
- Start the VM

> Note the VM ID assigned by the script — you'll need it in the next step.

## Step 2 — Configure network for VLAN 10

In the Proxmox VM network settings, set the NIC's VLAN tag to `10`. This places the VM directly on the IoT network — Home Assistant will get a DHCP address from the VLAN 10 range and have full layer-2 access to IoT devices.

## Step 3 — First boot and onboarding

Start the VM and navigate to `http://homeassistant.local:8123` (mDNS) or the DHCP-assigned IP. Complete the onboarding wizard:

1. Create admin account
2. Set home location (used for sun-based automations and weather)
3. Home Assistant will auto-discover devices on VLAN 10

## Step 4 — Set static IP and add DNS entry

After onboarding, set the static IP inside Home Assistant:

**Settings → System → Network → IPv4** — set to static, IP `192.168.10.10`, gateway `192.168.10.1`, DNS `192.168.0.101`.

Then add the Pi-hole DNS record:

```bash
ssh proxmox "pct exec 102 -- pihole-FTL --config dns.hosts '192.168.10.10 home-assistant.atlas.local'"
```

## Step 5 — Configure integrations

> TODO: Document specific integrations as they are set up

Planned integrations:

| Integration | Type | Notes |
|---|---|---|
| Philips Hue | IP (bridge) | Hue bridge on VLAN 10 or reachable from it |
| UniFi | IP | UniFi controller at `192.168.0.1` — may need VLAN 10 → VLAN 1 firewall rule |

## Step 6 — Add to Homepage dashboard (future)

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
