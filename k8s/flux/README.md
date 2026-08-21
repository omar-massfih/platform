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
directory, on purpose: the CRDs below are not installed on the cluster, and
kustomize-controller fails the *entire* build when a resource has no matching
kind — which would stop every app in this repo from reconciling, not just this
one. Wire it in as the last step, after the three prerequisites.

## Prerequisites

### 1. The two controllers

A stock `flux install` ships source, kustomize, helm and notification. Image
automation is two extra controllers, and this cluster does not have them:

```bash
kubectl get deploy -n flux-system     # expect only the four
```

Install the pair at the version matching what is already running — the cluster
is on Flux v2.9.4 (source-controller v1.9.3), where all three image kinds are
`image.toolkit.fluxcd.io/v1`, not the `v1beta2` most blog posts show:

```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.9.4/install.yaml
```

That bundle reconciles all six controllers to v2.9.4. It is a no-op for the four
already at that version — check first with `kubectl -n flux-system get deploy -o
wide`, and if they have drifted, decide about the upgrade before running it
rather than as a side effect of wanting image automation.

### 2. A registry credential in `flux-system`

The package is private: an anonymous `GET /v2/omar-massfih/rpg-system/tags/list`
returns 401. The `ghcr` pull secret exists in `platform` for the kubelet;
image-reflector needs its own copy in `flux-system`. The `ghcr_secret` Ansible
role creates the first one from `secrets/ghcr.pat` — extend it to both
namespaces rather than copying the secret by hand.

### 3. Git write access for Flux

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

Once all three are done, two edits:

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
