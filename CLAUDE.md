# Claude Code Configuration

## Allowed Commands

The following commands are pre-approved and do not require classifier review:

- `curl *192.168.0.1*` — UniFi controller API (local network only)
- `curl *192.168.0.100*` — Proxmox API (local network only)
- `curl *app.terraform.io*` — Terraform Cloud API
- `ssh *192.168.0.100*` — Proxmox SSH access
- `ssh *proxmox-claude*` — Proxmox SSH via Claude key

## Credentials

All credentials are sourced from local files — never hardcoded or echoed:

- `~/.unifi-credentials` — UniFi controller (UNIFI_URL, UNIFI_USER, UNIFI_PASSWORD)
- `~/.proxmox-credentials` — Proxmox credentials: `PROXMOX_URL`, `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET` (terraform@pve API token for VM/API operations), `PROXMOX_SSH_KEY`, `PROXMOX_SSH_USER` (root SSH for shell access)
- `~/.terraform.d/credentials.tfrc.json` — Terraform Cloud API token (org: ACLABORG, workspace: atlas-talos)

## Services on the Proxmox host

- Pi-hole (LXC 102) — managed from the Proxmox host with `pct exec 102 -- <command>` (e.g. `pihole-FTL --config dns.hosts` for local DNS records). No separate Pi-hole credentials.
