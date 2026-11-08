# pve-01 (Proxmox on the M920q)

The new Proxmox host: a Lenovo M920q Tiny that lives directly on the lab VLAN (VLAN 20). It runs in parallel with the old host (`proxmox`, `192.168.0.100`, see [proxmox-install.md](proxmox-install.md)) while guests move over one at a time. This is the host part of the network redesign in [lab-infrastructure.md](../lab-infrastructure.md) and [network-address-plan.md](../network-address-plan.md).

**Status:** being built (started 2026-11-07). Proxmox not installed yet.

## Overview

| Item | Value |
|---|---|
| Hostname | `pve-01` (`pve-01.atlas.local`) |
| IP | `192.168.20.5/24` (reserved in the address plan), gateway `192.168.20.1` |
| DNS | `1.1.1.1` for now; later Technitium `192.168.20.3` first, `1.1.1.1` as fallback |
| Network | VLAN 20 untagged on the switch port; nothing on the host is tagged |
| Switch / patch panel | USW-Lite-8-PoE port 3 (named `pve-01`: native VLAN 20, tagged Block All, PoE off) ← patch panel 5 |
| Rack | Slot 4, directly below the gateway |
| Hardware | Intel i5-8500T (6 cores, 35 W), 32 GB RAM (to verify), 1 GbE Intel I219 |
| Storage | 1 TB NVMe, ZFS: Proxmox OS and all guests on one disk |
| Proxmox | Latest Proxmox VE 9.x ISO |

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Install | Fresh install, not a transplant of the old host's drive | Clean start on new hardware; guests move individually |
| Storage | One 1 TB NVMe, ZFS (single disk) | Our choice: OS and guests together; ZFS gives snapshots and compression. No redundancy with one disk, so backups matter |
| Cluster | **Standalone**, not clustered with the old host | A two-node cluster loses quorum when either node is down. Guests move by backup and restore |
| Network | Host and guests on VLAN 20 untagged; `vmbr0` VLAN-aware | Matches the redesign. Home Assistant (VLAN 10) will need VLAN 10 tagged on port 3 when it moves, not before |
| Old host | Keeps running until it's empty, then retired | Low-risk migration |

## Credentials

- **Root password:** Bitwarden (item to be created at install).
- **SSH:** the Mac key and Claude's key (`~/.ssh/proxmox-claude`), same as the old host.
- **API token:** new token after install, stored like the old host's (see [lab-credentials.md](../lab-credentials.md)).

## BIOS

To do. Check before installing:
- Virtualisation: Intel VT-x and VT-d enabled
- Power: on after AC power loss
- Boot: USB boot allowed; boot order
- Confirm RAM (32 GB) and which disks are installed (only the 1 TB NVMe should be selected in the installer)

## Install

To do.

**Installer USB (Mac):** as in [proxmox-install.md → Create the installer USB](proxmox-install.md#create-the-installer-usb-mac).

| Installer setting | Value |
|---|---|
| Target disk | 1 TB NVMe only |
| Filesystem | ZFS (RAID0, single disk) |
| Country / timezone | United States / `America/New_York` |
| Hostname | `pve-01.atlas.local` |
| Management interface | onboard Intel I219 |
| IP / gateway | `192.168.20.5/24` / `192.168.20.1` |
| DNS | `1.1.1.1` (Cloudflare). Not Pi-hole: it's being replaced, so the new host shouldn't depend on it |

## Post-install

To do. Same steps as the old host where they apply ([proxmox-install.md → Post-install steps](proxmox-install.md#post-install-steps)): SSH keys, no-subscription repositories, `dist-upgrade` and `intel-microcode`, then:
- `vmbr0` VLAN-aware
- DNS stays `1.1.1.1` only until Technitium is running; then set Technitium (`192.168.20.3`) first and `1.1.1.1` second (pve-01 → System → DNS). Debian only uses the second if the first doesn't answer. Until then, `*.atlas.local` names don't resolve on the host itself; it only needs internet names (apt, NTP)
- API token
- Pi-hole record `pve-01.atlas.local` → `192.168.20.5`; address plan; `~/.ssh/config` host

## Migration

Guests on the old host (2026-11-07). About 30 GB of guest data in total.

| ID | Name | Type | Today | On pve-01 | Status |
|---|---|---|---|---|---|
| 104 | `cloudflared` | LXC | VLAN 20 tagged, `.20.17` | untagged, same IP | Not started |
| 103 | `obsidian-mcp` | LXC | VLAN 20 tagged, `.20.16` | untagged, same IP | Not started |
| 203 | `vault` | VM | VLAN 20 tagged, `.20.15` | untagged, same IP | Not started |
| 200 | `talos-cp` | VM | VLAN 20 tagged, `.20.10` | untagged; Terraform `vlan_id` unset | Not started |
| 201 | `talos-worker-01` | VM | VLAN 20 tagged, `.20.11` | untagged; Terraform `vlan_id` unset | Not started |
| 102 | `atlas-pihole` | LXC | VLAN 1, `.0.101` | Not migrated: replaced by Technitium at `.20.3` | Not started |
| 204 | `home-assistant` | VM | VLAN 10 tagged, `.10.10` | VLAN 10 tagged (needs port 3 change) | Not started |

Order and method to be decided. Things to carry over per guest: Proxmox firewall rules (103, 104), `onboot` and startup order, and Vault's "tell Austin before restarting" rule.

Open: orphaned `vm-100-disk-0/1` (about 8 GB) on the old host's `CRUCIAL_SSD_512GB` with no VM 100 config; confirm before deleting or migrating.

## References

- [Proxmox VE installation](https://pve.proxmox.com/pve-docs/chapter-pve-installation.html)
- [Package repositories](https://pve.proxmox.com/wiki/Package_Repositories)
- [ZFS on Linux](https://pve.proxmox.com/wiki/ZFS_on_Linux)
- [Backup and restore](https://pve.proxmox.com/pve-docs/chapter-vzdump.html)
