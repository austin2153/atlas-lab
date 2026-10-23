# Proxmox SMB Share

> **Status (2026-10-23): offline.** After the OS drive replacement and reinstall, the WD 1TB drive is not detected by the host at all (no `/dev/disk/by-id` entry, no importable `WD_SATA_1TB` pool), so LXC 106 has not been recreated. Check the drive's SATA/power cables or replace it, then follow the reinstall steps in [proxmox-install.md](proxmox-install.md) (import pool, register storage, recreate `106.conf`).

This document describes the design and configuration of a Samba file share hosted on the Proxmox server, accessible from macOS via Finder.

## Why This Exists

The Proxmox server has a dedicated 1TB WD SATA drive (`WD_SATA_1TB` ZFS pool) separate from the SSD pool used by VMs and LXCs. Rather than leave it unused, it serves as a general-purpose network share — accessible from the Mac laptop as a standard SMB mount.

## Design

```
Mac (Finder)
    │
    │  SMB (port 445)
    ▼
[share LXC]  192.168.20.13  Alpine Linux
    │
    │  bind-mount (via pct)
    ▼
[ZFS dataset]  WD_SATA_1TB/share  on Proxmox host
```

**Why an LXC instead of Samba on the Proxmox host directly?**

Running Samba on the Proxmox host is not recommended — it can interfere with Proxmox's own cluster networking and complicates upgrades. An LXC keeps it isolated and independently manageable (start, stop, destroy without touching the host).

**Why ZFS for the share data?**

The `WD_SATA_1TB` pool is already ZFS. A dedicated dataset (`WD_SATA_1TB/share`) is bind-mounted into the LXC so the actual data lives on the Proxmox host's ZFS pool — not inside the LXC's rootfs. This means:
- The LXC can be destroyed and recreated without losing share data
- ZFS provides checksums (silent corruption protection) and supports snapshots
- The dataset can be expanded or snapshotted independently

## Infrastructure

| Item | Value |
|---|---|
| LXC ID | 106 (Proxmox node `proxmox`) |
| Hostname | `share.atlas.local` |
| IP | `192.168.20.13` (Atlas Lab VLAN 20) |
| OS | Alpine Linux |
| LXC storage (rootfs) | `WD_SATA_1TB` |
| Share data | `WD_SATA_1TB/share` (ZFS dataset, bind-mounted) |
| Samba share name | `share` |
| Container protection | Enabled |

DNS entry managed in Pi-hole: `share.atlas.local → 192.168.20.13`

## LXC Configuration

The LXC is created with a bind-mount so the ZFS dataset appears inside the container at `/mnt/share`:

```bash
# Create the ZFS dataset on the host (run once)
zfs create WD_SATA_1TB/share

# The bind-mount is set via pct during container creation or after:
pct set <vmid> -mp0 /WD_SATA_1TB/share,mp=/mnt/share
```

The LXC must be **privileged** (not unprivileged) for the Samba bind-mount to work correctly with file ownership.

## Samba Configuration

Samba is installed inside the LXC:

```bash
apk add samba
```

`/etc/samba/smb.conf`:

```ini
[global]
   workgroup = WORKGROUP
   server string = atlas-samba
   security = user
   map to guest = never
   log level = 1

[share]
   path = /mnt/share
   valid users = austin
   read only = no
   browsable = yes
   create mask = 0664
   directory mask = 0775
```

A dedicated Samba user is created (separate from any OS user):

```bash
adduser -D austin
smbpasswd -a austin
```

Samba runs as a service:

```bash
rc-update add samba
rc-service samba start
```

## Connecting from macOS

In Finder: **Go → Connect to Server** (`⌘K`):

```
smb://share.atlas.local/share
```

Or by IP if DNS isn't resolving:

```
smb://192.168.20.13/share
```

Enter username `austin` and the Samba password when prompted. macOS will offer to save it in Keychain.

### Persist connection across reboots

To reconnect automatically on login:

1. Connect to the share manually via `⌘K`
2. Open **System Settings → General → Login Items & Extensions**
3. Under **Open at Login**, click `+` and select the mounted volume (`share.atlas.local`)

## Credentials

- **LXC root password**: stored at `~/.proxmox-samba-credentials` (chmod 600, not committed to git). Set during the community-scripts Alpine LXC wizard. Write it with:
  ```bash
  echo -n "Password: " && read -s p && echo && echo "$p" > ~/.proxmox-samba-credentials && chmod 600 ~/.proxmox-samba-credentials && unset p
  ```
- **Samba user password**: set interactively via `smbpasswd -a austin` inside the LXC. Saved to macOS Keychain on first Finder connect — not stored on disk anywhere else.

## Build Steps (How This Was Created)

These are the exact steps used to provision this from scratch. Follow them in order if you ever need to rebuild.

### 1. Create the ZFS dataset on the Proxmox host

Run on the Proxmox host (via SSH):

```bash
zfs create WD_SATA_1TB/share
zfs list WD_SATA_1TB/share  # verify
```

### 2. Create the Alpine LXC

Use the Proxmox web UI or `pct` to create a new container:

- **Container ID**: TBD (next available)
- **Hostname**: `share`
- **Template**: Alpine Linux
- **Storage (rootfs)**: `WD_SATA_1TB`
- **Disk size**: 2GB (rootfs only — share data lives in the bind-mounted dataset)
- **CPU**: 1 core
- **RAM**: 512MB
- **Network**: VLAN tag 20, static IP `192.168.20.13`, gateway `192.168.20.1`
- **DNS**: `192.168.0.101` (atlas-pihole)
- **Privileged container**: yes (required for bind-mount file ownership to work correctly)
- **Container protection**: enabled after setup

### 3. Add the bind-mount

After the container is created, temporarily disable protection, add the bind-mount, re-enable protection, then start (run on Proxmox host):

```bash
pct set 106 -protection 0
pct stop 106
pct set 106 -mp0 /WD_SATA_1TB/share,mp=/mnt/share
pct set 106 -protection 1
pct start 106
```

Verify the mount is visible inside the container:

```bash
pct exec 106 -- ls /mnt/share
```

### 4. Install and configure Samba

Inside the LXC:

```bash
pct exec <vmid> -- ash
apk update && apk add samba
```

Write `/etc/samba/smb.conf`:

```ini
[global]
   workgroup = WORKGROUP
   server string = atlas-share
   security = user
   map to guest = never
   log level = 1

[share]
   path = /mnt/share
   valid users = austin
   read only = no
   browsable = yes
   create mask = 0664
   directory mask = 0775
```

### 5. Create the Samba user

```bash
adduser -D austin
smbpasswd -a austin   # prompts for password — store it in macOS Keychain on first connect
```

### 6. Start Samba and enable on boot

```bash
rc-update add samba
rc-service samba start
```

### 7. Add Pi-hole DNS entry

In Pi-hole local DNS: `share.atlas.local → 192.168.20.13`

### 8. Enable container protection

```bash
pct set <vmid> -protection 1
```

### 9. Connect from macOS

Finder → Go → Connect to Server (`⌘K`): `smb://share.atlas.local/share`

---

## Management

```bash
# SSH into the LXC via Proxmox host
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100
pct exec <vmid> -- rc-service samba status

# Check connected clients
pct exec <vmid> -- smbstatus

# ZFS snapshot of share data (run on Proxmox host)
zfs snapshot WD_SATA_1TB/share@$(date +%Y%m%d)

# List snapshots
zfs list -t snapshot -r WD_SATA_1TB/share
```

## Why Not NFS?

NFS is better suited for Linux-to-Linux (e.g., Kubernetes nodes mounting storage). macOS supports NFS but SMB is the native protocol — it integrates with Finder, Keychain, and Spotlight indexing without any extra configuration.
