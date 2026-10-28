# ─── Control Plane ────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "control_plane" {
  name      = "talos-cp"
  node_name = var.proxmox_node
  vm_id     = 200
  started   = true
  tags      = ["kubernetes", "vm"]

  # UEFI (OVMF) — consistent with other VMs on this host
  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id      = var.disk_storage
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = var.control_plane_cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.control_plane_memory
  }

  # Boot disk
  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.control_plane_disk_size
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  # Talos installation ISO — attached as CDROM on ide2
  # UEFI will boot from disk after Talos installs itself and sets an EFI entry
  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    vlan_id     = var.vlan_id
    mac_address = "BC:24:11:00:02:00"
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  # Start after Pi-hole (LXC 102, order=1) so DNS is up before the cluster
  startup {
    order    = 3
    up_delay = 60
  }

  # After Talos installs, UEFI boots from disk via EFI entry — no need to eject ISO
  lifecycle {
    ignore_changes = [
      cdrom,
      boot_order,
    ]
  }
}

# ─── Workers ──────────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.workers

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = each.value.vmid
  started   = true
  tags      = ["kubernetes", "vm"]

  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id      = var.disk_storage
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = var.worker_cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.worker_disk_size
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id
    # MAC is derived from VMID offset from 200 (CP=200 → :00, worker-01=201 → :01, etc.)
    # Assumes VMIDs 201–254 for workers; collisions occur if other VMs use IDs in that range.
    mac_address = format("BC:24:11:00:02:%02X", each.value.vmid - 200)
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  # Start after the control plane
  startup {
    order = 4
  }

  lifecycle {
    ignore_changes = [
      cdrom,
      boot_order,
    ]
  }
}
