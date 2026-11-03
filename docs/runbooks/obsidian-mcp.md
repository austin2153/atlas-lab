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
| CPU / RAM / disk | 1 core / 1 GB / 8 GB on `CRUCIAL_SSD_512GB` |
| Network | `vmbr0`, VLAN `20`, static `192.168.20.16/24`, gateway `192.168.20.1`, DNS `192.168.0.101` |

On the Proxmox host, run the community Debian script and choose **Advanced**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/debian.sh)"
```

Change RAM to **1024** and disk to **8** (the defaults are 512 MB / 2 GB), and set the CT ID and network from the table. Other prompts:

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
