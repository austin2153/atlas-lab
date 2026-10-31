# ArgoCD

## Reference

| Resource | Link |
|---|---|
| ArgoCD docs | https://argo-cd.readthedocs.io/en/stable/ |
| Releases | https://github.com/argoproj/argo-cd/releases |
| ApplicationSet git generator | https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/ |
| Declarative repo credentials | https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories |
| GitHub deploy keys | https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys |

**Currently installed:** ArgoCD v3.3.7 in the `argocd` namespace (`argocd.atlas.local`, `192.168.20.50`)

To check the installed version:
```bash
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

ArgoCD is the lab's GitOps engine. One ApplicationSet (`platform`) watches `platform/*` in this repo and turns every subfolder into an ArgoCD Application with automated sync, self-heal and prune. Adding a service means adding a folder and pushing to `main`.

ArgoCD manages everything under `platform/`, but **ArgoCD itself, the ApplicationSet, and the repo credential are not managed by ArgoCD**. They were applied by hand with `kubectl`. That's the main thing this runbook exists to document: the parts of the GitOps setup that Git alone won't fix.

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Install method | Upstream `install.yaml` via `kubectl apply` | Simplest path; no Helm release to manage |
| Self-management | ArgoCD does **not** manage itself or the ApplicationSet | Avoids the bootstrap chicken-and-egg; revisit with an app-of-apps root later (see Open items) |
| App discovery | One ApplicationSet with a git directory generator on `platform/*` | New services need no ArgoCD wiring, just a folder |
| Sync policy | Automated, `selfHeal: true`, `prune: true` | Git is the source of truth; manual drift gets reverted and deleted manifests get removed |
| Repo access | SSH, read-only GitHub deploy key | Scoped to this one repo; can't push |
| Repo credential | `repository`-type secret `atlas-lab-repo`, created imperatively | Private key must never be committed (the repo is public) |
| Exposure | `argocd-server` Service patched to `LoadBalancer`, pinned to `192.168.20.50` | MetalLB; see `docs/network-address-plan.md` |
| DNS | `argocd.atlas.local` → `192.168.20.50` in Pi-hole | |

## What lives where

| Piece | Where it's defined | Applied how | Picks up Git changes automatically? |
|---|---|---|---|
| ArgoCD itself | Upstream `install.yaml` (v3.3.7) | `kubectl apply` by hand | No |
| `argocd-server` LoadBalancer patch | This runbook (Step 2) | `kubectl patch` by hand | No |
| Repo credential `atlas-lab-repo` | This runbook (Step 3); key at `~/.ssh/argocd-atlas-talos` | `kubectl create secret` by hand | No (not in Git) |
| ApplicationSet `platform` | [`platform/appset.yaml`](../../platform/appset.yaml) | `kubectl apply` by hand | **No.** Re-apply after every change |
| Everything under `platform/*/` | This repo | ArgoCD | Yes, within ~3 minutes of a push to `main` |

> **Gotcha:** `platform/appset.yaml` sits *inside* `platform/` but is a file, not a folder, so the generator (`platform/*` directories) never picks it up. Editing it in Git does nothing until you `kubectl apply` it. This is how the live ApplicationSet stayed on the old `atlas-talos.git` URL after the repo rename on 2026-10-31.

---

## Rebuild from scratch

Use this after a cluster rebuild, or if ArgoCD is ever reinstalled. Steps 1–2 were reconstructed from the live install (the original commands weren't recorded); Steps 3–5 match what's running today.

### Prerequisites
- Talos cluster running (`kubectl get nodes` shows Ready)
- MetalLB deployed with the `default-pool` covering `192.168.20.50`. On a fresh cluster ArgoCD deploys MetalLB itself, so the LoadBalancer IP stays `<pending>` until the `metallb` app syncs. That's expected.
- Deploy key private half at `~/.ssh/argocd-atlas-talos` on the Mac

---

### Step 1 — Install ArgoCD

```bash
kubectl create namespace argocd

# Pin the version; check the releases page before upgrading.
# --server-side is needed because some ArgoCD CRDs are too large for client-side apply's annotation.
ARGOCD_VERSION=v3.3.7
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

kubectl rollout status deploy/argocd-server -n argocd
```

---

### Step 2 — Expose the UI

```bash
# LoadBalancer via MetalLB, pinned to the address reserved in docs/network-address-plan.md
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"LoadBalancer","loadBalancerIP":"192.168.20.50"}}'

kubectl get svc argocd-server -n argocd   # EXTERNAL-IP: 192.168.20.50
```

Initial admin password (change it after first login):
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```

---

### Step 3 — Repo credential

ArgoCD clones this repo over SSH (`git@github.com:...`). GitHub requires a key for SSH even on public repos, so ArgoCD needs the deploy key.

ArgoCD matches a `repository` secret to an Application by **exact URL**. If the URL in the secret doesn't match the `repoURL` in the ApplicationSet character for character, ArgoCD tries without credentials and every app fails with an SSH auth error.

```bash
# Read-only deploy key "argocd-atlas-talos" on github.com/austin2153/atlas-lab
# (key title predates the repo rename; the key itself is fine)
kubectl create secret generic atlas-lab-repo -n argocd \
  --from-literal=type=git \
  --from-literal=url=git@github.com:austin2153/atlas-lab.git \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd-atlas-talos

# This label is what makes ArgoCD treat the secret as a repo credential
kubectl label secret atlas-lab-repo -n argocd argocd.argoproj.io/secret-type=repository
```

If the deploy key is ever lost, generate a new one and register it on GitHub (read-only):
```bash
ssh-keygen -t ed25519 -N "" -C "argocd@atlas-lab" -f ~/.ssh/argocd-atlas-lab
gh repo deploy-key add ~/.ssh/argocd-atlas-lab.pub --repo austin2153/atlas-lab --title argocd-atlas-lab
```
Then create the secret from the new key and delete the old deploy key from GitHub.

---

### Step 4 — Apply the ApplicationSet

```bash
kubectl apply -f platform/appset.yaml
```

Within a minute or two, one Application appears per folder under `platform/`.

---

### Step 5 — Verify

```bash
# Every app should be Synced / Healthy and point at atlas-lab.git
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REPO:.spec.source.repoURL

# Any app with an error condition (no output = none)
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.conditions}{"\n"}{end}' | grep -v ': $'
```

---

## Common operations

### Add a platform component

Add a folder `platform/<name>/` with plain manifests (or a `kustomization.yaml`), commit and push to `main`. The ApplicationSet creates an Application named `<name>` automatically. Nothing else is needed.

Removing the folder deletes the Application **and** (because of `prune: true`) everything it deployed.

### Change the ApplicationSet

Edit `platform/appset.yaml`, commit, then apply it by hand:
```bash
kubectl diff -f platform/appset.yaml    # review first
kubectl apply -f platform/appset.yaml
```
Changing only the template's `source.repoURL` or sync policy updates the Applications in place; workloads aren't recreated.

### Force a refresh

ArgoCD polls Git about every 3 minutes. To re-fetch now:
```bash
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite
# or every app:
kubectl annotate applications --all -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

### Pause self-heal while debugging

Self-heal reverts any manual `kubectl edit` within seconds. To experiment on a live app, comment out `selfHeal: true` in `platform/appset.yaml` and re-apply it (this affects **every** app), then restore it when done.

### Renaming the GitHub repo

Learned from the `atlas-talos` → `atlas-lab` rename. GitHub redirects the old URL, so nothing breaks immediately. That hides the drift until the redirect goes away. Do it in this order so ArgoCD never loses access:

1. Update every `repoURL` in Git (`platform/appset.yaml`, plus `platform/flux/gitrepository.yaml` and `platform/kratix/git-state-store.yaml`, which have their own URLs). Commit and push.
2. Create a **new** repo secret with the new URL and the same key (Step 3, with a new secret name). Keep the old one for now.
3. `kubectl apply -f platform/appset.yaml`.
4. Hard-refresh all apps and confirm Synced / Healthy on the new URL (Step 5).
5. Delete the old repo secret.

Doing step 3 before step 2 leaves ArgoCD with no credential for the new URL, and every app goes to `Unknown` with a comparison error until the secret exists. Nothing gets deleted, but sync stops.

---

## Troubleshooting

**App shows `Unknown` sync status / `ComparisonError` mentioning SSH or authentication**

The repo credential doesn't match the app's URL. Compare them:
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.data.url}{"\n"}{end}' \
  | while read n u; do echo "$n $(echo $u | base64 -d)"; done
kubectl get applicationset platform -n argocd -o jsonpath='{.spec.template.spec.source.repoURL}'; echo
```

**A change to `platform/appset.yaml` didn't take effect**

It's not managed by ArgoCD. `kubectl apply -f platform/appset.yaml`.

**New folder under `platform/` didn't become an app**

Check the ApplicationSet controller logs:
```bash
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=50
```

---

## Open items

- [ ] Make ArgoCD manage the ApplicationSet (app-of-apps root `Application` pointing at a folder outside `platform/*`), so Git changes to it apply automatically
- [ ] Move the repo credential into Vault and sync it with External Secrets Operator once ESO is deployed (see `vault-install.md`, Step 13)
- [ ] Optionally re-create the GitHub deploy key with an `atlas-lab` title (cosmetic)
- [ ] Issue a Vault PKI cert for `argocd.atlas.local` (currently ArgoCD's self-signed cert)
