# platform

Infrastructure for the **omar** VM: single-node **k3s**, images on **ghcr.io**, and
**Ansible** to bootstrap the cluster and migrate every service off Docker
Compose / systemd into Kubernetes.

## What runs here

| Service | Exposure | Notes |
|---|---|---|
| agentic-assistent | **public** `https://assistant.omarmassfih.no` (Traefik + TLS) | FastAPI :8000. PVCs: memory (prod state), models. External Neon Postgres. |
| chatgpt-proxy | ClusterIP `chatgpt-proxy.platform.svc:8765` | OpenAI-compat proxy over Codex. Shares the codex-auth PVC. |
| chatgpt-browser | ClusterIP `chatgpt-browser.platform.svc:8766` | Headless-browser → OpenAI bridge (chromium). |
| pr-pilot | none (outbound Telegram + git) | Ships features to wakiru. State + workspace PVCs. |
| pr-pilot-omarmassfih | none | Same image, omarmassfih.no group config. |
| postgres (CNPG) | ClusterIP `pg-rw.platform.svc:5432` | CloudNativePG `Cluster`, single instance. Read/write store for the ingest/dlt pipelines. Auto-generated creds in Secret `pg-app`, DB `ingest`. |
| ingest | none (Deployment) | dlt orchestrator from the `ingest` repo → Postgres; schedules live in its source YAMLs. Creds injected from `pg-app`. Image tag auto-bumped here by the ingest repo's build-push CI. |
| omarmassfih-backend | **public** `https://backend.omarmassfih.no` (Traefik + TLS) | Notes and chat API. Authored notes and local FastEmbed vectors are synchronized into cluster-local Postgres before rollout; embeddings refresh hourly without Vercel. |
| rpg-system | **public** `https://rpg.omarmassfih.no` (Traefik + TLS) | Rank tracker from the `rpg-system` repo; API + static UI in one image. Own CNPG database `rpg`. Image tag to be bumped here by Flux image automation — see `k8s/flux/`. BasicAuth middleware ships disabled — see that app's `ingress.yaml`. |

All apps run in namespace `platform`. Agentic-assistent and omarmassfih-backend
have public HTTP APIs. The proxy, browser and both pr-pilot bots stay
cluster-internal. Postgres is a cluster-internal data store (CloudNativePG); its
operator lives in `cnpg-system`, the DB itself in `platform`.

## How a change reaches the node

**Flux**, in `flux-system`, watches this repo's `main` branch and applies `./k8s`
with `prune: true` — a one-minute poll on the git source, ten minutes on the
kustomization. Nothing here is deployed by pushing to the cluster; it is deployed
by merging to `main`.

So the whole path for a service change is:

```
service repo push → build-push CI → ghcr image
                                  → `newTag` bumped here (by that repo's CI, or by
                                     Flux image automation — see k8s/flux/)
                                  → Flux → rolling update
```

`ansible/playbooks/50-apps.yml` does the same apply by hand. It is the bootstrap
and the break-glass, not the everyday route — and reaching for `kubectl set image`
directly only creates drift that Flux will undo on its next reconcile.

## Layout

```
ansible/    inventory, group_vars, site.yml, playbooks 00–99, roles
k8s/        kustomize: platform/ (ns, codex-auth PVC, CNPG postgres) + apps/<svc>/
ci-templates/build-push.yml   arm64 → ghcr workflow to drop into each service repo
dockerfiles/                  reference Dockerfiles for services that lack one
scripts/push-from-vm.sh       build+push from the arm64 VM (no-GitHub services)
secrets/                      git-ignored env/creds + *.example templates
```

## One-time prerequisites

1. **Local tools:** `ansible`, `kubectl`, `kustomize`, the `kubernetes.core` collection
   (`ansible-galaxy collection install kubernetes.core`). VPN up so `ssh omar` works.
2. **Secrets** (`secrets/`, git-ignored — see `secrets/README.md`): copy each
   `*.example` and fill in. Also drop in `codex-auth.json` (copy of the VM's
   `~/.codex/auth.json`) and `ghcr.pat` (a PAT with `read:packages`).
3. **Images:** add `ci-templates/build-push.yml` to `agentic-assistent` (wakiru) and
   `pr-pilot` repos (edit `IMAGE` per repo). For `chatgpt-proxy` / `chatgpt-browser`
   (no GitHub remote) either create repos or build from the VM:
   `./scripts/push-from-vm.sh chatgpt-proxy '~/chatgpt-openai-proxy' dockerfiles/chatgpt-proxy.Dockerfile`
   The **ingest** repo carries its own `build-push.yml` (arm64 → ghcr) that also
   bumps its image pin here on each push — it needs a `PLATFORM_PAT` secret
   (contents:write on this repo) set in *that* repo.

   **rpg-system** is moving to the other arrangement: its CI only builds, and
   Flux watches ghcr and writes the pin here itself, so no service repo needs a
   credential on this one. See `k8s/flux/README.md` — the manifests are written
   but not yet wired in, and three prerequisites are listed there.
4. **DNS + firewall (for public TLS):** A records for `assistant.omarmassfih.no`
   and `backend.omarmassfih.no` → VM public IP, and open **80/443** in ufw **and**
   the OCI security list (needed for the Let's Encrypt HTTP-01 challenge).

## Bootstrap

```bash
cd ansible
ansible-playbook site.yml            # 00-prereqs → 10-k3s → 20-platform → 30-secrets → 40-migrate → 50-apps
# or stage by stage:
ansible-playbook site.yml --tags prereqs,k3s
ansible-playbook site.yml --tags platform,secrets
ansible-playbook site.yml --tags migrate,apps
```

`00-prereqs` prunes ~24 GB of Docker build cache first (the disk is otherwise 85%
full) and asserts ≥15 GB free before continuing. The k3s role fetches a kubeconfig
to `ansible/kubeconfig` (server URL rewritten to the VPN address) for local `kubectl`.

## Data migration (do not skip — live prod state)

`40-data-migrate.yml` seeds local-path PVCs from existing VM directories:
`agentic-assistent/memory` (**live** — overwriting re-fires the daily briefing and
wipes follow-ups), `agentic-assistent/models`, `~/.pr-pilot*`, `~/wakiru`,
`~/omarmassfih-ws`. It copies **only into empty PVC dirs**, so it's safe to re-run.

Because local-path provisions a PV lazily on first pod bind, the copy may report
`SKIP-no-pv` on a fresh cluster. In that case: run `50-apps`, then
`kubectl -n platform scale deploy --all --replicas=0`, re-run `40-data-migrate`,
then scale back up. `codex-auth` is seeded separately by the `pvc_seed` role (a
one-shot Job) — writable, so Codex can rotate its token in place.

## Verify

```bash
export KUBECONFIG=ansible/kubeconfig
kubectl get nodes                                   # Ready
kubectl -n platform get pods                        # all Running/Ready
curl https://assistant.omarmassfih.no/health        # 200, valid LE cert
curl https://backend.omarmassfih.no/db-health       # 200, cluster-local Postgres
kubectl -n platform exec deploy/pr-pilot -- \
  curl -s http://chatgpt-proxy.platform.svc:8765/v1/models   # 200 in-cluster
```
Confirm agentic memory is intact (notes/tasks present, briefing did **not** re-fire),
both Telegram bots respond, and a pr-pilot run reaches the proxy and opens a PR.

## Cutover

Only after everything is verified healthy in k3s:

```bash
ansible-playbook playbooks/99-decommission.yml --tags decommission
```

Stops the old Compose stack + the four systemd `--user` units and does a final
docker prune. Old files are left in place for a rollback window — to roll back,
`docker compose up -d` in `~/agentic-assistent` and `systemctl --user enable --now`
the units, and scale the k3s deployments to 0.

## Notes / assumptions to confirm

- `chatgpt-browser` listen port is assumed **8766**; confirm against `browser_backend.py`.
- pr-pilot's in-image `opencode.json` must point at `http://chatgpt-proxy.platform.svc:8765/v1`
  (replacing the old `127.0.0.1:8765`), and its config toml + gh/git creds ship via
  the `pr-pilot*` Secrets.
- k3s version, ghcr org, image tags and the public domain live in
  `ansible/group_vars/all.yml`; the ingress host is also in
  `k8s/apps/agentic-assistent/ingress.yaml` — keep them in sync.
