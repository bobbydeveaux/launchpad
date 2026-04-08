# Operator Guide

This guide covers how to set up, manage, and operate a StackRamp platform environment.

## What is an Operator?

A StackRamp operator is someone who manages the shared cloud infrastructure that apps deploy to. Typically this is a senior engineer, platform team member, or the org admin.

Developers using StackRamp never need to be operators — they just write code and push.

## Setting Up a New Environment

### Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated as a project owner
- Terraform >= 1.5
- GitHub org or user account

### Bootstrap

```bash
cd providers/gcp/terraform/bootstrap

# Copy and fill in the example for your environment
cp dev.tfvars.example dev.tfvars
# edit dev.tfvars with your GCP project, region, GitHub org

./bootstrap.sh dev
```

The script will:
1. Check your `gcloud` auth and ADC
2. Create the GCS state bucket via `gsutil` (so Terraform uses remote state from run 1 — no local state ever)
3. Write `backend.tf` pointing at that bucket
4. Run `terraform init / plan / apply`
5. Print the GitHub Variables to set

The bootstrap creates:
- **Artifact Registry** (`stackramp-images`) — shared container registry
- **Service Account** (`stackramp-cicd-sa`) — used by all app deployments
- **Workload Identity Federation** (`stackramp-github-pool`) — secretless auth from GitHub Actions
- **IAM bindings** — Cloud Run, Firebase, Artifact Registry, Secret Manager, Cloud DNS permissions
- **GCS bucket** (`{project}-tf-state`) — Terraform state for bootstrap and all app deployments
- **Cloud DNS zone** — created if `base_domain` is set in tfvars

### Setting GitHub Variables

After bootstrap, set these as GitHub **Variables** (not secrets) at the org level:

```
STACKRAMP_PROVIDER=gcp
STACKRAMP_PROJECT=<your-gcp-project>
STACKRAMP_REGION=<your-region>
STACKRAMP_WIF_PROVIDER=<from terraform output>
STACKRAMP_SA_EMAIL=<from terraform output>
```

If you set a `base_domain`, also set:

```
STACKRAMP_BASE_DOMAIN=myapp.io
STACKRAMP_DNS_ZONE=myapp-io
```

The bootstrap script prints all of these values at the end. Setting them at the org level means all repos in the org can deploy automatically.

---

## Custom Domains

StackRamp supports two modes of custom domain assignment:

### Option A: Explicit domain (per app)

Set `domain:` in the app's `stackramp.yaml`:

```yaml
name: my-app
domain: myapp.io
```

### Option B: Auto-subdomains via BASE_DOMAIN (recommended for platforms)

Set `base_domain` in your bootstrap tfvars and `STACKRAMP_BASE_DOMAIN` + `STACKRAMP_DNS_ZONE` as GitHub Variables. Every app then automatically gets `{app-name}.{base_domain}` with no extra config in `stackramp.yaml`.

For example, with `STACKRAMP_BASE_DOMAIN=myorg.io`:
- `name: dashboard` → `dashboard.myorg.io`
- `name: api` → `api.myorg.io`

### How domain verification works automatically

Because Cloud DNS is fully authoritative (nameservers delegated to Google), StackRamp closes the Firebase domain verification loop entirely inside Terraform:

```
terraform apply (provision job)
  → creates google_firebase_hosting_custom_domain
  → Firebase generates required_dns_updates (TXT ownership proof + A records)
  → Terraform reads required_dns_updates
  → creates TXT record in Cloud DNS  ← Firebase polls this and auto-verifies
  → creates A record in Cloud DNS    ← traffic routed to Firebase CDN
```

No manual Firebase Console steps. No copy-pasting verification records.

> **Note on first deploys:** Firebase verification is asynchronous. On the very first deploy for a new domain, the TXT record gets written but Firebase may not have returned A records yet. The next push (or re-run) will add the A record once Firebase has verified. This is safe and handled automatically — `terraform apply` is idempotent.

### Nameserver delegation (one-time)

After bootstrap, point your domain registrar's nameservers at the values printed by the bootstrap script:

```
ns-cloud-c1.googledomains.com.
ns-cloud-c2.googledomains.com.
ns-cloud-c3.googledomains.com.
ns-cloud-c4.googledomains.com.
```

This is a one-time step. Once done, all subdomains are covered — new apps verify automatically without any further registrar interaction.

---

## Managing Apps

### How Apps Are Provisioned

When a developer pushes code with a `stackramp.yaml`, the platform:
1. Parses the config
2. Detects what changed (frontend/backend/both)
3. Provisions infra idempotently (safe to run multiple times)
4. Builds and deploys only what changed

### Naming Conventions

All resources follow a consistent naming scheme within the shared project:

| Resource | Pattern | Example |
|----------|---------|---------|
| Cloud Run service | `{app-name}-{env}` | `my-app-dev` |
| Firebase site | `{app-name}-{env}` | `my-app-dev` |
| Container image | `stackramp-images/{app-name}:{sha}` | `stackramp-images/my-app:abc1234` |
| TF state prefix | `{app-name}-{env}/` | `my-app-dev/` |

### Monitoring

- **Cloud Run**: GCP Console → Cloud Run → view services, logs, metrics
- **Firebase Hosting**: Firebase Console → Hosting → view sites, release history, custom domain status
- **Artifact Registry**: GCP Console → Artifact Registry → view images

---

## Multi-Environment Setup

> **Current limitation:** The platform currently uses a single set of GitHub Variables (`STACKRAMP_PROJECT`, `STACKRAMP_WIF_PROVIDER`, etc.) with no `_DEV` / `_PROD` suffix. This means both dev and prod app deployments target the same GCP project. This is fine for early-stage platforms but is a known gap — see the roadmap below.

### Current state (single platform project)

One `bootstrap.sh dev` run, one GCP project, one set of GitHub Variables. Both dev and prod *app* environments (`my-app-dev`, `my-app-prod`) are created inside the same GCP project. Resource isolation is by naming convention only.

This is the simplest setup and works well until you need billing separation, stricter IAM boundaries, or prod-grade reliability SLAs.

### Target state (separate platform projects per environment)

Each environment gets its own GCP project and its own bootstrap:

```bash
cd providers/gcp/terraform/bootstrap

# Dev platform
cp terraform.tfvars.example dev.tfvars   # edit with dev project
./bootstrap.sh dev

# Prod platform
cp terraform.tfvars.example prod.tfvars  # edit with prod project
./bootstrap.sh prod
```

The GitHub Variables would then be namespaced:

```
STACKRAMP_PROJECT_DEV       = my-platform-dev
STACKRAMP_PROJECT_PROD      = my-platform-prod
STACKRAMP_WIF_PROVIDER_DEV  = projects/.../providers/github-provider
STACKRAMP_WIF_PROVIDER_PROD = projects/.../providers/github-provider
STACKRAMP_SA_EMAIL_DEV      = stackramp-cicd-sa@my-platform-dev.iam...
STACKRAMP_SA_EMAIL_PROD     = stackramp-cicd-sa@my-platform-prod.iam...
```

And `platform.yml` would use `_DEV` vars for dev deployments and `_PROD` vars for prod deployments — proper isolation, separate billing, separate Cloud SQL instances.

**This is not yet implemented.** The platform workflow uses the unsuffixed variable names. Implementing it requires updating `platform.yml` to conditionally switch variable sets based on environment. Tracked as a future enhancement.

---

## Security Model

- **No GitHub secrets** — authentication uses OIDC/Workload Identity Federation
- **No long-lived credentials** — the GitHub Actions runner proves its identity cryptographically
- **Scoped access** — the WIF pool only trusts repos from your GitHub org/user
- **Shared service account** — one SA handles all deployments; per-app SA is a future enhancement
- **GitHub Variables are not secrets** — knowing them without a valid OIDC token gives no access

## Adding AWS Support (Future)

1. Implement `providers/aws/` following the [provider interface](../providers/interface.md)
2. Run `providers/aws/terraform/bootstrap/`
3. Set `STACKRAMP_PROVIDER=aws` in GitHub Variables
4. Apps deploy to AWS with zero changes to `stackramp.yaml`
