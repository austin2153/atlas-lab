# Proxmox VE Installation & Configuration

This document covers how to install and configure Proxmox VE from scratch on the homelab server, including post-install setup and ZFS pool recovery.

## Hardware

| Component | Details |
|---|---|
| Server | Desktop PC |
| OS Drive | PNY CS900 250GB 2.5" SATA SSD |
| Data Drive 1 | Crucial CT512MX100SSD1 512GB SATA SSD (`CRUCIAL_SSD_512GB` ZFS pool) |
| Data Drive 2 | WDC WD10EURS 1TB HDD (`WD_SATA_1TB` ZFS pool) |
| Network | `192.168.0.100` on main LAN |
| Hostname | `proxmox` |

## Creating the Installer USB

On a Mac:

1. Download the latest Proxmox VE ISO from `https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso`
2. Identify the USB stick device:
   ```bash
   diskutil list
   ```
   Look for the external disk (e.g. `/dev/disk4`)

3. Unmount and flash:
   ```bash
   diskutil unmountDisk /dev/disk4
   sudo dd if=/path/to/proxmox-ve_9.x-x.iso of=/dev/rdisk4 bs=4m status=progress
   ```
   Use `rdisk4` (with the `r`) for faster writes. Takes ~5 minutes.

## Installation

Boot the Proxmox server from the USB stick (may need to set boot order in BIOS).

### Installer Settings

| Setting | Value |
|---|---|
| Target disk | PNY CS900 250GB (select only this disk — do NOT touch other drives) |
| Filesystem | **ZFS** (ext4 fails with initramfs error on this hardware — use "Graphical, nomodeset" → ZFS) |
| Country | United States |
| Timezone | America/Detroit |
| Hostname | `proxmox.atlas.local` |
| IP | `192.168.0.100/24` |
| Gateway | `192.168.0.1` |
| DNS | `192.168.0.101` (atlas-pihole) — use `8.8.8.8` temporarily if pihole is down |

### Notes
- The installer will **only** touch the selected target disk — `CRUCIAL_SSD_512GB` and `WD_SATA_1TB` are not affected
- After install, remove the USB and reboot

## Post-Install Configuration

### 1. Restore Claude SSH access (Mac)

The host key changed with the reinstall — clear the old one first:
```bash
ssh-keygen -R 192.168.0.100
```

Copy Claude's key to the new install (use your own password when prompted):
```bash
ssh-copy-id -i ~/.ssh/proxmox-claude.pub -o StrictHostKeyChecking=accept-new root@192.168.0.100
```

Test:
```bash
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 "echo connected"
```

### 2. Add non-free-firmware apt sources

Edit `/etc/apt/sources.list` to add `non-free-firmware`:

```
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
```

### 3. Update packages and install intel-microcode

```bash
apt-get update && apt-get upgrade -y
apt-get install intel-microcode -y
```

### 5. Reimport ZFS pools

After install the data drives are present but pools need to be imported. If the pools were last used by a different Proxmox install (different hostid), force-import with `-f`:

```bash
zpool import -f CRUCIAL_SSD_512GB
zpool import -f WD_SATA_1TB
```

Verify:
```bash
zpool status
```

### 6. Register ZFS pools as Proxmox storage

A fresh install only has `local` and `local-zfs`. The data pools must be registered so Proxmox can see VMs and LXCs stored on them:

```bash
pvesm add zfspool CRUCIAL_SSD_512GB --pool CRUCIAL_SSD_512GB --content images,rootdir --sparse
pvesm add zfspool WD_SATA_1TB --pool WD_SATA_1TB --content images,rootdir --sparse
```

Verify:
```bash
pvesm status
```

### 7. Recreate VM and LXC config files

After a fresh install, the config files in `/etc/pve/nodes/proxmox/lxc/` and `/etc/pve/nodes/proxmox/qemu-server/` are gone — only the ZFS data survives. Recreate them (the ZFS datasets tell you what exists):

```bash
zfs list -r CRUCIAL_SSD_512GB   # shows subvol-<vmid>-disk-0 for LXCs, vm-<vmid>-disk-* for VMs
```

Create `/etc/pve/nodes/proxmox/lxc/102.conf`:
```
arch: amd64
cores: 1
features: nesting=1
hostname: atlas-pihole
memory: 512
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:00:00:02,ip=192.168.0.101/24,gw=192.168.0.1,type=veth
onboot: 1
ostype: debian
rootfs: CRUCIAL_SSD_512GB:subvol-102-disk-0,size=8G
swap: 512
unprivileged: 1
```

Create `/etc/pve/nodes/proxmox/lxc/105.conf`:
```
arch: amd64
cores: 2
hostname: awx-postgres
memory: 1024
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:00:00:05,ip=192.168.20.12/24,gw=192.168.20.1,tag=20,type=veth
onboot: 1
ostype: debian
rootfs: CRUCIAL_SSD_512GB:subvol-105-disk-0,size=8G
swap: 512
unprivileged: 1
```

Create `/etc/pve/nodes/proxmox/lxc/106.conf`:
```
arch: amd64
cores: 1
hostname: share
memory: 512
mp0: /WD_SATA_1TB/share,mp=/mnt/share
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:00:00:06,ip=192.168.20.13/24,gw=192.168.20.1,tag=20,type=veth
onboot: 1
ostype: alpine
protection: 1
rootfs: WD_SATA_1TB:subvol-106-disk-0,size=2G
swap: 0
```

Create `/etc/pve/nodes/proxmox/qemu-server/200.conf`:
```
name: talos-cp
cores: 2
cpu: x86-64-v2-AES
memory: 4096
bios: ovmf
machine: q35
efidisk0: CRUCIAL_SSD_512GB:vm-200-disk-0,efitype=4m,size=1M
scsi0: CRUCIAL_SSD_512GB:vm-200-disk-1,size=20G,iothread=1,discard=on
scsihw: virtio-scsi-single
net0: virtio,bridge=vmbr0,tag=20,macaddr=BC:24:11:00:02:00
boot: order=scsi0
ostype: l26
onboot: 1
```

Create `/etc/pve/nodes/proxmox/qemu-server/201.conf`:
```
name: talos-worker-01
cores: 2
cpu: x86-64-v2-AES
memory: 6144
bios: ovmf
machine: q35
efidisk0: CRUCIAL_SSD_512GB:vm-201-disk-0,efitype=4m,size=1M
scsi0: CRUCIAL_SSD_512GB:vm-201-disk-1,size=75G,iothread=1,discard=on
scsihw: virtio-scsi-single
net0: virtio,bridge=vmbr0,tag=20,macaddr=BC:24:11:00:02:01
boot: order=scsi0
ostype: l26
onboot: 1
```

> **Note**: Do NOT use `pre-enrolled-keys=1` on the EFI disk for Talos VMs — Microsoft Secure Boot will block Talos from booting.

### 8. Start Pi-hole LXC

Pi-hole must come up first — everything else depends on DNS:

```bash
pct start 102
pct exec 102 -- systemctl is-active pihole-FTL   # should print "active"
```

### 9. Switch Proxmox DNS from temporary to Pi-hole

```bash
pvesh set /nodes/proxmox/dns --search atlas.local --dns1 192.168.0.101
```

### 10. Start remaining LXC containers

```bash
pct start 105   # awx-postgres
pct start 106   # share (requires WD_SATA_1TB pool to be imported)
pct list
```

### 11. Start Kubernetes VMs

```bash
qm start 200    # talos-cp
qm start 201    # talos-worker-01
```

Wait ~2 minutes for Talos to boot, then verify:
```bash
TALOSCONFIG=~/.talos/atlas-talos.talosconfig talosctl --nodes 192.168.20.10 health --server=false
kubectl get nodes
```

If nodes come up `NotReady,SchedulingDisabled`, uncordon them (they were cordoned on the last clean shutdown):
```bash
kubectl uncordon talos-cp talos-worker-01
```

### 12. Restore Proxmox API token

The API token is tied to the Proxmox install and does not survive a reinstall. Create a new one:
- Proxmox UI → Datacenter → Permissions → API Tokens → Add
- User: `root@pam`, Token ID: `terraform` (or whatever was used before), uncheck "Privilege Separation"
- Save the token secret to `~/.proxmox-credentials` on the Mac (chmod 600)

## LXC Reference

| VMID | Name | IP | Purpose |
|---|---|---|---|
| 102 | `atlas-pihole` | `192.168.0.101` | Pi-hole DNS for home network |
| 105 | `awx-postgres.atlas.local` | `192.168.20.12` | AWX external PostgreSQL database |
| 106 | `share.atlas.local` | `192.168.20.13` | Samba SMB share on WD_SATA_1TB |

## VM Reference

| VMID | Name | IP | Purpose |
|---|---|---|---|
| 200 | `talos-cp` | `192.168.20.10` | Talos Kubernetes control plane |
| 201 | `talos-worker-01` | `192.168.20.11` | Talos Kubernetes worker node |

## Network

| Parameter | Value |
|---|---|
| Proxmox IP | `192.168.0.100` |
| Bridge | `vmbr0` |
| VLAN 20 tag | Used for all Kubernetes/lab traffic (`192.168.20.0/24`) |
| Gateway | `192.168.0.1` (Home Cloud Gateway Ultra) |
| DNS | `192.168.0.101` (atlas-pihole) |

## See Also

- [proxmox-access.md](proxmox-access.md) — API token and SSH access setup
- [proxmox-upgrade.md](proxmox-upgrade.md) — Major version upgrade guide and issues log
- [awx-external-postgres.md](awx-external-postgres.md) — AWX database setup
- [proxmox-smb-share.md](proxmox-smb-share.md) — SMB share setup
