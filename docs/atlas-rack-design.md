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
- Frontier XGS-PON fiber into FRX523 ONT (no ISP router). ONT to UCG Ultra WAN (2.5 GbE) with a short direct cable (1 ft Cat6) down the back of the rack, from the ONT's network port to the gateway's rear WAN port. It does not go through the patch panel: it's the internet link between two devices in the rack and never touches the switch. The link runs at 2.5 Gb/s (the gateway's WAN port), which only matters for a plan faster than 2.5 Gig. Leave the wall fiber a gentle loop into the back of the ONT; the ONT's power plug ("Fiber Service, DO NOT REMOVE") goes to the side-mounted strip.
- UCG Ultra to USW-Lite-8-PoE (1 GbE uplink).
- Three U7 Pro APs: Basement (wired, PoE from switch port 2, 192.168.0.3). Main and Office mesh wirelessly off Basement. House has no ethernet runs (has coax). The Basement AP sits on a stand beside the rack, cabled into patch panel rear port 2 (PoE). Keep it about 1 m from the rack (metal and the ONT block signal) and as high as practical, face toward the house: it is also the wireless mesh uplink for Main and Office. Ceiling-mounting it centrally with one cable back to port 2 would give the best coverage later.
- Old eero Pro 6E retired.

### Switch port map (PROPOSED)
| Port | Device | VLANs (target) |
|---|---|---|
| 1 | UCG Ultra uplink | Uplink, all VLANs |
| 2 | U7 Pro Basement (PoE) | AP trunk: native 1 (management), tagged 10, 20, 30 for the SSIDs |
| 3 | M920q Tiny #1 | VLAN 20 only, untagged (access port) |
| 4 | Tiny #2 (future) | VLAN 20 only, untagged |
| 5 | Tiny #3 (future) | VLAN 20 only, untagged |
| 6 | Old Proxmox box (temporary, during migration) | Native 1, tagged 20 (as today), then spare and disabled |
| 7 | Philips Hue bridge (side-mounted, via patch panel port 7) | VLAN 10 only, untagged (access port) |
| 8 | Break-glass management port (no jumper; plug a laptop straight into the switch) | VLAN 1 only, untagged (access port) |

Cable path for every cable that reaches the switch, including the gateway uplink (panel 1) and the Basement AP (panel 2): device -> patch panel rear port N -> patch panel front port N -> 0.5 ft jumper -> switch port N. Keep panel and switch numbers matched so only the short jumpers show at the front. The side-mounted Hue bridge follows the same path: a short (1-2 ft) cable around the rear edge into patch panel rear port 7. The only cable that skips the panel is ONT -> gateway WAN.

**Port VLAN settings today (verified 2026-10-24).** No port profiles are set; ports 6 and 7 have per-port overrides. Every port's native VLAN is Default (1) except port 7 (IoT, 10), and every port still allows **all** tagged VLANs (the UniFi default), which is how VLAN 20 reaches Proxmox today. The target settings in the table above replace this as part of the network redesign: in UniFi, set each port's native VLAN and tagged VLAN management (Block All for access ports, Custom for the AP and uplink).

### Network redesign (agreed 2026-10-25, done with the M920q install)
Goal: stronger isolation. VLAN 1 becomes a management network for network gear only; everyday devices move to a new Home VLAN; the whole Proxmox host, Pi-hole included, lives on the lab VLAN.

### VLANs and subnets (target)
| VLAN | Name | Subnet | Use | Wi-Fi |
|---|---|---|---|---|
| 1 | Management | 192.168.0.0/24 | Network gear only: gateway, switch, APs | None, by design. Wired break-glass access on switch port 8 |
| 30 | Home (new) | 192.168.30.0/24 | Everyday devices: phones, laptops, TVs, consoles, printer | "Atlas Home" (5 GHz) and "Atlas Gaming" (6 GHz only, WPA3 only, so Wi-Fi 6E/7 devices only; MLO off) |
| 10 | IoT | 192.168.10.0/24 | Smart-home devices, Hue bridge | "Atlas IoT" (2.4 GHz) |
| 20 | Atlas Lab | 192.168.20.0/24 | Proxmox host, Pi-hole, Talos cluster, AAP, lab services | "Atlas Lab" (5 GHz) |

Home gets its own firewall zone (HOME), separate from Management (the existing Internal zone), so the two can be isolated from each other.

No management Wi-Fi (decided 2026-10-25): it would broadcast the management network through the house. The laptop stays on Home and reaches Management through its firewall rule (443, 22). If Wi-Fi or a firewall change ever locks it out, switch port 8 is a **break-glass port**: VLAN 1 untagged, nothing normally plugged in. Plug the laptop's cable straight into switch port 8 (no patch panel jumper) to land on Management. It's only usable by someone at the rack. Label the port.

### Firewall (target)
Traffic between zones is blocked by default; replies to allowed connections are let through automatically.

| From | To | Allowed | Rule |
|---|---|---|---|
| austin-mac (Home, 192.168.30.58, matched by MAC) | Lab | All traffic | Allow Austin MAC to LAB |
| austin-mac | Management | TCP 443 (UniFi UI), TCP 22 (SSH to switch and APs) | Allow Austin MAC to Management |
| Home | IoT | All traffic (control lights, cast to speakers; needs mDNS across Home and IoT) | Allow Home to IoT |
| Home, IoT, Management | Pi-hole 192.168.20.3 | UDP/TCP 53 | Allow DNS to PiHole |
| Home, IoT, Lab | Gateway | DHCP, NTP, mDNS only; admin (443, 22) blocked except austin-mac | Restrict gateway admin (recommended) |
| Everything else between zones | | Blocked | Default |
| All zones | Internet | All traffic | Default |

Retired by the redesign: "Allow LAB DNS to PiHole" (Pi-hole is on the lab VLAN, so no firewall hop) and "Allow LAB to Proxmox API" (Proxmox is on the lab VLAN too). Today the gateway's own UI and SSH are reachable from every VLAN, because the predefined Gateway-zone policies allow all; the "Restrict gateway admin" rule closes that.

The laptop's MAC (ba:b0:9f:7d:1a:3b) is a macOS private Wi-Fi address set to "Fixed" for Atlas Home, stable since June 2025. Moving Atlas Home to VLAN 30 keeps the same SSID, so the MAC stays the same; update its reservation to 192.168.30.58.

Other UniFi settings: Nord VPN policy route for IoT (disabled); QoS rule for gaming PC (follows it to the Home VLAN).

### DNS (target)
Every machine uses Pi-hole (192.168.20.3, on the lab VLAN) first and Cloudflare 1.1.1.1 as a fallback, so filtering applies normally and internet DNS keeps working if Pi-hole or the lab host is down. DHCP on all four VLANs hands out both. Proxmox and its containers use the host DNS settings; the Talos nodes use Terraform `dns_server` (changes to 192.168.20.3) + `dns_fallback_server`. Clients can occasionally use the fallback even when Pi-hole is up, so expect the odd unfiltered lookup or a brief `atlas.local` miss. Pi-hole forwards to local Unbound (127.0.0.1#5335) and Google 8.8.4.4.

Why Pi-hole lives on the lab VLAN: it runs on the lab host, and whichever VLAN it sits on, the lab host has to carry that VLAN. On the lab VLAN, the host carries only VLAN 20, so the lab never touches Home or Management. Home, IoT and Management reach it through one DNS-only firewall rule. If home DNS should ever be independent of the lab, move Pi-hole to its own small box on Management.

### Known addresses (target)
| Host | IP |
|---|---|
| UCG Ultra (gateway) | 192.168.0.1 |
| USW-Lite-8-PoE | 192.168.0.2 |
| U7 Pro Basement / Main / Office | 192.168.0.3 / .4 / .5 |
| atlas-pihole (LXC 102) | 192.168.20.3 (today 192.168.0.101) |
| proxmox.atlas.local (M920q Tiny #1) | 192.168.20.5 (today 192.168.0.100 on the old tower) |
| Tiny #2 / #3 (future) | 192.168.20.6 / .7 |
| austin-mac | 192.168.30.58 (DHCP reservation; today 192.168.0.58) |

### Address plan (target)
Static addresses sit outside each DHCP range.

| VLAN | Range | Use |
|---|---|---|
| 1 | .1 | Gateway |
| 1 | .2-.5 | Switch and APs |
| 1 | .10-.99 | DHCP, for adopting new network gear |
| 30 | .1 | Gateway |
| 30 | .10-.254 | DHCP (Mac reserved at .58; printer gets a reservation too) |
| 10 | .100-.254 | DHCP |
| 20 | .1 | Gateway |
| 20 | .3 | atlas-pihole |
| 20 | .5 / .6 / .7 | Proxmox nodes: Tiny #1 / #2 / #3 |
| 20 | .10 / .11 / .12 / .13 | talos-cp / talos-worker-01 / aap / talos-worker-02 |
| 20 | .14-.49 | Free for new VMs and LXCs |
| 20 | .50-.99 | MetalLB service IPs (.50 ArgoCD, .52-.53 vcsim) |
| 20 | .100-.254 | DHCP (lab Wi-Fi) |

### MetalLB service IPs
- Every LoadBalancer service pins its address so the address plan stays true. New services use the annotation `metallb.io/loadBalancerIPs: 192.168.20.X`; ArgoCD (.50) and vcsim (.52-.53) use the older `spec.loadBalancerIP` field, which still works.
- ArgoCD's .50 pin was set directly in the cluster, not in this repo; a reinstall of ArgoCD could come back on a different address. To do: add it to the repo.
- Never give a VM or LXC a static address in .50-.99: MetalLB assumes it owns the whole pool. Next free service IP: .51.
- How MetalLB works is explained in [architecture.md](architecture.md).

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
- The whole host lives on VLAN 20 (Atlas Lab); nothing on it is tagged.
- Switch port 3: VLAN 20 untagged, no tagged VLANs (access port).
- `vmbr0` bridged to the single onboard NIC. VLAN-aware can stay on for flexibility, but no guest uses a tag.
- Host management: 192.168.20.5/24, gateway 192.168.20.1, DNS 192.168.20.3 then 1.1.1.1.
- Guests: no VLAN tag. In Terraform, `vlan_id` becomes unset for the Talos VMs; Pi-hole (LXC 102) moves to 192.168.20.3/24, gateway .20.1.
- Don't mix styles: with VLAN 20 untagged on the port, a guest that sends VLAN 20 tagged frames would be dropped or misdelivered.

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

### Network cutover (with the M920q install)
1. UniFi: create the Home network (VLAN 30, 192.168.30.0/24, DHCP .10-.254, DNS 192.168.20.3 then 1.1.1.1) and a HOME firewall zone; enable mDNS across Home and IoT.
2. UniFi: move the "Atlas Home" and "Atlas Gaming" SSIDs to Home; reserve 192.168.30.58 for austin-mac and an address for the printer. Set switch port 8 to VLAN 1 untagged, Block All tagged (break-glass port), and test it once with the laptop.
3. Install Proxmox on the Tiny at 192.168.20.5; set switch port 3 to VLAN 20 untagged only.
4. Move Pi-hole (LXC 102) to 192.168.20.3, untagged; update `proxmox.atlas.local` and other records.
5. UniFi: set DHCP DNS to 192.168.20.3 + 1.1.1.1 on every network; add the target firewall rules and retire the two lab rules.
6. Terraform: `proxmox_endpoint` = https://192.168.20.5:8006, `dns_server` = 192.168.20.3, `vlan_id` unset. Kratix `proxmox-vm` promise: update the endpoint in the `proxmox-credentials` secret.
7. Repo: update `CLAUDE.md` (allowed commands) and `docs/proxmox.md` to the new addresses; run `scripts/check-lab-overview.py`.

### Hardware migration
1. Install Proxmox on the 250 GB SATA in the Tiny (or transplant the current 250 GB, still being considered).
2. Attach old Crucial via USB to import existing VMs/CTs.
3. Fix NIC name in `/etc/network/interfaces` if moving the existing install.
4. Repurpose the Crucial as the backup target.
5. Retire the old box from switch port 6.

## 9. Open decisions
- Fresh install on the Tiny vs. transplanting the current 250 GB drive.
- Which side panel takes the power strip and Hue bridge, and whether that side keeps its acrylic plate.
- 10-inch mount models for UCG Ultra, switch, and M920q.
- 1 TB NVMe purchase timing.
- RAM upgrade to 64 GB (2 x 32 GB SO-DIMM) for AAP.

Lab notes are kept in Obsidian.
