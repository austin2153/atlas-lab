# pve-01 (Proxmox on the M920q)

The new Proxmox host: a Lenovo M920q Tiny that lives directly on the lab VLAN (VLAN 20). It runs in parallel with the old host (`proxmox`, `192.168.0.100`, see [proxmox-install.md](proxmox-install.md)) while guests move over one at a time. This is the host part of the network redesign in [lab-infrastructure.md](../lab-infrastructure.md) and [network-address-plan.md](../network-address-plan.md).

**Status:** being built (started 2026-11-07). Proxmox not installed yet.

## Overview

| Item | Value |
|---|---|
| Hostname | `pve-01` (`pve-01.atlas.local`) |
| IP | `192.168.20.5/24` (reserved in the address plan), gateway `192.168.20.1` |
| DNS | Pi-hole `192.168.0.101`, then `1.1.1.1`, `9.9.9.9` as fallbacks; a replacement DNS server later |
| Network | VLAN 20 untagged on the switch port; nothing on the host is tagged |
| Switch / patch panel | USW-Lite-8-PoE port 3 (named `pve-01`: native VLAN 20, tagged Block All, PoE off) ← patch panel 5 |
| Rack | Slot 4, directly below the gateway |
| Hardware | Intel i5-8500T (6 cores, 35 W), 32 GB RAM (to verify), 1 GbE Intel I219 |
| Storage | 1 TB NVMe, ZFS: Proxmox OS and all guests on one disk |
| Proxmox | Proxmox VE 9.2-1 ISO (checksum verified 2026-11-07), on the 16 GB Cruzer Glide |

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Install | Fresh install, not a transplant of the old host's drive | Clean start on new hardware; guests move individually |
| Storage | One 1 TB NVMe, ZFS (single disk) | Our choice: OS and guests together; ZFS gives snapshots and compression. No redundancy with one disk, so backups matter |
| Cluster | **Standalone**, not clustered with the old host | A two-node cluster loses quorum when either node is down. Guests move by backup and restore |
| Network | Host and guests on VLAN 20 untagged; `vmbr0` VLAN-aware | Matches the redesign. Home Assistant (VLAN 10) will need VLAN 10 tagged on port 3 when it moves, not before |
| Old host | Keeps running until it's empty, then retired | Low-risk migration |

## Credentials

- **Root password:** Bitwarden item *Proxmox (pve-01)*. Create it and generate the password **before** the install; you type it in the installer.
- **SSH:** the Mac key (`~/.ssh/id_ed25519`) and Claude's key (`~/.ssh/proxmox-claude`), same as the old host.
- **API token:** created after install; saved on the Mac in `~/.proxmox-pve01-credentials` (same variable names as `~/.proxmox-credentials`, see [lab-credentials.md](../lab-credentials.md)).

## Before you start

- [ ] USB stick with the Proxmox VE 9.2-1 installer
- [ ] Monitor (HDMI or DisplayPort) and a USB keyboard on the M920q
- [ ] Network cable in (switch port 3 should show a link)
- [ ] Bitwarden item *Proxmox (pve-01)* created, password generated
- [ ] Mac on the home network (it reaches VLAN 20 through *Allow Austin MAC to LAB*)

## BIOS

Power on and press **F1** for the BIOS setup; **F12** opens the one-time boot menu (Lenovo's keys for the M920q). Menu names below are from Lenovo's ThinkCentre BIOS and may differ slightly by BIOS version.

| Where | Setting | Why |
|---|---|---|
| Main → System Summary | Check **32 GB RAM** and that the **1 TB NVMe** is listed (the only drive; the 2.5" bay is empty) | Confirms the hardware before installing |
| Advanced → CPU Setup | **Intel Virtualization Technology: Enabled** | VMs need VT-x |
| Advanced → CPU Setup | **VT-d: Enabled** | PCI/USB passthrough later |
| Power | **After Power Loss: Power On** | Comes back by itself after a power cut |
| Startup | **CSM: Disabled** (UEFI only) | Proxmox installs in UEFI mode |
| Security → Secure Boot | Leave as is. If the installer won't boot, set it to **Disabled** | Proxmox VE supports Secure Boot since 8.1 |

Save and exit (**F10**), then boot the USB stick from the **F12** menu.

## Install

Choose **Install Proxmox VE (Graphical)**. Source: [Proxmox VE installation](https://pve.proxmox.com/pve-docs/chapter-pve-installation.html).

| Screen | Setting |
|---|---|
| EULA | I agree |
| Target harddisk | Click **Options** → Filesystem **zfs (RAID0)** (a single disk; RAID0 is just the installer's name for it). Harddisk 0: **the 1 TB NVMe** (the only disk, besides the USB stick, which isn't offered) |
| ZFS advanced options | Leave the defaults (ashift 12, compress on, checksum on, copies 1; ARC max size defaults to 10% of RAM, about 3.2 GB) |
| Location and time zone | Country **United States**, time zone **America/New_York**, keyboard **U.S. English** |
| Password and email | Root password from Bitwarden *Proxmox (pve-01)*; email: your personal address (system notifications) |
| Management network | Interface: the onboard Intel I219 (likely `enp0s31f6`) · Hostname (FQDN) **`pve-01.atlas.local`** · IP **`192.168.20.5/24`** · Gateway **`192.168.20.1`** · DNS **`192.168.0.101`** (the installer takes one; fallbacks come later) |
| Summary | Check everything, leave *Automatically reboot after successful installation* ticked, **Install** |

When it reboots, **remove the USB stick**. The console shows `https://192.168.20.5:8006/` when it's up.

## Post-install

From the Mac unless noted.

**1. First login:** open **https://192.168.20.5:8006**, accept the self-signed certificate warning, log in as `root`, realm *Linux PAM*. The "No valid subscription" popup is cosmetic.

**2. SSH keys and config**

```bash
# Clear any old host key for this IP, then install both keys (asks for the root password once each)
ssh-keygen -R 192.168.20.5
ssh-copy-id -i ~/.ssh/id_ed25519.pub -o StrictHostKeyChecking=accept-new root@192.168.20.5
ssh-copy-id -i ~/.ssh/proxmox-claude.pub root@192.168.20.5
```

Add to `~/.ssh/config`, then `ssh pve-01`:

```text
Host pve-01
    HostName 192.168.20.5
    User root
    IdentityFile ~/.ssh/id_ed25519
    SetEnv TERM=xterm-256color
```

**3. Repositories** (on pve-01). A fresh install enables the paid **enterprise** repos, so `apt-get update` fails with `401 Unauthorized`. Switch to the free ones ([Package Repositories](https://pve.proxmox.com/wiki/Package_Repositories)):

```bash
cd /etc/apt/sources.list.d
grep Components debian.sources          # should include non-free-firmware

# Disable enterprise (keeps the files, easy to revert)
echo "Enabled: no" >> pve-enterprise.sources
echo "Enabled: no" >> ceph.sources

cat > proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

cat > ceph-no-subscription.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

apt-get update                          # must finish with no errors
```

**4. Updates and microcode** (on pve-01). `dist-upgrade`, not `upgrade`, so new kernel and PVE packages come in:

```bash
apt-get dist-upgrade -y
apt-get install -y intel-microcode
reboot
```

**5. DNS fallbacks** (on pve-01). Debian moves to the next server only when one doesn't answer:

```bash
pvesh set /nodes/pve-01/dns --search atlas.local --dns1 192.168.0.101 --dns2 1.1.1.1 --dns3 9.9.9.9
cat /etc/resolv.conf
```

**6. VLAN-aware bridge** (on pve-01). UI: pve-01 → System → Network → `vmbr0` → Edit → tick **VLAN aware** → OK → **Apply Configuration**. `/etc/network/interfaces` should then have:

```text
auto vmbr0
iface vmbr0 inet static
        address 192.168.20.5/24
        gateway 192.168.20.1
        bridge-ports enp0s31f6
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

**7. Checks** (on pve-01)

```bash
pveversion                       # pve-manager/9.x
free -g                          # ~31 total
zpool status rpool               # ONLINE, the NVMe only
zfs list                         # rpool, rpool/data, rpool/ROOT
ip -br a                         # vmbr0 192.168.20.5/24
ping -c 2 192.168.20.1           # gateway
getent hosts download.proxmox.com
timedatectl                      # America/New_York, NTP synchronized
```

**8. API token.** UI: Datacenter → Permissions → API Tokens → **Add**: user `root@pam`, Token ID `terraform`, **untick Privilege Separation**. Copy the secret (shown once) into `~/.proxmox-pve01-credentials` on the Mac and `chmod 600` it:

```bash
PROXMOX_URL=https://192.168.20.5:8006
PROXMOX_TOKEN_ID=root@pam!terraform
PROXMOX_TOKEN_SECRET=<secret>
PROXMOX_SSH_KEY=~/.ssh/proxmox-claude
PROXMOX_SSH_USER=root
```

Terraform keeps pointing at the old host until the Talos VMs move.

**9. Pi-hole record.** `dns.hosts` is a whole-list setting: read it and append, or every other record is wiped:

```bash
ssh proxmox 'cur=$(pct exec 102 -- pihole-FTL --config dns.hosts)
new=$(echo "$cur" | python3 -c "import sys,json; s=sys.stdin.read().strip().strip(\"[]\"); items=[x.strip() for x in s.split(\",\") if x.strip()]; items.append(\"192.168.20.5 pve-01.atlas.local\"); print(json.dumps(items))")
pct exec 102 -- pihole-FTL --config dns.hosts "$new"'

dig +short pve-01.atlas.local          # 192.168.20.5
```

Optional: Unbound's old `local-zones.conf` on CT 102 still maps `ubuntu-lxc.atlas.local` to `192.168.20.5`; remove those two lines and restart Unbound.

**10. Docs** (Claude can do these): address plan row for `192.168.20.5`, `CLAUDE.md` allowed commands for `192.168.20.5`, `lab-credentials.md` entry for `~/.proxmox-pve01-credentials`, and set this runbook's status to installed.

## Migration

Guests on the old host (2026-11-07). About 30 GB of guest data in total.

| ID | Name | Type | Today | On pve-01 | Status |
|---|---|---|---|---|---|
| 104 | `cloudflared` | LXC | VLAN 20 tagged, `.20.17` | untagged, same IP | Not started |
| 103 | `obsidian-mcp` | LXC | VLAN 20 tagged, `.20.16` | untagged, same IP | Not started |
| 203 | `vault` | VM | VLAN 20 tagged, `.20.15` | untagged, same IP | Not started |
| 200 | `talos-cp` | VM | VLAN 20 tagged, `.20.10` | untagged; Terraform `vlan_id` unset | Not started |
| 201 | `talos-worker-01` | VM | VLAN 20 tagged, `.20.11` | untagged; Terraform `vlan_id` unset | Not started |
| 102 | `atlas-pihole` | LXC | VLAN 1, `.0.101` | Not migrated: stays on the old host until a replacement DNS server exists (not planned yet) | — |
| 204 | `home-assistant` | VM | VLAN 10 tagged, `.10.10` | VLAN 10 tagged (needs port 3 change) | Not started |

**Method** (one guest at a time; the old copy stays until the new one is tested, so it can roll back):

```bash
# 1. Old host UI: guest > Backup > Backup now (mode: Stop, compression: zstd)

# 2. Old host shell: copy the backup to pve-01 (containers are vzdump-lxc-*)
scp /path/to/dump/vzdump-qemu-<id>-*.vma.zst root@192.168.20.5:/var/lib/vz/dump/

# 3. pve-01 UI: local > Backups > select the file > Restore (target: local-zfs)
# 4. Remove the VLAN 20 tag from the NIC (the port is native VLAN 20), boot, test, then shut down the old copy
```

**Firewall gap for step 2:** the old host is on Default (Internal zone) and UniFi blocks Internal → LAB, so it can't reach pve-01 today. Add a temporary UniFi policy, old host `192.168.0.100` → `192.168.20.5` TCP 22, and delete it when migration is done. The Mac already reaches VLAN 20 (*Allow Austin MAC to LAB*), so the web UI and SSH need no new rule.

Order to be decided. Things to carry over per guest: Proxmox firewall rules (103, 104), `onboot` and startup order, and Vault's "tell Austin before restarting" rule.

Open: orphaned `vm-100-disk-0/1` (about 8 GB) on the old host's `CRUCIAL_SSD_512GB` with no VM 100 config; confirm before deleting or migrating.

## References

- [Proxmox VE installation](https://pve.proxmox.com/pve-docs/chapter-pve-installation.html)
- [Package repositories](https://pve.proxmox.com/wiki/Package_Repositories)
- [ZFS on Linux](https://pve.proxmox.com/wiki/ZFS_on_Linux)
- [Backup and restore](https://pve.proxmox.com/pve-docs/chapter-vzdump.html)
