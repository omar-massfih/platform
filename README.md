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

All five run in namespace `platform`. Only agentic-assistent has an inbound HTTP
API, so it's the only one with a public ingress. The proxy, browser and both
pr-pilot bots stay cluster-internal.

## Layout

```
ansible/    inventory, group_vars, site.yml, playbooks 00–99, roles
k8s/        kustomize: platform/ (ns, codex-auth PVC) + apps/<svc>/
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
4. **DNS + firewall (for public TLS):** A record `assistant.omarmassfih.no` → VM public
   IP, and open **80/443** in ufw **and** the OCI security list (needed for the
   Let's Encrypt HTTP-01 challenge).

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
