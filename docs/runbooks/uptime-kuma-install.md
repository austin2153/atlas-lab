# Uptime Kuma

Uptime Kuma is a self-hosted uptime monitoring tool. It checks services on a schedule and tracks uptime history, response times, and sends alerts on failures. In this lab it provides the health status badges visible on the Homepage dashboard.

**Target:** `uptime-kuma.atlas.local` running in the atlas-talos Kubernetes cluster, managed by ArgoCD, exposed via MetalLB.

## Reference

| Resource | Link |
|---|---|
| Uptime Kuma GitHub | https://github.com/louislam/uptime-kuma |
| Docker Hub image | https://hub.docker.com/r/louislam/uptime-kuma |
| Homepage widget docs | https://gethomepage.dev/widgets/services/uptimekuma/ |
| Demo | https://demo.uptime.kuma.pet |

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Deployment | Plain Kubernetes manifests in `platform/uptime-kuma/` | Consistent with rest of platform |
| Storage | PersistentVolumeClaim backed by local-path-provisioner | SQLite database needs persistence across pod restarts |
| Service IP | MetalLB `.55` (`192.168.20.55`) | Next available pinned address after Homepage (`.54`) |
| DNS | `uptime-kuma.atlas.local` → `192.168.20.55` via Pi-hole | Same pattern as all other `*.atlas.local` names |
| Image | `louislam/uptime-kuma:2.5.8` | Latest stable as of install date |

---

## Step 1 — Understand what Uptime Kuma does

Uptime Kuma monitors services by making HTTP/HTTPS/TCP/DNS/ping checks on a configurable interval. For each monitor it tracks:

- Current status (up/down)
- Response time
- Uptime percentage (24h, 7d, 30d)
- Incident history

Homepage integrates with Uptime Kuma via its API — each service tile can show a live status badge pulled from a named Uptime Kuma monitor.

## Step 2 — Create manifests under `platform/uptime-kuma/`

> TODO: Add namespace, PVC, deployment, and service manifests

## Step 3 — Add Pi-hole DNS entry

```bash
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 \
  "pct exec 102 -- pihole-FTL --config dns.hosts '192.168.20.55 uptime-kuma.atlas.local'"
```

## Step 4 — Configure monitors

Once deployed, open `http://uptime-kuma.atlas.local` and add monitors for:

| Service | Type | URL |
|---|---|---|
| Proxmox | HTTPS | `https://proxmox.atlas.local:8006` |
| Pi-hole | HTTP | `http://atlas-pihole.atlas.local/admin` |
| Vault | HTTPS | `https://vault.atlas.local:8200` |
| ArgoCD | HTTPS | `https://argocd.atlas.local` |
| Homepage | HTTP | `http://homepage.atlas.local` |

## Step 5 — Add Homepage widget

> TODO: Document Homepage widget config once Uptime Kuma is running

## Open items

| Item | Status |
|---|---|
| Manifests | TODO |
| DNS entry | TODO |
| Monitor configuration | TODO |
| Homepage widget | TODO |

## Future consideration — full observability stack

Uptime Kuma covers basic up/down health. For deeper observability (metrics over time, alerting, log aggregation) the options to evaluate later are:

- **kube-prometheus-stack** — Prometheus + Grafana + Alertmanager, pre-wired for Kubernetes. The production standard. Heavier but gives CPU/memory graphs, pod restart counts, custom alerts.
- **TIG stack** — Telegraf + InfluxDB + Grafana. Better for network gear and SNMP metrics, common in homelab setups predating Prometheus.
- **Grafana LGTM stack** — Loki (logs) + Grafana + Tempo (tracing) + Mimir (metrics). Grafana's own full observability suite.

No decision made yet — revisit once the core lab services are stable.
