# Image automation

Flux watches ghcr.io for new tags and writes them into the image pins in
`../kustomization.yaml` itself, then reconciles its own commit. The full path:

```
service repo push → CI builds + pushes to ghcr → image-reflector notices the tag
  → image-automation commits the pin → source-controller sees the commit
  → kustomize-controller applies → rolling update
```

Nothing in a service repo needs credentials on this one. That is the point of
doing it this way rather than with a cross-repo PAT in each service's CI.

This is live. All three prerequisites below are done and recorded, because none
of them is guessable from the manifests alone.

Order matters if it ever has to be rebuilt: CRDs, then both credentials, then
wire this directory into `../kustomization.yaml`. Listed before its CRDs exist,
kustomize-controller fails the *entire* build on the unknown kind and every app
in this repo stops reconciling — not just this one.

## Prerequisites

### 1. The two controllers — **done**

`image-reflector-controller` and `image-automation-controller` are installed at
v1.2.3, the versions in the Flux v2.9.3 bundle this cluster runs. RBAC needed no
change: `crd-controller-flux-system` already listed both service accounts, since
the original install generated the full subject list even though only four
controllers were deployed.

Recorded because none of it is obvious if it has to be done again:

- **Match the running version.** The cluster is on **v2.9.3**, not latest.
  Applying `flux2/releases/download/v2.9.4/install.yaml` would have quietly
  upgraded all four existing controllers and added `source-watcher` as a side
  effect of wanting image automation. Take the two per-component files out of
  that release's `manifests.tar.gz` instead.
- **Pass `-n flux-system`.** The per-component manifests carry no `namespace:`
  on the namespaced objects — `flux install` sets it via kustomize. A plain
  `kubectl apply -f` puts the ServiceAccount and Deployment in `default`, where
  they run happily and do nothing, because the ClusterRoleBindings name those
  service accounts in `flux-system`.
- **Repoint the images at ghcr.** The raw manifests reference Docker Hub
  (`fluxcd/image-reflector-controller`), unlike the four already running, which
  use `ghcr.io/fluxcd/...`. Left alone it works until Docker Hub's anonymous
  pull limit says otherwise.

On API versions: at v2.9.x all three image kinds are `image.toolkit.fluxcd.io/v1`.
Most writing on this still shows `v1beta2`.

### 2. A registry credential in `flux-system` — **done**

The package is private: an anonymous `GET /v2/omar-massfih/rpg-system/tags/list`
returns 401, so image-reflector cannot even list tags without a credential.

`flux-system/ghcr` is a copy of the `platform/ghcr` pull secret the kubelet
already uses — copied namespace to namespace, so no new credential was minted.

That copy is the one loose end here: it is imperative, and nothing regenerates
it. If the ghcr PAT is ever rotated, the `ghcr_secret` Ansible role updates
`platform` and this copy silently goes stale — the symptom is an ImageRepository
that 401s while the node still pulls fine. Extending that role to both
namespaces is the proper fix.

### 3. Git write access for Flux — **done**

This is the part that is easy to assume and wrong here. The `platform`
GitRepository has **no `secretRef`** — it reads this public repo anonymously, so
Flux currently cannot write to git at all:

```bash
kubectl -n flux-system get gitrepository platform -o jsonpath='{.spec.secretRef}'   # empty
```

A `flux bootstrap` install would have created a deploy key; this one was
installed source-only. So image automation needs a credential added.

Prefer a **deploy key with write access** over a PAT — it is scoped to this one
repository, where a PAT carries whatever else it was granted:

```bash
flux create secret git platform-git \
  --url=ssh://git@github.com/omar-massfih/platform \
  --namespace=flux-system            # prints a public key; add it as a
                                     # deploy key on the repo, Allow write access
```

Then point the GitRepository at SSH and the secret. The object is not managed by
this repo (Flux was installed out of band), so this is an imperative patch:

```bash
kubectl -n flux-system patch gitrepository platform --type=merge -p \
  '{"spec":{"url":"ssh://git@github.com/omar-massfih/platform","secretRef":{"name":"platform-git"}}}'
```

Worth bringing the GitRepository and Kustomization into this repo afterwards, so
the thing that reconciles everything is not itself the one object nobody can see
the definition of.

## How it is wired

`- flux` in `../kustomization.yaml`'s `resources:`, and a marker comment on the
pin the automation owns:

```yaml
  - name: ghcr.io/omar-massfih/rpg-system
    newTag: "..." # {"$imagepolicy": "flux-system:rpg-system:tag"}
```

**The setter is `$imagepolicy`, all lowercase.** `$imagePolicy` appears in a lot
of older writing and in some Flux docs pages; the setter name is case-sensitive
and the camelCase spelling matches nothing. It does not error — the automation
reports `repository up-to-date` forever, with the policy resolved and the source
revision current, which looks exactly like success.

Editing that line by hand works until the next reconcile puts it back. To pin
deliberately — a rollback, say — suspend the automation first:

```bash
flux suspend image update platform      # or: kubectl -n flux-system annotate                                         # imageupdateautomation platform                                         # reconcile.fluxcd.io/suspend=true
```

## Checking it

```bash
kubectl -n flux-system get imagerepository,imagepolicy,imageupdateautomation
kubectl -n flux-system describe imagepolicy rpg-system     # .status.latestRef
```

An ImagePolicy with no `latestRef` means no tag matched the pattern — almost
always the tag format, not the credential. A 401 on the ImageRepository is the
credential.

## Adding another service

An `ImageRepository` + `ImagePolicy` pair here, and a marker comment on its pin.
The `ImageUpdateAutomation` is repo-wide and does not change. Note that the
service's build must emit an orderable tag for the policy to have anything to
sort — see the comment in `rpg-system.yaml`.

## Node headroom

The node is 2 CPU and was already at 1700m of requests. The two controllers ship
asking 100m each, which took it to exactly 2000m — 100% — and the next thing to
need a pod could not schedule. That surfaced as a *rolling update* failing:
a single-replica Deployment surges to two pods, and there was no room for the
second, so `rollout status` timed out with the old pod still serving.

Both are patched down to `cpu: 25m` (they are event-driven and idle between
scans) and to `maxSurge: 0`, so replacing them never needs two at once. That
leaves ~150m of headroom. Worth watching: at 92% requested, this cluster is one
modest addition away from the same failure, and the symptom points at the app
being rolled rather than at whatever consumed the margin.

## What is imperative here

These are not in git, and will revert if the controllers are reinstalled from
the release manifests:

- the `cpu: 25m` request and `maxSurge: 0` above,
- the images repointed from Docker Hub to ghcr,
- the `flux-images` Kustomization that applies this directory,
- the GitRepository's SSH url and `secretRef`.

The last two are the same gap the GitRepository and the `platform` Kustomization
already have — Flux was installed out of band, so the objects that reconcile
everything else are the ones with no definition in the repo. Bringing them in is
the obvious next tidy-up.
