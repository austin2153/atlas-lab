# Proxmox VE

Everything about the Proxmox host in one place: what's on it, how to reach it, how to rebuild it from scratch, how to keep it updated, and what went wrong before.

The lab runs on a single Proxmox node, `proxmox` (`192.168.0.100`), on Proxmox VE 9.2 / Debian 13 (Trixie). The planned move to a Lenovo M920q Tiny is covered in [lab-infrastructure.md](../lab-infrastructure.md).

> **Planned network change (with the M920q, not done yet):** the host moves to the lab VLAN at `192.168.20.5` with nothing tagged, and Pi-hole moves to `192.168.20.3`. Everything in this doc describes the current host; update it, including the rebuild runbook, as part of that migration. See the network cutover checklist in [lab-infrastructure.md](../lab-infrastructure.md).

## Overview

### Hardware (current host)

| Component | Details |
|---|---|
| Server | Desktop PC, Gigabyte Z97MX-Gaming 5, Intel i7-4790K, 24 GB RAM |
| OS drive | PNY CS900 250 GB 2.5" SATA SSD (`rpool`, ZFS) |
| Guest storage | Crucial CT512MX100SSD1 512 GB SATA SSD (`CRUCIAL_SSD_512GB` ZFS pool) |
| Hostname | `proxmox.atlas.local` |

> The BIOS only enables 2 of the 6 SATA ports (ports 1 and 5). A drive plugged into any other port is invisible to the OS until it's enabled under Peripherals → SATA And RST Configuration.

### Network

| Parameter | Value |
|---|---|
| Proxmox IP | `192.168.0.100` (VLAN 1, untagged) |
| Bridge | `vmbr0`, VLAN-aware |
| Lab VLAN | Guests on `192.168.20.0/24` are tagged VLAN 20 on the bridge |
| Gateway | `192.168.0.1` (UniFi Cloud Gateway Ultra) |
| DNS | `192.168.0.101` (atlas-pihole), fallback `1.1.1.1` |
| Switch port | USW-Lite-8-PoE port 6 |

### Guests

| VMID | Name | Type | IP | Boot order | Purpose |
|---|---|---|---|---|---|
| 102 | `atlas-pihole` | LXC | `192.168.0.101` | 1 (up=15) | Pi-hole DNS for the house and lab |
| 200 | `talos-cp` | VM | `192.168.20.10` | 3 (up=60) | Talos Kubernetes control plane |
| 201 | `talos-worker-01` | VM | `192.168.20.11` | 4 | Talos Kubernetes worker |

All guests have `onboot: 1`. The `startup:` order brings DNS up first, then the control plane with a 60-second head start, then the worker. Shutdown runs in reverse.

## Access

### API token

The Proxmox API token is stored locally at `~/.proxmox-credentials` (not committed to git) as a single value, `user@realm!tokenid=secret`:

```bash
chmod 600 ~/.proxmox-credentials
PROXMOX_TOKEN=$(cat ~/.proxmox-credentials)

# List nodes
curl -sk "https://192.168.0.100:8006/api2/json/nodes" \
  -H "Authorization: PVEAPIToken=$PROXMOX_TOKEN" | python3 -m json.tool

# List VMs on the node
curl -sk "https://192.168.0.100:8006/api2/json/nodes/proxmox/qemu" \
  -H "Authorization: PVEAPIToken=$PROXMOX_TOKEN" | python3 -m json.tool
```

The token doesn't survive a reinstall. Terraform reads its own copy from `terraform/terraform.tfvars`, so update both after creating a new one (see [step 11](#11-restore-the-proxmox-api-token)).

### SSH

For things the API can't do (community LXC install scripts, `pct` commands), Claude connects as root with a dedicated key, separate from the API token so each can be revoked on its own:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/proxmox-claude -N "" -C "claude-code-proxmox"
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100
```

The public key (`~/.ssh/proxmox-claude.pub`) goes in `root`'s `~/.ssh/authorized_keys` on the host. Containers are managed from the host with `pct` (`pct list`, `pct exec <vmid> -- <command>`).

### Notes

- TLS verification is disabled (`-sk`) because the certificate is self-signed.
- Always source credentials from their files; never hardcode or echo secrets.
- Per-container root passwords live in their own files, e.g. `~/.proxmox-<name>-credentials`.

## Rebuilding from scratch

### Create the installer USB (Mac)

1. Download the latest Proxmox VE ISO from `https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso`.
2. Find the USB stick with `diskutil list` (for example `/dev/disk4`).
3. Unmount and flash it. Use `rdisk4` (with the `r`) for faster writes; it takes about 5 minutes.
   ```bash
   diskutil unmountDisk /dev/disk4
   sudo dd if=/path/to/proxmox-ve_9.x-x.iso of=/dev/rdisk4 bs=4m status=progress
   ```

### Installer settings

Boot the server from the USB stick (you may need to change the boot order in the BIOS).

| Setting | Value |
|---|---|
| Target disk | PNY CS900 250 GB only. Don't select any other drive |
| Filesystem | **ZFS**. ext4 fails with an initramfs error on this hardware; use "Graphical, nomodeset" → ZFS |
| Country / timezone | United States / America/Detroit |
| Hostname | `proxmox.atlas.local` |
| IP / gateway | `192.168.0.100/24` / `192.168.0.1` |
| DNS | `192.168.0.101` (atlas-pihole). Use `1.1.1.1` temporarily if Pi-hole is down |

The installer only touches the selected disk, so `CRUCIAL_SSD_512GB` and the guest data on it survive. Remove the USB stick and reboot when it finishes.

### Post-install steps

#### 1. Restore Claude's SSH access (from the Mac)

The host key changes with a reinstall, so clear the old one first:

```bash
ssh-keygen -R 192.168.0.100
ssh-copy-id -i ~/.ssh/proxmox-claude.pub -o StrictHostKeyChecking=accept-new root@192.168.0.100
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 "echo connected"
```

#### 2. Check the non-free-firmware apt sources

PVE 9 uses deb822 `.sources` files; there is no `/etc/apt/sources.list`. The installer's `debian.sources` should already include `non-free-firmware`:

```bash
grep Components /etc/apt/sources.list.d/debian.sources
# Components: main contrib non-free-firmware
```

If it's missing, add `non-free-firmware` to both `Components:` lines.

#### 3. Switch from the enterprise repos to no-subscription

A fresh install enables the Proxmox **enterprise** repos, which need a paid subscription. Without one, `apt-get update` fails with `401 Unauthorized` and every update task in the UI shows `TASK ERROR: command 'apt-get update' failed: exit code 100`.

Disable the enterprise repos (`Enabled: no` keeps the files, so it's easy to revert) and add the free ones:

```bash
cd /etc/apt/sources.list.d
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

apt-get update   # must finish with no errors
```

The "No valid subscription" popup at UI login is cosmetic and unrelated.

#### 4. Update packages and install intel-microcode

Use `dist-upgrade` (not `upgrade`) so new kernel and PVE packages are pulled in:

```bash
apt-get update && apt-get dist-upgrade -y
apt-get install intel-microcode -y
reboot
```

#### 5. Import the guest ZFS pool

The pool is on disk but not imported yet. It was last used by a different install (different hostid), so force it:

```bash
zpool import -f CRUCIAL_SSD_512GB
zpool status
```

#### 6. Register the pool as Proxmox storage

A fresh install only has `local` and `local-zfs`:

```bash
pvesm add zfspool CRUCIAL_SSD_512GB --pool CRUCIAL_SSD_512GB --content images,rootdir --sparse
pvesm status
```

#### 7. Recreate the VM and container configs

A reinstall loses `/etc/pve/nodes/proxmox/lxc/` and `/etc/pve/nodes/proxmox/qemu-server/`; only the ZFS data survives. `zfs list -r CRUCIAL_SSD_512GB` shows what exists (`subvol-<vmid>-disk-0` for containers, `vm-<vmid>-disk-*` for VMs).

`/etc/pve/nodes/proxmox/lxc/102.conf`:
```
arch: amd64
cores: 1
features: nesting=1
hostname: atlas-pihole
memory: 512
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:00:00:02,ip=192.168.0.101/24,gw=192.168.0.1,type=veth
onboot: 1
startup: order=1,up=15
ostype: debian
rootfs: CRUCIAL_SSD_512GB:subvol-102-disk-0,size=8G
swap: 512
unprivileged: 1
```

`/etc/pve/nodes/proxmox/qemu-server/200.conf`:
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
startup: order=3,up=60
```

`/etc/pve/nodes/proxmox/qemu-server/201.conf`:
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
startup: order=4
```

> Don't use `pre-enrolled-keys=1` on the EFI disk of the Talos VMs: Microsoft Secure Boot keys will stop Talos from booting.

#### 8. Start Pi-hole

Pi-hole comes up first, because everything else depends on DNS:

```bash
pct start 102
pct exec 102 -- systemctl is-active pihole-FTL   # should print "active"
```

#### 9. Point the host at Pi-hole, with Cloudflare as fallback

```bash
pvesh set /nodes/proxmox/dns --search atlas.local --dns1 192.168.0.101 --dns2 1.1.1.1
```

Containers that don't set their own nameserver inherit this when they start.

#### 10. Start the Kubernetes VMs

```bash
qm start 200    # talos-cp
qm start 201    # talos-worker-01
```

Wait about 2 minutes for Talos to boot, then check:

```bash
TALOSCONFIG=~/.talos/atlas-lab.talosconfig talosctl --nodes 192.168.20.10 health --server=false
kubectl get nodes
```

If the nodes come up `NotReady,SchedulingDisabled`, they were cordoned on the last clean shutdown:

```bash
kubectl uncordon talos-cp talos-worker-01
```

#### 11. Restore the Proxmox API token

The token is tied to the install. Create a new one:

- Proxmox UI → Datacenter → Permissions → API Tokens → Add
- User `root@pam`, Token ID `terraform` (or whatever was used before), untick "Privilege Separation"
- Save it to `~/.proxmox-credentials` on the Mac (`chmod 600`) and to `proxmox_api_token` in `terraform/terraform.tfvars`

## Maintenance

### Updates

```bash
apt-get update
apt list --upgradable
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
```

- A kernel or `pve-manager` update needs a reboot. Rebooting takes down house DNS (Pi-hole) and the cluster for a few minutes. Guests stop and start in boot order on their own.
- Run long upgrades detached so a dropped SSH session can't interrupt `dpkg`:
  ```bash
  systemd-run --unit=pve-upgrade --collect bash -c "apt-get -y dist-upgrade > /root/upgrade.log 2>&1"
  ```
- After a reboot, confirm `uname -r` shows the new kernel and `systemctl --failed` is empty.

### Removing old kernels

`apt autoremove` does **not** remove old Proxmox kernels, because they aren't marked as automatic. Once the new kernel has run cleanly for a few days, remove the old one by name:

```bash
dpkg -l 'proxmox-kernel-*' | awk '/^ii/{print $2, $3}'
apt-get -s purge proxmox-kernel-<old-version>-pve-signed   # dry run first
apt-get -y purge proxmox-kernel-<old-version>-pve-signed
proxmox-boot-tool kernel list
```

The host boots through UEFI with `proxmox-boot-tool`, not GRUB. The `grub-probe: error: unknown filesystem` lines printed during kernel removal come from a GRUB hook that can't read the ZFS root, and are harmless.

## History

### AWX removed (24 Oct 2026)

AWX was removed ahead of the move to Red Hat Ansible Automation Platform: the `platform/awx` app came out of the cluster and the `awx-postgres` container (CT 105, `192.168.20.12`) was destroyed. Backups are in `/root/awx-backup-20261024/` on the host: a `pg_dump` of the database (`awx-db.dump`), the cluster secrets needed to read it (`k8s-secrets.yaml`, including the AWX secret key), the AWX instance spec, and a full ZFS copy of the container (`ct105-rootfs.zfs.zst` plus `105.conf`). The same day, vcsim was scaled down to two simulators.

### Repo fix and update to 9.2.21 (23 Oct 2026)

Update tasks in the UI were failing with `apt-get update ... exit code 100`: the reinstall had re-enabled the enterprise repos (see [step 3](#3-switch-from-the-enterprise-repos-to-no-subscription)). After switching repos, 184 packages were upgraded (pve-manager 9.2.2 → 9.2.21, kernel 7.0.2 → 7.0.14) and the host was rebooted. The old 7.0.2 kernel was removed on 24 Oct.

### PVE 8 → 9 upgrade and OS drive failure (Oct 2026)

The upgrade from Proxmox VE 8.4.19 (Debian 12) to 9.x (Debian 13) followed the official guide (`https://pve.proxmox.com/wiki/Upgrade_from_8_to_9`). Before it, `pve8to9` flagged these, all resolved:

| Issue | Fix |
|---|---|
| Second node `proxmox-cgrater` offline, cluster not quorate, guests couldn't start | `pvecm expected 1`, then `pvecm delnode proxmox-cgrater`. The `CS_ERR_NOT_EXIST` error is harmless |
| `systemd-boot` meta-package installed (FAIL) | `apt-get remove systemd-boot systemd-boot-efi -y` |
| `grub-efi-amd64` missing (WARN) | Set `grub2/force_efi_extra_removable` to true with `debconf-set-selections`, then install and reinstall `grub-efi-amd64` |
| `intel-microcode` missing (WARN) | Enable `non-free-firmware`, then `apt-get install intel-microcode` |

**During the dist-upgrade, the old OS drive failed.** It was a Samsung 840 Pro 256 GB with about 102,000 power-on hours. It threw `ICRC ABRT` errors, the root filesystem went read-only, the SATA link dropped to 1.5 Gb/s, and SMART showed 148 CRC errors even though its overall status said PASSED. Reseating the cable only helped for minutes.

The guest data on the ZFS pool was unaffected. The fix was a fresh PVE 9 install on a new PNY CS900 250 GB drive, followed by the [rebuild steps](#rebuilding-from-scratch) above.
