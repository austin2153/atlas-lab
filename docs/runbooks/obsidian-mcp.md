# Obsidian MCP Server

A self-hosted server that lets Claude read and write my Obsidian notes from any Claude app (Mac, phone, web and voice), without a manual "sync it" step.

**MCP (Model Context Protocol)** is an open standard for connecting AI apps like Claude to outside tools and data. An MCP server publishes tools (for example "search notes" or "write note") that Claude can call. Here, [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp) is the MCP server, and Claude connects to it as a custom connector.

**What gets built**, all on the existing Proxmox host:
- **MCP container:** runs obsidian-web-mcp and Syncthing, and holds the lab copy of the vault.
- **cloudflared container:** holds an outbound Cloudflare tunnel, so Claude can reach the server at `notes.atlaslab.dev` without opening any ports at home.
- **Syncthing:** keeps the lab copy and the Mac's copy of the vault in sync.

## MCP container

> **Built 2026-11-02.**

| Setting | Value |
|---|---|
| CT ID / hostname | `103` / `obsidian-mcp` (`obsidian-mcp.atlas.local`) |
| OS / type | Debian 13, unprivileged |
| CPU / RAM / disk | 1 core / 2 GB / 8 GB on `CRUCIAL_SSD_512GB` |
| Network | `vmbr0`, VLAN `20`, static `192.168.20.16/24`, gateway `192.168.20.1`, DNS `192.168.0.101` |

On the Proxmox host, run the community Debian script and choose **Advanced**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/debian.sh)"
```

Change RAM to **2048** and disk to **8** (the defaults are 512 MB / 2 GB; 1 GB ran out of memory with VS Code Remote-SSH connected), and set the CT ID and network from the table. Other prompts:

| Prompt | Answer |
|---|---|
| SSH key source | `found` → the Mac key and `claude-code-proxmox` |
| FUSE / TUN/TAP / GPU passthrough | No |
| Nesting | Yes (systemd on Debian 13 needs it) |
| Mount filesystems / post-install hook | Leave empty |

### SSH from the Mac

Add to `~/.ssh/config`, then `ssh obsidian-mcp`:

```
Host obsidian-mcp
    HostName 192.168.20.16
    User root
    IdentityFile ~/.ssh/id_ed25519
    SetEnv TERM=xterm-256color
```

## cloudflared container

> **Built 2026-11-03.**

| Setting | Value |
|---|---|
| CT ID / hostname | `104` / `cloudflared` (`cloudflared.atlas.local`) |
| OS / type | Debian 13, unprivileged |
| CPU / RAM / disk | 1 core / 512 MB / 4 GB on `CRUCIAL_SSD_512GB` |
| Network | `vmbr0`, VLAN `20`, static `192.168.20.17/24`, gateway `192.168.20.1`, DNS `192.168.0.101` |

On the Proxmox host, run the community cloudflared script and choose **Advanced**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/cloudflared.sh)"
```

Change disk to **4** (the default is 2 GB), and set the CT ID and network from the table. Other prompts:

| Prompt | Answer |
|---|---|
| SSH key source | `found` → the Mac key and `claude-code-proxmox` |
| FUSE / TUN/TAP / GPU passthrough | No |
| Nesting | Yes |
| Mount filesystems / post-install hook | Leave empty |

Don't configure the tunnel yet; that comes after the domain exists.

### SSH from the Mac

Add to `~/.ssh/config`, then `ssh cloudflared`:

```
Host cloudflared
    HostName 192.168.20.17
    User root
    IdentityFile ~/.ssh/id_ed25519
    SetEnv TERM=xterm-256color
```

## App repo

| | |
|---|---|
| Upstream | https://github.com/jimprosser/obsidian-web-mcp |
| Fork | https://github.com/austin2153/obsidian-web-mcp |
| Clone on the server | `obsidian-mcp:/opt/obsidian-web-mcp` |
| Working branch | `atlas` (customizations; `main` tracks upstream) |

> **Forked and cloned 2026-11-03.** Git 2.47.3 (Debian's repo) on `obsidian-mcp`.

Order: **fork → clone → review**. The review happens in the clone (in VS Code over Remote-SSH), before anything is installed or run.

```bash
# On the Mac: fork into my GitHub account
gh repo fork jimprosser/obsidian-web-mcp --clone=false

# On obsidian-mcp: clone the fork
git clone https://github.com/austin2153/obsidian-web-mcp.git /opt/obsidian-web-mcp
```

To pull upstream changes later: **Sync fork** on GitHub, then `git -C /opt/obsidian-web-mcp pull` on the server.

## Configuration

All settings are environment variables, kept in a root-only env file on `obsidian-mcp`: `/etc/obsidian-web-mcp.env` (`chmod 600`). The password and token also go in Bitwarden.

| Setting | Value |
|---|---|
| `VAULT_PATH` | `/srv/vault` |
| `VAULT_OAUTH_USERNAME` | (choose) |
| `VAULT_OAUTH_PASSWORD` | Long random password from Bitwarden |
| `VAULT_MCP_TOKEN` | `python3 -c "import secrets; print(secrets.token_hex(32))"` |
| `VAULT_MCP_HOST` | `192.168.20.16` (default `127.0.0.1` only works when cloudflared is on the same machine) |
| `VAULT_MCP_PORT` | `8420` (default) |
| `VAULT_MCP_FORWARDED_ALLOW_IPS` | `192.168.20.17` (cloudflared) |
| `VAULT_MCP_PUBLIC_URL` | `https://notes.atlaslab.dev` |
| `VAULT_MCP_ALLOWED_HOSTS` | `notes.atlaslab.dev` |

Connector URL in Claude: `https://notes.atlaslab.dev` (the server serves MCP at `/`).

## Setup

1. Review the code (auth, path handling, deletes)
2. Install `uv` and the app's dependencies
3. Create `/srv/vault` and the env file
4. Syncthing: get the new vault from the Mac into `/srv/vault`
5. systemd service so the app starts on boot
6. Firewall: port 8420 only from `192.168.20.17`
7. Domain and tunnel: `notes.atlaslab.dev` → `http://192.168.20.16:8420`
8. Add the connector in Claude and test (Mac, phone, voice)
