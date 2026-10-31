terraform {
  # Terraform Cloud backend — state (.tfstate) is stored remotely under org ACLABORG,
  # workspace atlas-lab. Workspace is set to Local execution mode: Terraform runs locally
  # but state lives in TF Cloud, so you get remote state without handing
  # TF Cloud your Proxmox credentials.
  cloud {
    organization = "ACLABORG"
    workspaces {
      name = "atlas-lab"
    }
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.102"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  # Self-signed TLS cert on homelab Proxmox — disable verification
  insecure = true
}
