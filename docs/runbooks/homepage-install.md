# Homepage

Homepage is a modern, highly configurable service dashboard. It provides a single starting page for the lab — links and live status widgets for Proxmox, Vault, ArgoCD, Pi-hole, and any other service worth surfacing. All configuration lives in files so it follows the same GitOps pattern as the rest of the platform.

**Target:** `homepage.atlas.local` running in the atlas-talos Kubernetes cluster, managed by ArgoCD, exposed via MetalLB.

## Reference

| Resource | Link |
|---|---|
| Homepage docs | https://gethomepage.dev/ |
| Kubernetes installation | https://gethomepage.dev/installation/k8s/ |
| Homepage GitHub | https://github.com/gethomepage/homepage |
| Service widgets | https://gethomepage.dev/widgets/ |

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Deployment | Plain Kubernetes manifests in `platform/homepage/` | Homepage's official docs recommend raw manifests; no official Helm chart exists |
| GitOps | ArgoCD auto-discovers `platform/homepage/` | No special wiring needed — the root ApplicationSet picks it up |
| Service IP | MetalLB `.54` (`192.168.20.54`) | Pinned address; outside DHCP range; keeps the address plan accurate |
| DNS | `homepage.atlas.local` → `192.168.20.54` via Pi-hole | Same pattern as all other `*.atlas.local` names |
| TLS | None initially; add Vault-issued cert as Step 6 | Get it running first; TLS mirrors the Proxmox cert pattern from vault-install.md |
| Configuration | ConfigMap mounted at `/app/config/` | Homepage reads its config files from a ConfigMap; all config lives in Git |
| Namespace | `homepage` | Isolated from platform services |
| Service widgets | Proxmox, Vault, ArgoCD, Pi-hole | Start with what we already have running; add more as services come online |

## PKI / TLS note

Homepage will eventually get a Vault-issued cert for `homepage.atlas.local`. That step is deferred until after the service is verified running. The pattern is the same as Step 11 in `vault-install.md` — issue a cert from the `atlas-lab` role, deploy it to a Kubernetes Secret, and reference it in the Ingress or service TLS config.

---

## Step 1 — Understand what Homepage is and how it works

Homepage is a static-ish dashboard: it reads a set of YAML config files on startup and renders a page. No database, no auth by default. The interesting parts are:

- **`services.yaml`** — defines the service tiles (name, URL, description, icon)
- **`widgets.yaml`** — the top-of-page info bar (clock, weather, search)
- **`bookmarks.yaml`** — link groups (optional; shortcuts to frequently used pages)
- **`settings.yaml`** — global settings (title, theme, color scheme)
- **`docker.yaml`** — optional Docker socket integration for auto-discovering containers

In a Kubernetes deployment, these files come from a ConfigMap. The pod mounts them at `/app/config/` using `subPath` entries so each key lands as a separate file.

Homepage also supports **service widgets** — live data pulled from service APIs shown directly on the tile. For example, the Proxmox tile can show CPU/RAM usage, the Pi-hole tile can show query stats, and the ArgoCD tile can show sync status. Each widget requires an API key or token.

## Step 2 — Create the manifests under `platform/homepage/`

The ArgoCD ApplicationSet watches `platform/*` and auto-discovers any subfolder. Adding `platform/homepage/` with plain Kubernetes manifests is all that's needed to get ArgoCD to deploy it. Homepage's official docs recommend this approach — there is no official Helm chart.

```bash
mkdir -p platform/homepage
```

The folder needs five files: a Namespace, a ServiceAccount + RBAC (for Kubernetes service discovery), a ConfigMap (all Homepage config), a Deployment, and a Service.

**`platform/homepage/namespace.yaml`**:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: homepage
```

**`platform/homepage/rbac.yaml`** — ServiceAccount and cluster-read permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: homepage
  namespace: homepage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: homepage
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods", "nodes"]
    verbs: ["get", "list"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: homepage
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: homepage
subjects:
  - kind: ServiceAccount
    name: homepage
    namespace: homepage
```

**`platform/homepage/configmap.yaml`** — all Homepage configuration files in one ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: homepage
  namespace: homepage
data:
  settings.yaml: |
    title: Atlas Lab
    theme: dark
    color: slate

  services.yaml: |
    - Lab:
        - Proxmox:
            href: https://proxmox.atlas.local:8006
            description: Hypervisor (Proxmox VE 9.2)
            icon: proxmox.png
        - Vault:
            href: https://vault.atlas.local:8200
            description: Secrets and PKI (HashiCorp Vault)
            icon: vault.png
        - ArgoCD:
            href: https://argocd.atlas.local
            description: GitOps controller
            icon: argo-cd.png
        - Pi-hole:
            href: http://atlas-pihole.atlas.local/admin
            description: DNS and ad blocking
            icon: pi-hole.png

  widgets.yaml: |
    - resources:
        cpu: true
        memory: true
    - search:
        provider: google
        target: _blank

  bookmarks.yaml: |
    []

  docker.yaml: |
    {}

  kubernetes.yaml: |
    mode: cluster
```

> The services list above is the starting point. Add widget blocks (live API data) to each service entry after verifying the basic tiles load — that's Step 7.

**`platform/homepage/deployment.yaml`**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  namespace: homepage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: homepage
  template:
    metadata:
      labels:
        app: homepage
    spec:
      serviceAccountName: homepage
      containers:
        - name: homepage
          image: ghcr.io/gethomepage/homepage:v2.7.0   # pin to a specific version
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: HOMEPAGE_ALLOWED_HOSTS
              value: "$(MY_POD_IP):3000,homepage.atlas.local"
          livenessProbe:
            httpGet:
              path: /api/healthcheck
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 15
          volumeMounts:
            - name: config
              mountPath: /app/config/settings.yaml
              subPath: settings.yaml
            - name: config
              mountPath: /app/config/services.yaml
              subPath: services.yaml
            - name: config
              mountPath: /app/config/widgets.yaml
              subPath: widgets.yaml
            - name: config
              mountPath: /app/config/bookmarks.yaml
              subPath: bookmarks.yaml
            - name: config
              mountPath: /app/config/docker.yaml
              subPath: docker.yaml
            - name: config
              mountPath: /app/config/kubernetes.yaml
              subPath: kubernetes.yaml
            - name: logs
              mountPath: /app/config/logs
      volumes:
        - name: config
          configMap:
            name: homepage
        - name: logs
          emptyDir: {}
```

> Pin the image tag. Check the [GitHub releases page](https://github.com/gethomepage/homepage/releases) for the latest version before deploying.

**`platform/homepage/service.yaml`**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: homepage
  namespace: homepage
  annotations:
    metallb.io/loadBalancerIPs: 192.168.20.54
spec:
  type: LoadBalancer
  selector:
    app: homepage
  ports:
    - name: http
      port: 80
      targetPort: 3000
```

## Step 3 — Review the manifest set before committing

Before pushing, do a quick sanity check on the five files:

```bash
ls platform/homepage/
# namespace.yaml  rbac.yaml  configmap.yaml  deployment.yaml  service.yaml
```

Check that the image tag in `deployment.yaml` matches an actual [release](https://github.com/gethomepage/homepage/releases), and that `192.168.20.54` is not already in use:

```bash
kubectl get svc -A | grep LoadBalancer   # confirm .54 is free
```

## Step 4 — Commit and push; let ArgoCD deploy

Once the files are in place:

```bash
git add platform/homepage/
git status       # verify only homepage files are staged
git commit -m "platform: add Homepage service dashboard"
git push
```

ArgoCD polls the repo every ~3 minutes and will create the Application automatically. Watch it come up:

```bash
# Watch ArgoCD pick up the new app
kubectl get applications -n argocd homepage -w

# Watch the pod come up in the homepage namespace
kubectl get pods -n homepage -w

# Check the assigned MetalLB address
kubectl get svc -n homepage
```

The service should get `192.168.20.54` from MetalLB. If it shows `<pending>`, see the troubleshooting note at the end of this doc.

## Step 5 — Add the Pi-hole DNS entry

Once the IP is confirmed:

```bash
# Add DNS record for homepage.atlas.local
ssh -i ~/.ssh/proxmox-claude root@192.168.0.100 \
  "pct exec 102 -- pihole-FTL --config dns.hosts '192.168.20.54 homepage.atlas.local'"
```

Verify resolution:

```bash
dig homepage.atlas.local @192.168.0.101 +short   # should return 192.168.20.54
```

Then open `http://homepage.atlas.local` in the browser. The tiles should render and the links should work.

## Step 6 — Add Vault-issued TLS (deferred)

> **Prerequisite:** Step 11 in `vault-install.md` covers the pattern for issuing a service cert. Complete that first (or review the Proxmox cert steps — the process is identical).

Once the basic dashboard is working, replace the plain HTTP endpoint with HTTPS:

1. Issue a cert for `homepage.atlas.local` from the `atlas-lab` Vault role
2. Store the cert and key in a Kubernetes Secret in the `homepage` namespace
3. Add an Ingress resource pointing at the Secret, or update `service.yaml` to reference it
4. Update the Pi-hole DNS record if the IP changes
5. Remove the self-signed bypass if any was added

## Step 7 — Configure service widgets (deferred)

Homepage's real value comes from live widgets — tiles that show actual status rather than just links. Each widget calls the service's API from the Homepage pod. Credentials must be supplied as Kubernetes Secrets and referenced in `values.yaml`.

| Service | Widget type | What it shows | Credential needed |
|---|---|---|---|
| Proxmox | `proxmox` | CPU/RAM/storage per node | Proxmox API token |
| Pi-hole | `pihole` | Query count, blocked %, clients | Pi-hole API key |
| ArgoCD | `argocd` | App count, sync status | ArgoCD API token |
| Vault | — | No official widget yet; use plain link | — |

Workflow for adding a widget:

1. Create a Kubernetes Secret with the API credential in the `homepage` namespace
2. Add a `widget:` block to the relevant service entry in `configmap.yaml`
3. Push the change; ArgoCD syncs; the tile updates

> Credentials for widgets go in Kubernetes Secrets — **not** in `configmap.yaml` directly (that file is committed to Git). Once Vault's Kubernetes auth and External Secrets Operator are set up (vault-install.md Steps 12–13), those secrets can be populated from Vault automatically.

## Open items

| Item | Status |
|---|---|
| Basic dashboard (tiles, no widgets) | Planned |
| Pi-hole DNS entry | Planned |
| Vault-issued TLS cert | Deferred (Step 6 above) |
| Proxmox widget | Deferred (needs API token in a K8s Secret) |
| Pi-hole widget | Deferred (needs Pi-hole API key) |
| ArgoCD widget | Deferred (needs ArgoCD token) |
| ESO integration for widget secrets | Deferred (needs Vault K8s auth — vault-install.md Step 12) |

## Troubleshooting

**Service stuck at `<pending>` (no MetalLB address assigned)**

Check whether the address is already taken or outside the pool:

```bash
kubectl get svc -A | grep LoadBalancer       # what addresses are already in use
kubectl -n metallb-system logs -l component=speaker   # what MetalLB is announcing
```

The pool is `192.168.20.50–99`. If `.54` is already in use, pick another from the pool and update both `service.yaml` and the Pi-hole DNS entry.

**Tiles show "Service offline" or fail to load**

Homepage resolves service URLs from inside the pod. `proxmox.atlas.local` needs to resolve via the cluster DNS (which forwards to Pi-hole) and be reachable from the cluster network (VLAN 20). Verify:

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup proxmox.atlas.local
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- https://proxmox.atlas.local:8006 --no-check-certificate
```

**ArgoCD doesn't pick up the new app**

Force a repo refresh:

```bash
argocd app list   # if homepage doesn't appear after 5 min
argocd repo list  # verify the repo is connected
# or trigger a hard refresh via the ArgoCD UI
```
