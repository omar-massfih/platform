# platform

Infrastructure for the omar VM, running single-node k3s. The frontend at
https://omarmassfih.no is hosted separately (GitHub Pages behind Cloudflare).

## Retained services

| Service | Purpose |
|---|---|
| omarmassfih-backend | Notes/chat API at https://backend.omarmassfih.no; hourly embedding refresh |
| rpg-system | RPG at https://rpg.omarmassfih.no |
| keycloak | Identity provider at https://auth.omarmassfih.no |
| oauth2-proxy | Authenticated gateway between RPG ingress and the RPG service |
| pg | Shared CloudNativePG Postgres for backend, RPG and Keycloak |

Keep k3s, Traefik, cert-manager, CloudNativePG, Flux, DNS, storage and VPN access:
these support the retained applications. The backend uses `pg-app` and the
existing database/role named `ingest`; that name does not mean the ingestion
service is still required. Do not rename or recreate the database during cleanup.

## Deployment

Flux watches `main` and reconciles `k8s/` with pruning enabled. Merging or pushing
a change to `main` deploys it and removes resources no longer declared there.
RPG image automation is reconciled separately from `k8s/flux/` by `flux-images`.
The backend image pin is updated by its service CI.

```bash
kubectl kustomize k8s
kubectl kustomize k8s/flux
```

## Layout and bootstrap

- `terraform/`: OCI VM and network provisioning.
- `ansible/`: k3s, disk guard, TLS, Postgres operator, image credentials and apps.
- `k8s/apps/`: backend, RPG, Keycloak and its authentication proxy.
- `k8s/platform/`: namespace and shared Postgres cluster.
- `k8s/retained-data/`: offline storage from retired services.
- `k8s/flux/`: RPG image automation.
- `secrets/`: optional backend credential template and credential instructions.

Ansible requires Ansible, kubectl, kustomize and the `kubernetes.core` collection
on the controller. Connect through the VPN using `ssh omar@10.8.0.1` (or configure
an `omar` SSH alias). Inventory uses normal SSH identity discovery.

```bash
cd ansible
ansible-playbook site.yml
# Individual stages:
ansible-playbook site.yml --tags platform,secrets,apps
```

Existing Keycloak and oauth2-proxy credentials are managed out of band; see
`secrets/README.md`. A fresh install needs those credentials provisioned first.
The manual apps playbook applies resources but does not prune retired workloads;
use Flux for the cleanup deployment.

## Retired services and retained data

Agentic assistant, ChatGPT proxy/browser, both PR bots, ingestion/webserver and
Garage are retired. Their deployment manifests, build helpers, secret templates
and migration bootstrap tasks have been removed.

The eight existing PVCs and Dagster database declaration remain under
`k8s/retained-data/` with Flux pruning disabled. They run no application workloads.
The shared Postgres database, old VM source directories and existing secrets are
preserved. This is service cleanup, not permanent erasure of historical data.
Reclaiming those volumes or database contents requires a separate backup and
explicit data deletion decision. Git history retains the old service manifests.

## Verify

```bash
ssh omar@10.8.0.1 'sudo k3s kubectl -n platform get deployments,pods,cronjobs,pvc'
curl --fail https://omarmassfih.no/
curl --fail https://backend.omarmassfih.no/db-health
curl --head https://rpg.omarmassfih.no/  # unauthenticated request redirects to login
curl --fail https://auth.omarmassfih.no/realms/platform/.well-known/openid-configuration
```

The only application deployments should be `omarmassfih-backend`, `rpg-system`,
`keycloak` and `oauth2-proxy`, plus the CNPG-managed Postgres pod. Flux and cluster
operators remain in their own namespaces.
