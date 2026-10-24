# Atlas Lab: Mini Rack Design and Setup

Handoff brief for the lab repo (Talos, Proxmox, AAP automation). Status as of 2026-10-24.
Items marked **PROPOSED** are recommendations, not final decisions. Items marked **OPEN** still need a decision.

---

## 1. Goal

Consolidate the basement network and lab gear (currently loose on a desk next to the Frontier fiber drop) into a 10-inch mini rack. Low power draw is a hard requirement. Nothing enterprise-grade or power hungry.

## 2. Enclosure

| Item | Detail |
|---|---|
| Rack | DeskPi RackMate T1, 8U, 10-inch, silver (standard T1, not Plus). Sold as GeeekPi on Amazon |
| Patch panel | GeeekPi 12-port Cat6, 10-inch, 0.5U, white, pass-through (keystone couplers, no punch-down) |
| Front jumpers | 24-pack white 0.5 ft patch cables (patch panel front to switch) |
| Rear cabling | Existing longer cables already on hand |
| Panel screws | 20x chrome knurled #10-32 x 5/8" thumb screws |
| Power | Reuse existing power strip, mounted on the side of the rack so it takes no U (no rack PDU, decided against on cost). Power bricks hidden behind |
| Side mounts | Power strip and Philips Hue bridge on the same side panel, near the rear edge so their cables stay short. Hue attached with Velcro/Dual Lock (or its wall-mount keyhole); keep it on acrylic, not metal, and away from the Basement AP (Zigbee shares 2.4 GHz) |
| Included with T1 | 1U vented rack shelf (kept as a spare), 2x 1U blank panels, 1x 1U venting blank panel, 2x acrylic side plates, acrylic top cover (fan-ready), handles, feet, #10-32 rack screws |
| Still to buy | 10-inch mounts for UCG Ultra, USW-Lite-8-PoE, and M920q |

## 3. Rack elevation (top to bottom)

| Slot | Height | Device | Notes |
|---|---|---|---|
| 1 | 0.5U | 12-port patch panel | Pass-through. Front jumpers to switch |
| 2 | 1U | UniFi USW-Lite-8-PoE | 192.168.0.2, 1 GbE |
| 3 | 1U | UniFi UCG Ultra | Gateway/router, 192.168.0.1, 2.5 GbE WAN |
| 4 | 1U | Blank (included 1U blank panel) | Not needed for a shelf: the ONT sits on top of the rack and the Hue bridge is side-mounted |
| 5 | 1U | Lenovo M920q Tiny #1 | Proxmox node. **VM backup drive:** old 500 GB Crucial SSD in a USB 3 enclosure, sitting behind the Tiny (import source during migration, then the backup target) |
| 6 | 1U | M920q Tiny #2 | Future. Included 1U blank panel until then |
| 7 | 1U | M920q Tiny #3 | Future. Included 1U blank panel until then |
| 8 | 1.5U | Spare | Included 1U venting blank + 0.5U open. Power strip is side-mounted, not in a slot |

**Space note:** 8U total, 5.5U used, 2.5U spare (slot 4 and slot 8). The ONT sits on top, and the Hue bridge and power strip are side-mounted, so none of them take a U.

**ONT placement: on top of the rack.** The ONT (Optical Network Terminal, Frontier FRX523) is the box where the fiber comes in; it converts the fiber's light signal into Ethernet for the UCG Ultra's WAN port. It measures ~9.7 x 7 x 1.25 in (W x D x H) and sits on the acrylic top cover (~11 x 7.9 in). It won't fit inside: the RackMate opening between the rails is ~222 mm / 8.75 in (DeskPi T0 spec, same 280 x 200 mm frame as the T1), about 1 in narrower than the ONT. Keep the fiber's bend gentle where it drops to the wall.

*Disclaimer: if the ONT does turn out to fit on the included 1U tray (for example, sliding in from the side with the acrylic plates off), it can move to slot 4 and this doc should be updated.*

## 4. Network

### Physical
- Frontier XGS-PON fiber into FRX523 ONT (no ISP router). ONT to UCG Ultra WAN (2.5 GbE).
- UCG Ultra to USW-Lite-8-PoE (1 GbE uplink).
\1 The Basement AP sits on a stand beside the rack, cabled into patch panel rear port 2 (PoE). Keep it about 1 m from the rack (metal and the ONT block signal) and as high as practical, face toward the house: it is also the wireless mesh uplink for Main and Office. Ceiling-mounting it centrally with one cable back to port 2 would give the best coverage later.
- Old eero Pro 6E retired.

### Switch port map (PROPOSED)
| Port | Device | Port profile |
|---|---|---|
| 1 | UCG Ultra uplink | Uplink |
| 2 | U7 Pro Basement (PoE) | AP trunk, all VLANs |
| 3 | M920q Tiny #1 | Native VLAN 1, tagged VLAN 20 |
| 4 | Tiny #2 (future) | Native VLAN 1, tagged VLAN 20 |
| 5 | Tiny #3 (future) | Native VLAN 1, tagged VLAN 20 |
| 6 | Old Proxmox box (temporary, during migration; currently on port 6) | Native VLAN 1, tagged VLAN 20 |
| 7 | Philips Hue bridge (side-mounted, via patch panel port 7) | Access, VLAN 10 IoT |
| 8 | Spare | |

Cable path for each node: device NIC -> patch panel rear port N -> patch panel front port N -> 0.5 ft jumper -> switch port N. Keep panel and switch numbers matched. The side-mounted Hue bridge follows the same path: a short (1-2 ft) cable around the rear edge into patch panel rear port 7.

### VLANs and subnets
| VLAN | Name | Subnet | Use |
|---|---|---|---|
| 1 | Default | 192.168.0.0/24 | Infra, Proxmox host management. SSIDs "Atlas Home" (5 GHz) and "Atlas Gaming" (6 GHz only, WPA3 only, so Wi-Fi 6E/7 devices only; MLO off) |
| 10 | IoT | 192.168.10.0/24 | SSID "Atlas IoT" (2.4 GHz) |
| 20 | Atlas Lab | 192.168.20.0/24 | Lab VMs/containers (tagged). SSID "Atlas Lab" (5 GHz) |

### Firewall / DNS
- Zone firewall (verified 2026-10-24): traffic between zones blocked by default. Exceptions: LAB and IoT to Pi-hole 192.168.0.101 on UDP 53; LAB to Proxmox 192.168.0.100 on 8006; personal laptop (austin-mac, 192.168.0.58, matched by MAC) to LAB, all traffic. Return traffic allowed automatically. The laptop's MAC (ba:b0:9f:7d:1a:3b) is a macOS private Wi-Fi address set to "Fixed" for Atlas Home, stable since June 2025. It only changes if the Mac forgets the network; then update the MAC in both the rule and the .0.58 reservation.
- Nord VPN policy route for IoT (disabled). QoS rule for gaming PC.
- DNS (intentional design, set 2026-10-24): every machine uses Pi-hole (192.168.0.101) first and Cloudflare 1.1.1.1 as a fallback, so filtering applies normally and internet DNS keeps working if Pi-hole is down. DHCP clients get both from UniFi (all three VLANs); Proxmox and its LXCs get them from the host DNS settings; the Talos nodes get them from Terraform `dns_server` + `dns_fallback_server`. Clients can occasionally use the fallback even when Pi-hole is up, so expect the odd unfiltered lookup or a brief `atlas.local` miss. Pi-hole forwards to local Unbound (127.0.0.1#5335) and Google 8.8.4.4.

### Known addresses
| Host | IP |
|---|---|
| UCG Ultra | 192.168.0.1 |
| USW-Lite-8-PoE | 192.168.0.2 |
| U7 Pro Basement | 192.168.0.3 |
| proxmox.atlas.local (current box) | 192.168.0.100 |
| Pi-hole | 192.168.0.101 |
| proxmox-cgrater.atlas.local (dormant, removed from cluster) | 192.168.0.102 |

### Address plan
Static addresses sit outside each DHCP range (verified in UniFi 2026-10-24).

| VLAN | Range | Use |
|---|---|---|
| 1 | .1 | Gateway |
| 1 | .2-.5 | Switch and APs |
| 1 | .10-.99 | DHCP (Mac reserved at .58) |
| 1 | .100 / .101 | Proxmox / Pi-hole |
| 1 | .102-.254 | Free for static |
| 20 | .1 | Gateway |
| 20 | .10 / .11 / .12 / .13 | talos-cp / talos-worker-01 / aap / talos-worker-02 |
| 20 | .14-.49 | Free for new VMs and LXCs |
| 20 | .50-.99 | MetalLB service IPs (.50 ArgoCD, .52-.53 vcsim) |
| 20 | .100-.254 | DHCP (lab Wi-Fi) |

### Power
Low power draw is a hard requirement. Rated maximums: ONT 24 W (label 16 V x 1.5 A), M920q 65 W adapter (35 W CPU), USW-Lite-8-PoE 52 W PoE budget (includes the U7 Pro, ~21 W). Measure the real total with a smart plug between the wall and the power strip once the rack is built.

## 5. Compute: Lenovo ThinkCentre M920q Tiny #1

Bought used on eBay (Oct 20 2026), i5-8500T, 32 GB listed (to verify on first boot).

From seller photos:
- 2.5" SATA caddy and cable included (spare caddy kit also on hand).
- Both SO-DIMM slots populated.
- Two M.2 2280 NVMe slots on the underside (SSD1, SSD2), both empty, thermal pads present.
- Empty M.2 E-key Wi-Fi slot. PCIe slot for riser + second NIC (rear knockout present).
- Rear: Lenovo slim-tip power, DisplayPort, HDMI, Flex I/O HDMI module, single 1 GbE (Intel I219, interface likely `enp0s31f6`, confirm with `ip a`), USB-A 3/4 at 10 Gbps, 5/6 at 5 Gbps.
- Front: USB-C and USB-A (5 Gbps).

### Storage plan
| Device | Role |
|---|---|
| 250 GB 2.5" SATA SSD (in caddy) | Proxmox OS |
| 1 TB NVMe in SSD1 (to buy, used OEM; future pick WD_Black SN7100) | VM storage |
| SSD2 | Free for later |
| Old 500 GB Crucial SSD in USB 3 enclosure (on a 10 Gbps port) | VM backup target / import source |

## 6. Proxmox networking (PROPOSED)
- `vmbr0` VLAN-aware, bridged to the single onboard NIC.
- Host management IP untagged on VLAN 1.
- Each VM/CT network device tagged VLAN 20.
- Switch port: native VLAN 1, tagged VLAN 20.

## 7. Workloads

Current single node (proxmox.atlas.local, Proxmox VE 9.2.21, rebuilt Oct 19 2026):
| ID | Name | Type |
|---|---|---|
| CT 102 | atlas-pihole | LXC |
| VM 200 | talos-cp | Talos control plane |
| VM 201 | talos-worker-01 | Talos worker |

Storage there: `local-zfs` on the 250 GB, plus `CRUCIAL_SSD_512GB`.

Target state:
- Proxmox on M920q nodes, growing from 1 to 3 Tinys (eventual 3-node Proxmox cluster).
- Three-node Kubernetes cluster on Talos VMs carrying most workloads: talos-cp (VM 200, 192.168.20.10), talos-worker-01 (VM 201, 192.168.20.11) and a new talos-worker-02 (VM 202, 192.168.20.13, talos-worker-02.atlas.local, 2 vCPU / 6 GB / 75 GB). Added by appending 192.168.20.13 to `worker_ips` in Terraform, which pins its MAC to BC:24:11:00:02:02; also add its Pi-hole DNS record.
- Red Hat Ansible Automation Platform on its own RHEL 9 VM, `aap.atlas.local` at 192.168.20.12 (VLAN 20, ~4 vCPU / 16 GB / 100 GB), installed with the containerized installer in the growth topology with its bundled Postgres. Not in the Talos cluster: the AAP operator is only supported on OpenShift. Replaces AWX, which was removed on 2026-10-24 along with its awx-postgres LXC (CT 105); its database and secrets are backed up in /root/awx-backup-20261024 on the Proxmox host. Needs the 64 GB RAM upgrade.
- Pi-hole and other lab services. More Kubernetes services and LXC containers are expected but not decided yet: new cluster services get MetalLB IPs from the free part of the pool (.51, .54-.99), and the 64 GB RAM upgrade leaves roughly 25 GB of headroom for them.
- No NAS planned (no media/data hoard; personal files live on OneDrive).

## Backups (PROPOSED)
Target: the 500 GB Crucial SSD in a USB 3 enclosure behind Tiny #1, added to Proxmox as backup storage.

| What | How | When | Keep |
|---|---|---|---|
| Pi-hole (LXC 102) | Proxmox backup job (vzdump, snapshot mode) | Nightly | 7 daily, 4 weekly |
| AAP VM | Proxmox backup job, plus the AAP installer's backup playbook before upgrades | Nightly | 7 daily, 4 weekly |
| Talos VMs (200-202) | Proxmox backup job (nodes are rebuildable with Terraform) | Weekly | 2 |
| Kubernetes state | `talosctl etcd snapshot` from a cron job on the Proxmox host | Daily | 14 |
| Pi-hole settings | Teleporter export | After changes | Latest |
| Code and infrastructure | Git (GitHub) and Terraform Cloud state | Every push | Full history, off-site |

Restore: `pct restore` / `qmrestore` for guests; for the cluster, `terraform apply` then `talosctl bootstrap --recover-from` the latest etcd snapshot and let ArgoCD redeploy from Git. The USB SSD sits in the same rack, so sync etcd snapshots and AAP backups to OneDrive weekly for an off-site copy. Retention may need tuning once real backup sizes are known.

## 8. Migration plan
1. Install Proxmox on the 250 GB SATA in the Tiny (or transplant the current 250 GB, still being considered).
2. Attach old Crucial via USB to import existing VMs/CTs.
3. Fix NIC name in `/etc/network/interfaces` if moving the existing install.
4. Repurpose the Crucial as the backup target.
5. Retire the old box from switch port 6.

## 9. Open decisions
- Does Tiny #1 take over `proxmox.atlas.local` / 192.168.0.100, or get a new name/IP while both run side by side?
- Fresh install on the Tiny vs. transplanting the current 250 GB drive.
- Which side panel takes the power strip and Hue bridge, and whether that side keeps its acrylic plate.
- 10-inch mount models for UCG Ultra, switch, and M920q.
- 1 TB NVMe purchase timing.
- RAM upgrade to 64 GB (2 x 32 GB SO-DIMM) for AAP.

Lab notes are kept in Obsidian.
