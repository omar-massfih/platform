# terraform/

Provisions the OCI infrastructure that hosts the k3s cluster: VCN, public subnet,
internet gateway, route table, the `agentic-sl` security list (OpenVPN + ICMP +
HTTP/HTTPS; SSH is VPN-only), and the `VM.Standard.A1.Flex` (arm64, 2 OCPU / 12 GB,
47 GB boot) instance running Ubuntu 24.04.

Terraform stops at the VM. The **platform Ansible** (`../ansible/site.yml`) installs
k3s and everything above it; **Flux** then reconciles the workloads.

## Auth
Uses your `~/.oci/config` (same as the `oci` CLI). No keys in the repo.

## Adopt the existing box (current setup)
The live infra already exists, so `import.tf` maps the running resources into
Terraform state — you adopt them instead of creating duplicates:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in compartment_ocid etc.
terraform init
terraform plan     # imports run here; review drift carefully before applying
terraform apply    # only once the plan shows no destructive changes
```

Review the plan closely the first time — small attribute drift (e.g. the default
route table, image id) is expected. Once imported you can delete `import.tf`.

## Provision a fresh environment
Delete `import.tf`, set your own `compartment_ocid` / `availability_domain`, then:

```bash
terraform init && terraform apply
```

`terraform output public_ip` → set the `assistant.<domain>` DNS A record to it,
then run `cd ../ansible && ansible-playbook site.yml`.

## Notes
- Public SSH is off by default (`open_public_ssh = false`) — reach the box over the
  OpenVPN tunnel. Flip to `true` to open TCP 22 to the world.
- The OpenVPN server itself is configured on the host, not by this Terraform.
- State is local and git-ignored. For a shared setup, move it to an OCI Object
  Storage backend.
