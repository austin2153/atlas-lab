# Claude Code Configuration

## Allowed Commands

The following commands are pre-approved and do not require classifier review:

- `curl *192.168.0.1*` — UniFi controller API (local network only)
- `curl *192.168.0.100*` — Proxmox API (local network only)
- `ssh *192.168.0.100*` — Proxmox SSH access
- `ssh *proxmox-claude*` — Proxmox SSH via Claude key

## Credentials

All credentials are sourced from local files — never hardcoded or echoed:

- `~/.unifi-credentials` — UniFi controller (UNIFI_URL, UNIFI_USER, UNIFI_PASSWORD)
- `~/.proxmox-credentials` — Proxmox API token
- `~/.ssh/proxmox-claude` — SSH key for Proxmox root access

## Services on the Proxmox host

- Pi-hole (LXC 102) — managed from the Proxmox host with `pct exec 102 -- <command>` (e.g. `pihole-FTL --config dns.hosts` for local DNS records). No separate Pi-hole credentials.
