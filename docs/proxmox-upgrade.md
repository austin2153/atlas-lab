# Proxmox VE Upgrade Guide

This document tracks major Proxmox VE version upgrades — the pre-upgrade checklist, issues encountered, and how they were resolved.

## PVE 8 → PVE 9

### Overview

| Item | Value |
|---|---|
| From | Proxmox VE 8.4.19 / Debian 12 (Bookworm) |
| To | Proxmox VE 9.x / Debian 13 (Trixie) |
| Node | `proxmox` (192.168.0.100) |
| Upgrade date | TBD |
| Official guide | https://pve.proxmox.com/wiki/Upgrade_from_8_to_9 |

### Pre-Upgrade Checklist

Run Proxmox's official checker before proceeding:

```bash
pve8to9
```

All FAILUREs must be resolved. WARNINGs should be reviewed. Re-run until `FAILURES: 0`.

### Issues Encountered and Resolved

#### 1. proxmox-cgrater node removed from cluster

**Problem**: The second Proxmox node (`proxmox-cgrater`) was offline and being repurposed. With 2-node cluster and 1 node down, quorum was blocked (`Quorate: No`) — VMs and LXCs could not start.

**Resolution**:
```bash
pvecm expected 1        # force quorum with 1 node
pvecm delnode proxmox-cgrater   # remove the dead node
```

The `CS_ERR_NOT_EXIST` error from `delnode` is harmless — the node was already removed from `corosync.conf`. Verify with `pvecm status` showing `Quorate: Yes`.

#### 2. systemd-boot installed — FAIL

**Problem**: `pve8to9` reported: *"systemd-boot meta-package installed. This will cause problems on upgrades of other boot-related packages."*

**Resolution**:
```bash
apt-get remove systemd-boot systemd-boot-efi -y
```

#### 3. grub-efi-amd64 not installed — WARN

**Problem**: System booted in UEFI mode but `grub-efi-amd64` meta-package was missing. New GRUB versions would not be installed to `/boot/efi`. Also, a removable bootloader was found at `/boot/efi/EFI/BOOT/BOOTX64.efi` but GRUB was not set up to update it.

**Resolution**:
```bash
# Set debconf flag to update removable EFI path
echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u

# Install and reinstall grub-efi-amd64
apt-get install grub-efi-amd64 -y
apt-get install --reinstall grub-efi-amd64 -y
```

#### 4. intel-microcode not installed — WARN

**Problem**: Matching CPU microcode package not found. The `non-free-firmware` apt component was not enabled.

**Resolution**: Add `non-free-firmware` to `/etc/apt/sources.list`:

```
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
```

Then install:
```bash
apt-get update && apt-get install intel-microcode -y
```

### Pre-Upgrade Steps (in order)

1. **Update all packages on PVE 8 first**:
   ```bash
   apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
   ```

2. **Resolve all pve8to9 FAILUREs** (see issues above)

3. **Confirm checker passes**:
   ```bash
   pve8to9
   # Must show: FAILURES: 0
   ```

### Upgrade Steps

> **Warning**: This will reboot Proxmox. All VMs and LXCs (including `atlas-pihole`) will be offline for ~5-10 minutes. Home network DNS will be down during this window.

1. **Update apt sources from Bookworm → Trixie**:
   ```bash
   sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
   # Also update any PVE-specific sources in /etc/apt/sources.list.d/
   sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-no-subscription.list
   ```

2. **Update apt and do the dist-upgrade**:
   ```bash
   apt-get update
   DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
   ```

3. **Reboot**:
   ```bash
   reboot
   ```

4. **Verify after reboot**:
   ```bash
   pveversion
   pvecm status
   pct list
   qm list
   ```

### Post-Upgrade Notes

- LXCs and VMs should start automatically if they were set to `onboot: 1`
- Check `atlas-pihole` (LXC 102) comes back up and DNS resolves
- Check `awx-postgres` (LXC 105) and `share` (LXC 106) are running
- Check Talos VMs (200, 201) are running and Kubernetes cluster is healthy

### Remaining Warnings (acceptable for home lab)

- **Single node cluster** — expected after removing proxmox-cgrater
- **5 running guests** — informational only, fine to upgrade with guests running (they are stopped/restarted by the reboot)
- **Old kernel packages** (6.2.x) still installed — can be cleaned up after upgrade with `apt-get autoremove`

---

## OS Drive Failure During Upgrade

### What Happened

During the PVE 8 → 9 dist-upgrade, the Proxmox OS drive (Samsung SSD 840 Pro, 256GB, `sda`) began throwing I/O errors. The sustained write activity of the upgrade pushed the aging drive over the edge. Symptoms:

- `ICRC ABRT` errors on `sda` in dmesg
- EXT4 journal aborted, root filesystem remounted read-only
- SATA link negotiating at 1.5 Gb/s instead of 6.0 Gb/s
- 148 CRC errors in SMART data (`CRC_Error_Count`)
- Drive had 102,377 power-on hours (~14 years old)

SMART reported PASSED overall, but the SATA interface errors and consistent I/O failures on writes confirmed the drive was failing.

Reseating the SATA cable briefly restored the 6.0 Gb/s link but errors resumed within minutes under write load — the drive's NAND or controller is failing.

### Impact

- Proxmox OS is unbootable in a stable state (filesystem goes read-only almost immediately)
- ZFS storage pools (`CRUCIAL_SSD_512GB` on `sdc`, `WD_SATA_1TB` on `sdb`) are **completely unaffected** — data is safe
- LXCs and VMs cannot start because ZFS pools cannot be imported (ZFS module also had a key signing issue with PVE 9 kernel — separate problem)

### Resolution: Fresh PVE 9 Install on New Drive

**New drive**: PNY CS900 250GB 2.5" SATA III (replacing the Samsung 840 Pro)

#### Step 1 — Prepare USB installer
- Download PVE 9 ISO from proxmox.com
- Flash to USB with Balena Etcher or Rufus
- Boot Proxmox server from USB

#### Step 2 — Install PVE 9
- Select the PNY 250GB as the target disk
- Set hostname: `proxmox`
- Set IP: `192.168.0.100`, gateway `192.168.0.1`, DNS `192.168.0.101`
- Installer will NOT touch `sdb` or `sdc` — ZFS data survives

#### Step 3 — Reimport ZFS pools (after first boot)
```bash
zpool import CRUCIAL_SSD_512GB
zpool import WD_SATA_1TB
```

#### Step 4 — Restore Claude SSH access
```bash
echo "<contents of ~/.ssh/proxmox-claude.pub>" >> /root/.ssh/authorized_keys
```

#### Step 5 — Verify LXCs and VMs
- LXCs (102 atlas-pihole, 105 awx-postgres, 106 share) should reappear in Proxmox UI
- Start each and confirm healthy
- Kubernetes VMs (200 talos-cp, 201 talos-worker-01) should come back up
