# secrets/

Real secret material lives here at bootstrap time but is **git-ignored** — only the
`*.example` templates are committed. The Ansible `app_secrets` / `ghcr_secret` /
`pvc_seed` roles read these files and create the corresponding Kubernetes objects.

| File (git-ignored)              | Becomes                                             |
|---------------------------------|-----------------------------------------------------|
| `agentic-assistent.env`         | Secret `agentic-assistent` (API_TOKEN, DATABASE_URL, tokens) |
| `pr-pilot.env`                  | Secret `pr-pilot`                                   |
| `pr-pilot-omarmassfih.env`      | Secret `pr-pilot-omarmassfih`                       |
| `codex-auth.json`               | Secret `codex-auth` → seeded into the writable `codex-auth` PVC |
| `ghcr.pat`                      | Secret `ghcr` (dockerconfigjson imagePullSecret)    |

`codex-auth.json` is a copy of the VM's `~/.codex/auth.json`. It is **seeded once**
into a writable PVC (not mounted read-only) because Codex rotates the refresh token
in place — a read-only Secret mount would break token refresh.
