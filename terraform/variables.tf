# ─── Proxmox ──────────────────────────────────────────────────────────────────

variable "proxmox_endpoint" {
  description = "Proxmox VE API URL (e.g. https://192.168.0.100:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the format user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
  default     = "proxmox"
}

# ─── Storage & Networking ─────────────────────────────────────────────────────

variable "disk_storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "CRUCIAL_SSD_512GB"
}

variable "iso_storage" {
  description = "Proxmox storage pool for ISO files"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for cluster node NICs"
  type        = number
  default     = 20
}

# ─── Talos & Cluster ──────────────────────────────────────────────────────────

variable "talos_version" {
  description = "Talos Linux version — should match your talosctl client version"
  type        = string
  default     = "v1.12.6"
}

variable "talos_schematic_id" {
  description = <<-EOT
    Talos Image Factory schematic ID. Generated at https://factory.talos.dev.
    Current schematic: amd64, no SecureBoot, qemu-guest-agent extension.
  EOT
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "atlas"
}

# ─── Network (VLAN 20) ────────────────────────────────────────────────────────

variable "subnet_prefix" {
  description = "Subnet prefix length for VLAN 20"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for cluster nodes"
  type        = string
  default     = "192.168.20.1"
}

variable "dns_server" {
  description = "DNS server IP (atlas-pihole)"
  type        = string
  default     = "192.168.0.101"
}

variable "dns_fallback_server" {
  description = "Fallback DNS server used if Pi-hole is down (internet names only; no atlas.local records)"
  type        = string
  default     = "1.1.1.1"
}

variable "control_plane_ip" {
  description = "Static IP for the control plane node"
  type        = string
  default     = "192.168.20.10"
}

variable "worker_ips" {
  description = "List of static IPs for worker nodes, one per worker"
  type        = list(string)
  default     = ["192.168.20.11"]
}

# ─── VM Sizing ────────────────────────────────────────────────────────────────

variable "control_plane_cpu" {
  description = "Number of vCPUs for the control plane VM"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "RAM in MB for the control plane VM"
  type        = number
  default     = 4096
}

variable "control_plane_disk_size" {
  description = "Disk size in GB for the control plane VM"
  type        = number
  default     = 20
}

variable "worker_cpu" {
  description = "Number of vCPUs per worker VM"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "RAM in MB per worker VM"
  type        = number
  default     = 6144
}

variable "worker_disk_size" {
  description = "Disk size in GB per worker VM"
  type        = number
  default     = 75
}
