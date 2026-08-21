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

**These manifests are not live yet.** `../kustomization.yaml` does not list this
directory, on purpose: kustomize-controller fails the *entire* build when a
resource has no matching kind, which would stop every app in this repo from
reconciling, not just this one. The CRDs exist now (prerequisite 1 below), but
the two credentials do not, and an automation that cannot push is a
CRD-shaped way of finding that out. Wire it in last.

Prerequisite 1 is done. **2 and 3 are credentials, and both are outstanding.**

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

### 2. A registry credential in `flux-system` — outstanding

The package is private: an anonymous `GET /v2/omar-massfih/rpg-system/tags/list`
returns 401. The `ghcr` pull secret exists in `platform` for the kubelet;
image-reflector needs its own copy in `flux-system`. The `ghcr_secret` Ansible
role creates the first one from `secrets/ghcr.pat` — extend it to both
namespaces rather than copying the secret by hand.

### 3. Git write access for Flux — outstanding

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

## Enabling

Once 2 and 3 are done, two edits:

1. Add `- flux` to `resources:` in `../kustomization.yaml`.
2. Put the marker comment on the pin the automation should own:

```yaml
  - name: ghcr.io/omar-massfih/rpg-system
    newTag: "20260821203300-7707621" # {"$imagePolicy": "flux-system:rpg-system:tag"}
```

The tag has to be one the policy matches — `<14-digit UTC timestamp>-<short
sha>`. Builds from before the workflow change only carry `sha-` tags, which the
policy filters out, so the first automated bump lands on the next push.

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
