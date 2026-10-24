# ─── Secrets ──────────────────────────────────────────────────────────────────
# Generates the cluster PKI, tokens, and encryption keys.
# Stored in Terraform state (sensitive). Never committed to git.

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# ─── Machine Configurations ───────────────────────────────────────────────────
# Renders the YAML machine config for each node type.
# Static IP, gateway, DNS, and hostname are injected via config patches.

data "talos_machine_configuration" "control_plane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.control_plane_ip}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = "talos-cp"
      auto       = "off"
    }),
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = {
              driver = "virtio_net"
            }
            dhcp      = false
            addresses = ["${var.control_plane_ip}/${var.subnet_prefix}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.gateway
            }]
          }]
          nameservers = [var.dns_server, var.dns_fallback_server]
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  for_each = local.workers

  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${var.control_plane_ip}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    }),
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = {
              driver = "virtio_net"
            }
            dhcp      = false
            addresses = [each.value.cidr]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.gateway
            }]
          }]
          nameservers = [var.dns_server, var.dns_fallback_server]
        }
      }
    })
  ]
}

# ─── Apply Configs ────────────────────────────────────────────────────────────
# Pushes machine configs to each node via the Talos API.
# Talos installs itself to disk and reboots. The provider retries until ready.

resource "talos_machine_configuration_apply" "control_plane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                        = var.control_plane_ip

  depends_on = [proxmox_virtual_environment_vm.control_plane]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.workers

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = each.value.ip

  depends_on = [proxmox_virtual_environment_vm.worker]
}

# ─── Bootstrap ────────────────────────────────────────────────────────────────
# Bootstraps etcd on the control plane — only runs once.

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ip

  depends_on = [talos_machine_configuration_apply.control_plane]
}

# ─── Client Configuration ─────────────────────────────────────────────────────
# Generates the talosconfig file for use with talosctl.

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [var.control_plane_ip]
  endpoints            = [var.control_plane_ip]
}

# ─── Kubeconfig ───────────────────────────────────────────────────────────────
# Retrieves the kubeconfig once the cluster is bootstrapped and healthy.

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ip

  depends_on = [talos_machine_bootstrap.this]
}
