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
| Power | Reuse existing power strip (no rack PDU, decided against on cost). Sits loose behind the rack for now; plan is to mount it on a side panel so it takes no U. Power bricks hidden behind |
| Side mounts | Planned: power strip on a side panel, near the rear edge so its cables stay short. Not mounted yet (as of 2026-11-07) |
| Included with T1 | 1U vented rack shelf (holds the Hue bridge in slot 8), 2x 1U blank panels, 1x 1U venting blank panel, 2x acrylic side plates, acrylic top cover (fan-ready), handles, feet, #10-32 rack screws |
| Still to buy | 10-inch mounts for UCG Ultra, USW-Lite-8-PoE, and M920q |

## 3. Rack elevation (top to bottom)

| Slot | Height | Device | Notes |
|---|---|---|---|
| 1 | 0.5U | 12-port patch panel | Pass-through. Front jumpers to switch |
| 2 | 1U | UniFi USW-Lite-8-PoE | 1 GbE |
| 3 | 1U | UniFi UCG Ultra | Gateway/router, 2.5 GbE WAN |
| 4 | 1U | Lenovo M920q Tiny #1 | Proxmox node `pve-01`, directly below the gateway. **VM backup drive:** old 500 GB Crucial SSD in a USB 3 enclosure, sitting behind the Tiny (import source during migration, then the backup target) |
| 5 | 1U | Blank (included 1U blank panel) | Spare slot |
| 6 | 1U | M920q Tiny #2 | Future. Included 1U blank panel until then |
| 7 | 1U | M920q Tiny #3 | Future. Included 1U blank panel until then |
| 8 | 1.5U | Philips Hue bridge | On the included 1U vented shelf, + 0.5U open |

**Space note:** 8U total: 4.5U used (patch panel, switch, gateway, Tiny #1, Hue shelf), 3.5U free (slot 5, slots 6–7 reserved for Tiny #2 and #3, and 0.5U under the shelf). The ONT sits on top and the power strip sits behind the rack, so neither takes a U.

**Outside the rack:** the old Proxmox host, a tower (the old gaming PC, see [proxmox-install.md](runbooks/proxmox-install.md)), stands beside the rack until its guests move to Tiny #1. Its cable goes into patch panel rear port 8.

**ONT placement: on top of the rack.** The ONT (Optical Network Terminal, Frontier FRX523) is the box where the fiber comes in; it converts the fiber's light signal into Ethernet for the UCG Ultra's WAN port. It measures ~9.7 x 7 x 1.25 in (W x D x H) and sits on the acrylic top cover (~11 x 7.9 in). It won't fit inside: the RackMate opening between the rails is ~222 mm / 8.75 in (DeskPi T0 spec, same 280 x 200 mm frame as the T1), about 1 in narrower than the ONT. Keep the fiber's bend gentle where it drops to the wall.

*Disclaimer: if the ONT does turn out to fit on the included 1U tray (for example, sliding in from the side with the acrylic plates off), it can move to slot 4 and this doc should be updated.*

## 4. Network

### Physical
- Frontier XGS-PON fiber into FRX523 ONT (no ISP router). ONT to UCG Ultra WAN (2.5 GbE) with a short direct cable (1 ft Cat6) down the back of the rack, from the ONT's network port to the gateway's rear WAN port. It does not go through the patch panel: it's the internet link between two devices in the rack and never touches the switch. The link runs at 2.5 Gb/s (the gateway's WAN port), which only matters for a plan faster than 2.5 Gig. Leave the wall fiber a gentle loop into the back of the ONT; the ONT's power plug ("Fiber Service, DO NOT REMOVE") goes to the side-mounted strip.
- UCG Ultra LAN port 4 to USW-Lite-8-PoE port 5 (1 GbE uplink).
- Three U7 Pro APs: Basement (wired, PoE from switch port 4, 192.168.0.3). Main and Office mesh wirelessly off Basement. House has no ethernet runs (has coax). The Basement AP sits on a stand beside the rack, cabled into patch panel rear port 6 (PoE), jumpered to switch port 4. Keep it about 1 m from the rack (metal and the ONT block signal) and as high as practical, face toward the house: it is also the wireless mesh uplink for Main and Office. Ceiling-mounting it centrally with one cable back to panel port 6 would give the best coverage later.
- Old eero Pro 6E retired.

### Switch port map

**Actual** layout checked in UniFi on 2026-11-07. **Target** is the network redesign. No port profiles are set; ports 3, 6 and 7 have per-port overrides, and every other port still uses UniFi's defaults (native Default/1, all tagged VLANs allowed).

| Switch port | Patch panel | Actual device | Actual VLANs | Target |
|---|---|---|---|---|
| 1 | — | Empty | default | |
| 2 | — | Empty | default | |
| 3 | 5 | M920q Tiny #1 (`pve-01`, port named `pve-01`) | native 20, tagged Block All, PoE off | Same (VLAN 20 access port) |
| 4 | 6 | U7 Pro Basement (PoE) | native 1, all tagged | AP trunk: native 1, tagged 10, 20, 30 |
| 5 | 7 | Uplink to UCG Ultra LAN port 4 | native 1, all tagged | Same |
| 6 | 8 | Old Proxmox tower, outside the rack (`proxmox`, 192.168.0.100) | native 1, all tagged | Retired after migration; then free |
| 7 | 9 | Philips Hue bridge (bottom shelf, slot 8) | native 10 (IoT), all tagged | VLAN 10 access port (Block All tagged) |
| 8 | — | Empty (break-glass; plug straight into the switch) | default | VLAN 1 access port, Block All tagged; not set up yet |

Patch panel ports 1–4 and 10–12 are empty.

**UCG Ultra ports:** 5 (2.5 GbE) WAN to the ONT, 4 to the switch, 1–3 empty.

Cable path for every cable that reaches the switch, including the gateway uplink and the Basement AP: device -> patch panel rear port -> patch panel front port -> 0.5 ft jumper -> switch port. The switch sits under the middle of the wider panel, so **panel port N+2 jumpers to switch port N** (panel 5–9 to switch 3–7; checked on the rack 2026-11-07). The Hue bridge on the bottom shelf follows the same path, up the back of the rack into patch panel rear port 9. The only cable that skips the panel is ONT -> gateway WAN.

### Network redesign (agreed 2026-10-25, done with the M920q install)
Goal: stronger isolation. VLAN 1 becomes a management network for network gear only; everyday devices move to a new Home VLAN; the whole Proxmox host, Pi-hole included, lives on the lab VLAN.

### VLANs (target)

| VLAN | Name | Use | Wi-Fi |
|---|---|---|---|
| 1 | Management | Network gear only: gateway, switch, APs | None, by design. Break-glass on switch port 8 |
| 10 | IoT | Smart-home devices, Hue bridge | "Atlas IoT" (2.4 GHz) |
| 20 | Atlas Lab | Proxmox host, Pi-hole, Talos cluster, AAP, lab services | "Atlas Lab" (5 GHz) |
| 30 | Home | Everyday devices: phones, laptops, TVs, consoles, printer | "Atlas Home" (5 GHz), "Atlas Gaming" (6 GHz, WPA3 only) |

Subnets, DHCP ranges, and static IP assignments: see [network-address-plan.md](network-address-plan.md).

Home gets its own firewall zone (HOME), separate from Management (the existing Internal zone), so the two can be isolated from each other.

No management Wi-Fi (decided 2026-10-25): it would broadcast the management network through the house. If one is ever needed as a way back in during the move, it's temporary and deleted afterwards. The laptop stays on Home and reaches Management through its firewall rule (443, 22). If Wi-Fi or a firewall change ever locks it out, switch port 8 is a **break-glass port**: VLAN 1 untagged, nothing normally plugged in. Plug the laptop's cable straight into switch port 8 (no patch panel jumper) to land on Management. It's only usable by someone at the rack. Label the port.

### Firewall (target)
Traffic between zones is blocked by default; replies to allowed connections are let through automatically.

| From | To | Allowed | Rule |
|---|---|---|---|
| austin-mac (Home, matched by MAC) | Lab | All traffic | Allow Austin MAC to LAB |
| austin-mac | Management | TCP 443 (UniFi UI), TCP 22 (SSH to switch and APs) | Allow Austin MAC to Management |
| Home | IoT | All traffic (control lights, cast to speakers; needs mDNS across Home and IoT) | Allow Home to IoT |
| Home, IoT, Management | Pi-hole (`atlas-pihole.atlas.local`) | UDP/TCP 53 | Allow DNS to PiHole |
| Home, IoT, Lab | Gateway | DHCP, NTP, mDNS only; admin (443, 22) blocked except austin-mac | Restrict gateway admin (recommended) |
| Everything else between zones | | Blocked | Default |
| All zones | Internet | All traffic | Default |

Retired by the redesign: "Allow LAB DNS to PiHole" (Pi-hole is on the lab VLAN, so no firewall hop) and "Allow LAB to Proxmox API" (Proxmox is on the lab VLAN too). Today the gateway's own UI and SSH are reachable from every VLAN, because the predefined Gateway-zone policies allow all; the "Restrict gateway admin" rule closes that.

The laptop's MAC (ba:b0:9f:7d:1a:3b) is a macOS private Wi-Fi address set to "Fixed" for Atlas Home, stable since June 2025. Moving Atlas Home to VLAN 30 keeps the same SSID, so the MAC stays the same; update its reservation to 192.168.30.58.

Other UniFi settings: Nord VPN policy route for IoT (disabled); QoS rule for gaming PC (follows it to the Home VLAN).

### DNS (target)

Every machine uses Pi-hole (`atlas-pihole.atlas.local`, on the lab VLAN) first and Cloudflare `1.1.1.1` as a fallback. DHCP on all four VLANs hands out both. Pi-hole forwards to local Unbound and Google `8.8.4.4`.

Why Pi-hole lives on the lab VLAN: the lab host has to carry whichever VLAN Pi-hole is on. On VLAN 20, the host carries only the lab VLAN. Home, IoT, and Management reach it through one DNS-only firewall rule.

Static IP assignments and DNS records: see [network-address-plan.md](network-address-plan.md).

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
| 1 TB NVMe (installed 2026-11) | Proxmox OS and all guests, one ZFS pool (decided 2026-11-07) |
| SSD2 | Free for later |
| Old 500 GB Crucial SSD in USB 3 enclosure (on a 10 Gbps port) | VM backup target / import source |

## 6. Proxmox networking (PROPOSED)
- The whole host lives on VLAN 20 (Atlas Lab); nothing on it is tagged.
- Switch port 3: VLAN 20 untagged, Block All tagged (access port). Set; port named `pve-01`.
- `vmbr0` bridged to the single onboard NIC. VLAN-aware can stay on for flexibility, but no guest uses a tag.
- Guests: no VLAN tag. In Terraform, `vlan_id` becomes unset for the Talos VMs.
- Don't mix styles: with VLAN 20 untagged on the port, a guest that sends VLAN 20 tagged frames would be dropped or misdelivered.
- Host IP and guest IP assignments: see [network-address-plan.md](network-address-plan.md).

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
- Three-node Kubernetes cluster on Talos VMs: talos-cp (VM 200), talos-worker-01 (VM 201), and talos-worker-02 (VM 202, planned — pending M920q hardware). 2 vCPU / 6 GB / 75 GB per worker.
- Red Hat Ansible Automation Platform on its own RHEL 9 VM (`aap.atlas.local`, VLAN 20, ~4 vCPU / 16 GB / 100 GB), containerized installer, growth topology with bundled Postgres. Not in the Talos cluster — the AAP operator is only supported on OpenShift. Replaces AWX (removed 2026-10-24; backup in `/root/awx-backup-20261024` on the Proxmox host). Needs the 64 GB RAM upgrade.
- Pi-hole and other lab services. More Kubernetes services and LXC containers are expected but not decided yet.
- Local LLM box (`llm.atlas.local`): the former gaming PC nicknamed **cgrater** ("cheese grater" case; i7-11700KF, RTX 3080), previously a Proxmox host `proxmox-cgrater.atlas.local` (`192.168.0.102`). A physical machine beside the rack on VLAN 20, not a Proxmox guest; wired only, Wi-Fi off. Offline (as of 2026-11-07): it has no RAM and waits until memory is bought.
- No NAS planned (personal files live on OneDrive).

IP assignments for all workloads: see [network-address-plan.md](network-address-plan.md).

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
1. UniFi: create the Home network (VLAN 30) and a HOME firewall zone; enable mDNS across Home and IoT.
2. UniFi: move the "Atlas Home" and "Atlas Gaming" SSIDs to VLAN 30; reserve `austin-mac` and printer addresses. Set switch port 8 to VLAN 1 untagged, Block All tagged (break-glass port), and test it once with the laptop.
3. Install Proxmox on the Tiny (`pve-01`, `192.168.20.5`) on switch port 3, already VLAN 20 untagged only. Runs in parallel with the old host.
4. Move Pi-hole (LXC 102) to its target VLAN 20 address; update all DNS records. Update the LLM box's static DNS to point at the new Pi-hole address.
5. UniFi: set DHCP DNS to Pi-hole + `1.1.1.1` on every network; add the target firewall rules and retire the two old lab rules.
6. Terraform: update `proxmox_endpoint`, `dns_server`, and unset `vlan_id`. Update the Kratix `proxmox-vm` promise endpoint in the `proxmox-credentials` secret.
7. Repo: update `CLAUDE.md` (allowed commands) and runbooks to the new addresses; run `scripts/check-lab-overview.py`.

Target IPs for the cutover: see [network-address-plan.md](network-address-plan.md).

### Hardware migration
1. Fresh install of Proxmox on the Tiny's 1 TB NVMe (ZFS, OS and guests on one disk), standalone, in parallel with the old host (decided 2026-11-07).
2. Move guests one at a time (backup on the old host, restore on `pve-01`), re-addressing or re-tagging each for VLAN 20.
3. Attach the old Crucial via USB if needed as an import source.
4. Repurpose the Crucial as the backup target.
5. Retire the old box from switch port 6 once it's empty.

## 9. Open decisions
- Mounting the power strip (loose behind the rack today): which side panel, and whether that side keeps its acrylic plate.
- 10-inch mount models for UCG Ultra, switch, and M920q.
- RAM upgrade to 64 GB (2 x 32 GB SO-DIMM) for AAP.

Lab notes are kept in Obsidian.
