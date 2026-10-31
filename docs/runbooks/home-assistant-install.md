# Home Assistant

Home Assistant is an open-source home automation platform that integrates with thousands of smart home devices — lights, switches, sensors, locks, climate, media players, and more. It runs locally, keeping all automation logic and device data on-premises.

**Target:** `home-assistant.atlas.local` running in the atlas-talos Kubernetes cluster, managed by ArgoCD, exposed via MetalLB.

## Reference

| Resource | Link |
|---|---|
| Home Assistant docs | https://www.home-assistant.io/docs/ |
| Container installation | https://www.home-assistant.io/installation/linux#docker-compose |
| Docker Hub image | https://hub.docker.com/r/homeassistant/home-assistant |
| Integrations catalog | https://www.home-assistant.io/integrations/ |
| Community forum | https://community.home-assistant.io/ |

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Deployment | Plain Kubernetes manifests in `platform/home-assistant/` | Consistent with rest of platform |
| Flavor | Home Assistant Container (`homeassistant/home-assistant`) | Home Assistant OS is not suitable for Kubernetes; Container flavor runs the core app |
| Storage | PersistentVolumeClaim backed by local-path-provisioner | Configuration and automation data must persist across pod restarts |
| Network mode | Standard Kubernetes networking | Sufficient for cloud/IP-based integrations; USB device passthrough addressed separately if needed |
| Service IP | MetalLB `.56` (`192.168.20.56`) | Next available pinned address |
| DNS | `home-assistant.atlas.local` → `192.168.20.56` via Pi-hole | Same pattern as all other `*.atlas.local` names |

---

## Network considerations

Home Assistant discovers and controls devices in several ways. Each has different network requirements from inside the cluster:

| Integration type | Examples | Works from cluster? |
|---|---|---|
| Cloud-based | Google Home, Amazon Alexa, IFTTT | Yes — outbound HTTPS only |
| IP-based (local) | Philips Hue, UniFi, Sonos, Apple TV | Yes — same LAN or routed VLAN |
| mDNS/Bonjour discovery | Chromecast, some bulbs | Needs host network mode or mDNS proxy |
| USB devices | Zigbee/Z-Wave dongles | Requires node-level device passthrough |

For Philips Hue (bridge-based, IP) and UniFi this is straightforward. mDNS-dependent devices may require additional configuration.

---

## Step 1 — Understand what Home Assistant is

Home Assistant is a local-first automation hub. Key concepts:

- **Integrations** — connectors to external devices and services (there are 3000+)
- **Entities** — individual controllable things (a light, a sensor, a switch)
- **Automations** — rules that trigger actions based on state changes, time, or conditions
- **Dashboards (Lovelace)** — customizable UI for controlling devices
- **Add-ons** — only available in Home Assistant OS, not in Container flavor

The Container flavor includes the core platform and all integrations. It does not include the Supervisor or Add-ons system — those require Home Assistant OS.

## Step 2 — Create manifests under `platform/home-assistant/`

> TODO: Add namespace, PVC, deployment, and service manifests

## Step 3 — Add Pi-hole DNS entry

```bash
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 \
  "pct exec 102 -- pihole-FTL --config dns.hosts '192.168.20.56 home-assistant.atlas.local'"
```

## Step 4 — Initial setup

On first launch, navigate to `http://home-assistant.atlas.local:8123` to complete the onboarding wizard:

1. Create admin account
2. Set location (used for sun-based automations)
3. Home Assistant will auto-discover devices on the network

## Step 5 — Configure integrations

> TODO: Document specific integrations as they are set up (Hue, UniFi, etc.)

## Open items

| Item | Status |
|---|---|
| Manifests | TODO |
| DNS entry | TODO |
| Initial setup | TODO |
| Philips Hue integration | TODO |
| UniFi integration | TODO |
| Homepage widget | TODO |
