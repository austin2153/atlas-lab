# Homepage

[Homepage](https://gethomepage.dev/) is a file-configured service dashboard: one start page for the lab with links and live status widgets. It runs in the Talos cluster from the plain manifests in `platform/homepage/`, deployed by ArgoCD and exposed through MetalLB.

**Status:** parked. The Deployment is scaled to `replicas: 0`; the Service, its MetalLB address and the DNS name stay in place. Set `replicas: 1` and push to bring it back.

## References

- [Homepage docs](https://gethomepage.dev/)
- [Kubernetes installation](https://gethomepage.dev/installation/k8s/)
- [Service widgets](https://gethomepage.dev/widgets/)
- [Releases](https://github.com/gethomepage/homepage/releases)

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Deployment | Plain manifests in `platform/homepage/` | Homepage's docs recommend raw manifests; there's no official Helm chart |
| GitOps | Picked up by the root ApplicationSet | Every folder under `platform/` becomes an ArgoCD app; no extra wiring |
| Exposure | MetalLB LoadBalancer pinned to `192.168.20.54`, port 80 | Fixed address from the MetalLB pool for a stable DNS name |
| DNS | `homepage.atlas.local` → `192.168.20.54` | Same pattern as the other lab names |
| Configuration | ConfigMap mounted at `/app/config/` | All dashboard config lives in Git |
| Secrets | Kubernetes Secrets created by hand, read through `envFrom` | Credentials never go in the ConfigMap, which is committed to a public repo |
| TLS | None yet | A Vault-issued certificate is planned (see [vault-architecture.md](vault-architecture.md)) |

## Manifests

| File | What it holds |
|---|---|
| `namespace.yaml` | The `homepage` namespace |
| `rbac.yaml` | ServiceAccount, ClusterRole and binding: read access to namespaces, pods, nodes, ingresses and metrics, for the Kubernetes widgets |
| `configmap.yaml` | `settings.yaml`, `services.yaml`, `widgets.yaml`, `bookmarks.yaml`, `docker.yaml`, `kubernetes.yaml` |
| `deployment.yaml` | The Homepage container (pinned image tag), each ConfigMap key mounted as its own file with `subPath`, `HOMEPAGE_ALLOWED_HOSTS`, and the widget Secrets via `envFrom` |
| `service.yaml` | LoadBalancer Service on port 80 → container port 3000, with the `metallb.io/loadBalancerIPs` annotation |

When updating the image, check the tag against the releases page, and that the pinned address isn't used by another Service (`kubectl get svc -A | grep LoadBalancer`).

## Widget secrets

Service widgets call each service's API from inside the pod. Homepage only substitutes environment variables that start with `HOMEPAGE_VAR_`, written as `{{HOMEPAGE_VAR_NAME}}` in the config files. Each widget's credentials are a Secret in the `homepage` namespace whose keys carry that prefix, loaded into the container with `envFrom`.

| Secret | Keys | Used by |
|---|---|---|
| `proxmox-widget` | `HOMEPAGE_VAR_PROXMOX_TOKEN_ID`, `HOMEPAGE_VAR_PROXMOX_TOKEN_SECRET` | Proxmox widget (read-only `PVEAuditor` API token) |
| `pihole-widget` | `HOMEPAGE_VAR_PIHOLE_KEY` | Pi-hole v6 widget |

```yaml
# configmap.yaml (services.yaml): a widget reads its credentials from env vars
widget:
  type: proxmox
  url: https://proxmox.atlas.local:8006
  username: "{{HOMEPAGE_VAR_PROXMOX_TOKEN_ID}}"
  password: "{{HOMEPAGE_VAR_PROXMOX_TOKEN_SECRET}}"

# deployment.yaml: the Secrets become env vars in the container
envFrom:
  - secretRef:
      name: proxmox-widget
  - secretRef:
      name: pihole-widget
```

The Secrets are created imperatively, not stored in Git. Once Vault's Kubernetes auth and External Secrets Operator are set up, they can be synced from Vault instead.

**Planned:** an ArgoCD widget (needs an ArgoCD API token). Vault has no official widget, so it gets a plain link.

## Deploy and check

Changes deploy by pushing to `main`; ArgoCD polls the repo about every 3 minutes.

```bash
kubectl get applications -n argocd homepage     # synced and healthy
kubectl get pods -n homepage                    # running (none while parked)
kubectl get svc -n homepage                     # EXTERNAL-IP 192.168.20.54
```

## Troubleshooting

**Service stuck at `<pending>`:** the address is taken or outside the MetalLB pool (`192.168.20.50–.99`). Pick a free one and update `service.yaml` and the DNS record.

```bash
kubectl get svc -A | grep LoadBalancer
kubectl -n metallb-system logs -l component=speaker
```

**Tiles show "Service offline":** Homepage resolves and calls service URLs from inside the pod, through cluster DNS and the lab network. Test from a throwaway pod:

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup proxmox.atlas.local
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- --no-check-certificate https://proxmox.atlas.local:8006
```

**A widget shows dashes:** the Secret is missing or wrong, or a firewall blocks the pod from reaching the service. Check `kubectl get secret -n homepage` and the pod logs.

**ArgoCD doesn't pick up a change:** `argocd app get homepage --refresh`, or Refresh in the ArgoCD UI.
