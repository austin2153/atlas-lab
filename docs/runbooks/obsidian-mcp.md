# Obsidian MCP Server

A self-hosted server that lets Claude read and write my Obsidian notes from any Claude app (Mac, phone, web and voice).
**MCP (Model Context Protocol)** is an open standard for connecting AI apps like Claude to outside tools and data. An MCP server publishes tools (for example "search notes" or "write note") that Claude can call. Here, [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp) is the MCP server, and Claude connects to it as a custom connector.

**What gets built**, all on the existing Proxmox host:
- **MCP container:** runs obsidian-web-mcp and Syncthing, and holds the lab copy of the vault.
- **cloudflared container:** holds an outbound Cloudflare tunnel, so Claude can reach the server at `notes.atlaskeep.dev` without opening any ports at home.
- **Syncthing:** keeps the lab copy and the Mac's copy of the vault in sync.

## References

| What | Link |
|---|---|
| App (upstream) | https://github.com/jimprosser/obsidian-web-mcp |
| App (my fork) | https://github.com/austin2153/obsidian-web-mcp |
| App README: Configuration / Quick Start | [Configuration](https://github.com/austin2153/obsidian-web-mcp#configuration), [Quick Start](https://github.com/austin2153/obsidian-web-mcp#quick-start) |
| Claude custom connectors (remote MCP) | [Help center](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp), [Docs](https://claude.com/docs/connectors/custom/remote-mcp) |
| MCP specification | https://modelcontextprotocol.io |
| uv | https://docs.astral.sh/uv/ |
| Syncthing | [Docs](https://docs.syncthing.net), [APT repo](https://apt.syncthing.net) |
| Cloudflare Tunnel | https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ |
| cloudflared | https://github.com/cloudflare/cloudflared |
| Proxmox community scripts | [Debian](https://community-scripts.org/scripts/debian), [cloudflared](https://community-scripts.org/scripts/cloudflared) |

## Checklist

- [x] [MCP container](#mcp-container) (LXC 103, `obsidian-mcp`)
- [x] [cloudflared container](#cloudflared-container) (LXC 104, `cloudflared`)
- [x] [Fork and clone the app repo](#app-repo), `atlas` branch
- [x] [Install uv and dependencies](#install-uv-and-dependencies)
- [x] [Vault folder, env file and test run](#vault-folder-env-file-and-test-run) (settings in [Configuration](#configuration))
- [x] New vault on the Mac (`~/vaults/notes`) + [Syncthing](#syncthing)
- [x] [systemd service](#systemd-service)
- [x] [Firewall](#firewall) (CT 103 only; logging on while testing)
- [x] [Domain](#domain) (`atlaskeep.dev`)
- [x] [Cloudflare tunnel](#cloudflare-tunnel)
- [ ] Connect Claude and test (Mac, phone, voice)
- [ ] Make it the main vault
- [ ] Phone: Syncthing-Fork (F-Droid) + Obsidian on the Moto G

## MCP container

> **Built 2026-11-02.**

| Setting | Value |
|---|---|
| CT ID / hostname | `103` / `obsidian-mcp` (`obsidian-mcp.atlas.local`) |
| OS / type | Debian 13, unprivileged |
| CPU / RAM / disk | 1 core / 2 GB / 8 GB on `CRUCIAL_SSD_512GB` |
| Network | `vmbr0`, VLAN `20`, static `192.168.20.16/24`, gateway `192.168.20.1`, DNS `192.168.0.101` |
| Timezone | `America/New_York`, set 2026-11-04 with `timedatectl set-timezone` (built with the Proxmox host's wrong `America/Adak`; the host is fixed too) |

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
| Timezone | `America/New_York`, set 2026-11-04 with `timedatectl set-timezone` (built with the Proxmox host's wrong `America/Adak`; the host is fixed too) |

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

```bash
# On the Mac: fork into my GitHub account
gh repo fork jimprosser/obsidian-web-mcp --clone=false

# On obsidian-mcp: clone the fork
git clone https://github.com/austin2153/obsidian-web-mcp.git /opt/obsidian-web-mcp
```

To pull upstream changes later: **Sync fork** on GitHub, then `git -C /opt/obsidian-web-mcp pull` on the server.

## Configuration

All settings are environment variables, kept in a root-only env file on `obsidian-mcp`: `/etc/obsidian-web-mcp.env` (`chmod 600`). The password and token also go in Bitwarden.

Reference: [README → Configuration](https://github.com/austin2153/obsidian-web-mcp#configuration) and [Quick Start](https://github.com/austin2153/obsidian-web-mcp#quick-start). **Source** says whether a value comes from the README or is our choice for this deployment.

| Setting | Value | Source |
|---|---|---|
| `VAULT_PATH` | `/srv/vault` | README: required. Path is our choice |
| `VAULT_OAUTH_USERNAME` | `austin` | README: default `obsidian`. Ours |
| `VAULT_OAUTH_PASSWORD` | 32 letters/digits from Bitwarden | README: required, server refuses all logins without it. README generates one with `secrets.token_urlsafe(24)`; we used Bitwarden |
| `VAULT_MCP_TOKEN` | `python3 -c "import secrets; print(secrets.token_hex(32))"` | README Quick Start method (256-bit hex). Format isn't enforced |
| `VAULT_MCP_HOST` | `192.168.20.16` | README: default `127.0.0.1`, which assumes cloudflared on the same machine. Ours, because cloudflared is a separate container |
| `VAULT_MCP_PORT` | `8420` | README default |
| `VAULT_MCP_FORWARDED_ALLOW_IPS` | `192.168.20.17` | README: default `127.0.0.1`, "never set this to `*`". Ours: cloudflared's IP |
| `VAULT_MCP_PUBLIC_URL` | `https://notes.atlaskeep.dev` | README: recommended for any reverse-proxy deployment |
| `VAULT_MCP_ALLOWED_HOSTS` | `notes.atlaskeep.dev` | README: set to the tunnel hostname for any remote deployment |

Connector URL in Claude: `https://notes.atlaskeep.dev`. README: MCP is served at `/`, and clients connect to the base URL.

## Setup

| | Task | Status |
|---|---|---|
| 1 | Install `uv` and the app's dependencies | Done 2026-11-03 |
| 2 | Create `/srv/vault` and the env file, test run | Done 2026-11-03 |
| 3 | Syncthing: get the new vault from the Mac into `/srv/vault` | Done 2026-11-04 |
| 4 | systemd service so the app starts on boot | Done 2026-11-04 |
| 5 | Firewall: port 8420 only from `192.168.20.17` | Done 2026-11-05 |
| 6 | Domain and tunnel: `notes.atlaskeep.dev` → `http://192.168.20.16:8420` | Done 2026-11-05 |
| 7 | Add the connector in Claude and test (Mac, phone, voice) | Next |

### Install uv and dependencies

README → Prerequisites: Python 3.12+ and [uv](https://docs.astral.sh/uv/) (recommended). The install command is from uv's own docs.

On `obsidian-mcp`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

cd /opt/obsidian-web-mcp
uv sync --python 3.13
```

- uv 0.13.7, installed to `/root/.local/bin`.
- **Deviation from the README:** `--python 3.13` uses Debian's Python. The repo's `.python-version` asks for 3.14, which uv would otherwise download; `pyproject.toml` only needs 3.12+.
- **Deviation from the README:** the README runs the app with `uv run vault-mcp`. We run `.venv/bin/vault-mcp` so uv doesn't switch to 3.14.
- Upstream has no `uv.lock`, so dependency versions aren't pinned. Installed: obsidian-web-mcp 0.4.0, mcp 1.30.0, pydantic 2.14.2.

### Vault folder, env file and test run

```bash
mkdir -p /srv/vault          # plus a throwaway _index.md and "Test note.md"
touch /etc/obsidian-web-mcp.env
chmod 600 /etc/obsidian-web-mcp.env
vi /etc/obsidian-web-mcp.env # settings from the Configuration table
```

- Password and token were generated as described in Configuration, saved in Bitwarden, then pasted into the file.
- Debian's `vi` is vim-tiny: arrow keys in Insert mode type letters, and it doesn't show `-- INSERT --`. Install `vim` for normal behaviour.

Test run (foreground, then Ctrl+C). The README's Quick Start uses `export` and `uv run vault-mcp`; this loads the env file instead:

```bash
cd /opt/obsidian-web-mcp
set -a; . /etc/obsidian-web-mcp.env; set +a
.venv/bin/vault-mcp
```

From a second terminal:

```bash
curl http://192.168.20.16:8420/health   # {"status":"ok","audit":{"enabled":false}}
curl http://192.168.20.16:8420/         # {"error":"Missing or malformed Authorization header"}
```

Close the test shell afterwards; `set -a` leaves the secrets in its environment.


## Syncthing

[Syncthing](https://syncthing.net) is open-source, peer-to-peer file sync. Devices sync a shared folder directly with each other; there's no cloud service holding the files, and every device keeps a full local copy that works offline.

Here it keeps the vault in sync between the Mac and `obsidian-mcp:/srv/vault`, so notes Claude writes on the server show up in Obsidian on the Mac, and edits on the Mac reach the server.

- Devices pair by exchanging **device IDs**, and all traffic is encrypted.
- At home, the two sync directly over the LAN. Away from home, Syncthing's public discovery and relay servers help them find each other; relays only see encrypted traffic.
- Ports: **22000** (sync, TCP/UDP), **21027** (local discovery, UDP), **8384** (web UI).

References:
- [Syncthing docs](https://docs.syncthing.net) and [getting started](https://docs.syncthing.net/intro/getting-started.html)
- [Official APT repository](https://apt.syncthing.net) (install instructions used below)
- [Firewall and ports](https://docs.syncthing.net/users/firewall.html)
- [Running as a service with systemd](https://docs.syncthing.net/users/autostart.html#linux)
- [Ignoring files (`.stignore`)](https://docs.syncthing.net/users/ignoring.html) and [file versioning](https://docs.syncthing.net/users/versioning.html)
- Phone: the official Android app was [discontinued in Dec 2024](https://forum.syncthing.net/t/discontinuing-syncthing-android/23002); use [Syncthing-Fork on F-Droid](https://f-droid.org/en/packages/com.github.catfriend1.syncthingfork)

### Install

> **Installed 2026-11-03:** Syncthing v2.1.7 from `apt.syncthing.net` (stable-v2).

From [apt.syncthing.net](https://apt.syncthing.net), run as root (no `sudo`):

```bash
mkdir -p /etc/apt/keyrings
curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" > /etc/apt/sources.list.d/syncthing.list

# Prefer Syncthing's packages over Debian's own (from the site's troubleshooting section)
cat > /etc/apt/preferences.d/syncthing.pref <<'PREF'
Package: *
Pin: origin apt.syncthing.net
Pin-Priority: 990
PREF

apt update
apt install -y syncthing
apt policy syncthing   # installed version should come from apt.syncthing.net
```

### Service user and service

Syncthing and the app both run as a dedicated system user `vault`, not root. A compromised app or Syncthing only gets `vault`'s permissions. (Our choice; Syncthing's docs advise against running as root.)

```bash
useradd --system --create-home --home-dir /var/lib/vault --shell /usr/sbin/nologin vault
chown -R vault:vault /srv/vault
systemctl enable --now syncthing@vault
```

- `syncthing@.service` ships with the package ([autostart on Linux](https://docs.syncthing.net/users/autostart.html#linux)); the part after `@` is the user.
- Config: `/var/lib/vault/.local/state/syncthing/config.xml`.
- Server device ID: `BTAELK6-ICVBTYW-K4HSLGE-SBDZ5GQ-AOGUMQ3-V3XREMT-CLMW7Z6-WVJK2AM`.
- Listening: `22000` TCP/UDP (sync), `21027` UDP (local discovery).

### Web UI

Reachable from the Mac at **http://obsidian-mcp.atlas.local:8384**, with a username and password (in Bitwarden: *Syncthing (obsidian-mcp)*). Our choice over an SSH tunnel; it's lab-internal like the other services.

```bash
su -s /bin/sh vault -c "syncthing cli config gui raw-address set 192.168.20.16:8384"
```

- Listen address is the IP, not the FQDN, so the UI doesn't depend on DNS at boot. The FQDN works in the browser because Syncthing only checks the Host header when bound to localhost.
- Password is set in the UI (**Actions → Settings → GUI**), not on the command line, so it stays out of shell history. Syncthing stores only a hash.

### Mac

> **Set up 2026-11-04:** Syncthing v2.1.7 from Homebrew. Vault at `~/vaults/notes`.

- **Vault:** `~/vaults/notes`, outside OneDrive so two sync tools don't fight over the same files. Opened in Obsidian with **Manage vaults → Open folder as vault**, which creates `.obsidian/`.
- **Install:** Homebrew rather than the menu bar app (our choice). `brew services` runs it as a launchd agent for the user, started at every login.

```bash
brew install syncthing
brew services start syncthing
```

- Web UI at **http://127.0.0.1:8384** (localhost only). Username `austin`, password in Bitwarden: *Syncthing (Mac)*, set in **Actions → Settings → GUI**.
- Mac device ID starts `QBYJF22`; device name `austin-mac.atlas.local`.

### Pairing

| Side | Device added | Addresses |
|---|---|---|
| Mac | `obsidian-mcp` (`BTAELK6…`) | `tcp://192.168.20.16:22000` (the server's IP is static) |
| Server | `austin-mac.atlas.local` (`QBYJF22…`), accepted from the new-device prompt | `dynamic` (the Mac's IP changes; the Mac opens the connection) |

All other device settings left at their defaults. Paired and connected 2026-11-04.

### Folder share

> **Shared and synced 2026-11-04.**

| Setting | Mac | Server |
|---|---|---|
| Folder label / ID | `notes` / `notes` | `notes` / `notes` (accepted from the Mac's share prompt) |
| Path | `~/vaults/notes` | `/srv/vault` (the default would be under `/var/lib/vault`) |
| Type | Send & Receive | Send & Receive |
| Versioning | Staggered, defaults (365 days, in `.stversions/`) | Staggered, defaults |

Everything else left at its defaults. Each side keeps old versions of files changed by the *other* side, so the Mac keeps what Claude edits on the server, and the server keeps what's edited on the Mac.

`.stignore` doesn't sync, so it was created on both sides. It went in **before** sharing, so the ignored files never went across:

```
// Obsidian's per-device UI state (open tabs, pane layout)
.obsidian/workspace.json
.obsidian/workspace-mobile.json

// macOS clutter
.DS_Store
```

On the server it's `/srv/vault/.stignore`, owned by `vault`.

## systemd service

> **Created 2026-11-04.** Running as `vault`, enabled at boot.

Runs the app the same way as the [test run](#vault-folder-env-file-and-test-run), but started by systemd at boot and restarted if it crashes.

**Source:** the README only ships **launchd** templates for macOS (`scripts/launchd/`), not a systemd unit. This unit is our own, modelled on those: start at boot, restart on failure, env vars from outside the repo.

### Unit file

`/etc/systemd/system/obsidian-web-mcp.service`. Hand-written units go in `/etc/systemd/system/`; package-installed ones (like Syncthing's) live in `/lib/systemd/system/`.

```ini
[Unit]
Description=Obsidian Web MCP server
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
EnvironmentFile=/etc/obsidian-web-mcp.env
ExecStart=/opt/obsidian-web-mcp/.venv/bin/vault-mcp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

| Line | Why |
|---|---|
| `After=` / `Wants=network-online.target` | The app binds to `192.168.20.16`, so the network must be up first |
| `User=vault` / `Group=vault` | Same user as Syncthing, so both can read and write `/srv/vault` |
| `EnvironmentFile=` | The [Configuration](#configuration) settings. systemd reads it as root before switching user, so it stays `root` / `600` and `vault` can't read it |
| `ExecStart=` | The venv's entry-point launcher (not `uv run`; see [Install uv and dependencies](#install-uv-and-dependencies)) |
| `Restart=on-failure`, `RestartSec=5` | Restart 5 seconds after a crash; a clean `systemctl stop` stays stopped |
| `WantedBy=multi-user.target` | `enable` hooks it into normal boot |

`/opt/obsidian-web-mcp` stays owned by root; `vault` only needs to read and run it.

### Enable and check

```bash
systemd-analyze verify /etc/systemd/system/obsidian-web-mcp.service   # no output = OK
systemctl daemon-reload
systemctl enable --now obsidian-web-mcp

systemctl status obsidian-web-mcp
journalctl -u obsidian-web-mcp -n 30 --no-pager
```

Expected:
- Log shows `Starting server on 192.168.20.16:8420 with bearer auth + OAuth` and `Vault: /srv/vault`.
- `ps -o user= -C vault-mcp` → `vault`.
- `curl -s http://192.168.20.16:8420/health` → `{"status":"ok",...}`.
- `curl -s -o /dev/null -w "%{http_code}\n" http://192.168.20.16:8420/` → `401` (no token).

### State directory

OAuth clients and tokens go in `~/.local/share/vault-mcp/` (README, *OAuth* section), which for `vault` is `/var/lib/vault/.local/share/vault-mcp/`. It's outside the vault, as the README requires, and is created when the first client connects. `vault`'s home is `/var/lib/vault` (system-user convention), not `/home`.

### Day to day

```bash
systemctl restart obsidian-web-mcp   # after editing the env file or pulling app updates
journalctl -u obsidian-web-mcp -f    # follow the log
```

After editing the unit file itself, run `systemctl daemon-reload` first.

## Firewall

> **Enabled 2026-11-05.** Proxmox firewall on CT 103 only. Logging of drops is on while testing.

Port 8420 only accepts connections from `cloudflared`, so the app is reachable only through the tunnel. The UniFi LAB zone already blocks other VLANs, but it can't filter traffic *within* VLAN 20 (e.g. from the Talos cluster); the Proxmox firewall can, because it filters at each guest's bridge port.

**Source:** [Proxmox VE firewall docs](https://pve.proxmox.com/wiki/Firewall). The README doesn't cover this (its design runs everything on one Mac); the rules are our design.

### How it's set up

A guest is only filtered when **all three** are on: the datacenter switch, the guest's firewall option, and the **Firewall** flag on its network interface. Other guests are unaffected until they're opted in.

| Level | Setting | GUI / file |
|---|---|---|
| Datacenter | **On** (master switch); aliases defined here | Datacenter → Firewall · `/etc/pve/firewall/cluster.fw` |
| Host | **Off**, so the Proxmox host isn't filtered (no lockout risk; revisit once we know what talks to the API) | proxmox → Firewall → Options · `/etc/pve/nodes/proxmox/host.fw` |
| CT 103 | **On**, input policy **DROP**, output **ACCEPT**, log level `info` | 103 → Firewall · `/etc/pve/firewall/103.fw` |
| CT 103 `net0` | `firewall=1` | 103 → Network → net0 → Firewall ✓ |

Standard (iptables) firewall, not the nftables `proxmox-firewall`, which Proxmox's docs call a tech preview.

**Aliases** (Datacenter → Firewall → Alias), so rules read by name and can be reused for other guests:

| Alias | Address |
|---|---|
| `admin_mac` | `192.168.0.58` (Mac, DHCP reservation) |
| `cloudflared` | `192.168.20.17` (LXC 104) |

**CT 103 rules** (incoming; everything else is dropped):

| Proto | Port | Source | For |
|---|---|---|---|
| tcp | 8420 | `cloudflared` | MCP app, tunnel only |
| tcp | 22 | `admin_mac` | SSH / VS Code |
| tcp | 8384 | `admin_mac` | Syncthing web UI |
| tcp + udp | 22000 | `admin_mac` | Syncthing sync |
| icmp | | `admin_mac` | ping |

Syncthing's local discovery (21027/udp) isn't allowed: it's broadcast-based and can't cross from the Mac's network to VLAN 20 anyway.

## Domain

> **Registered 2026-11-05:** `atlaskeep.dev` with Cloudflare Registrar, 1 year, auto-renew on (expires 2027-11-05, renews at $12.20/yr).
>
> **Cloudflare login:** Sign in with Google (personal Gmail).

A base domain for lab services (`notes.` first; others like `ha.` later). The tunnel's public hostname must be in a domain whose DNS is on Cloudflare. The plan's `atlaslab.dev` was already taken (registered by someone else in 2020), as were `atlas-lab.dev`, `atlaslabs.dev` and `atlaslab.com` / `.net` / `.org`.

Registering with Cloudflare Registrar (our choice) means the domain uses Cloudflare's nameservers from the start, so there's no nameserver move. Registrar domains can't switch to another DNS provider while registered there.

`.dev` is on the browser HSTS preload list, so it only works over HTTPS; the tunnel provides that.

References:
- [Create a Cloudflare account](https://developers.cloudflare.com/fundamentals/account/create-account/)
- [Two-factor authentication](https://developers.cloudflare.com/fundamentals/user-profiles/2fa/)
- [Register a new domain](https://developers.cloudflare.com/registrar/get-started/register-domain/) (Cloudflare Registrar)
- [WHOIS redaction](https://developers.cloudflare.com/registrar/account-options/whois-redaction/)
- App README: *Remote Access with Cloudflare Tunnel* section (used in the tunnel step)

[Configuration](#configuration) updated to `notes.atlaskeep.dev` (`VAULT_MCP_PUBLIC_URL`, `VAULT_MCP_ALLOWED_HOSTS`), then `systemctl restart obsidian-web-mcp`.

## Cloudflare tunnel

> **Live 2026-11-05.** `https://notes.atlaskeep.dev/health` returns OK from the internet; `/` without a token returns `401`; OAuth discovery advertises `https://notes.atlaskeep.dev`.

`cloudflared` on CT 104 keeps an outbound connection to Cloudflare. Requests to `https://notes.atlaskeep.dev` arrive at Cloudflare and come down that connection to `http://192.168.20.16:8420`. Nothing at home accepts inbound connections from the internet.

**Deviation from the README:** the README uses `scripts/setup-tunnel.sh` (`cloudflared login`, a locally-managed tunnel and config file, on the same Mac as the app). We use a **remotely-managed tunnel** from Cloudflare's docs instead (our choice): the tunnel and its route live in the dashboard, and CT 104 only holds a token. The README's other requirement still applies: `VAULT_MCP_ALLOWED_HOSTS` is set to the hostname (see [Configuration](#configuration)).

Pre-checks (2026-11-05): `cloudflared` 2026.10.7 on CT 104 (from Cloudflare's APT repo); outbound TCP 7844 to Cloudflare OK; `atlaskeep.dev` on Cloudflare nameservers.

| Setting | Value |
|---|---|
| Tunnel name / ID | `atlas-lab` / `3cf91843-bd25-49cb-82ba-222dfec762cb` |
| Connector | CT 104 `cloudflared` (`192.168.20.17`), as a systemd service |
| Token | In Bitwarden: *Cloudflare tunnel (atlas-lab)*. Installed with `cloudflared service install <token>` (the dashboard's Debian command; package-install lines skipped, `cloudflared` was already installed). The token is in the unit file, so `chmod 600 /etc/systemd/system/cloudflared.service` (our choice) |
| Published application | `notes.atlaskeep.dev` → `http://192.168.20.16:8420`. Cloudflare created the DNS record (CNAME to `<tunnel-id>.cfargotunnel.com`). Additional application settings left at defaults (the original Host header is passed through, which `VAULT_MCP_ALLOWED_HOSTS` checks) |

References:
- [Create a remotely-managed tunnel (dashboard)](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)
- [Cloudflare Tunnel overview](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Tunnel connectivity pre-checks](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/troubleshoot-tunnels/connectivity-prechecks/) (port 7844)
- App README: *Remote Access with Cloudflare Tunnel*; *Cloudflare Access mode (opt-in)* for optional SSO in front, not used for now
