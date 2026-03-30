# PaaGA — Platform as a GitHub Action

> You commit code. The platform figures out the rest.

## The Problem

Every new BobbyJason project repeats the same ritual:
- Create a new GCP project (x3 — dev/uat/prod)
- Bootstrap Terraform state buckets
- Set up Workload Identity Federation for GitHub Actions
- Wire up Firebase Hosting
- Configure Artifact Registry
- Create Cloud Run service
- Copy 500 lines of workflow YAML and find/replace the project name

This is soul-destroying. PaaGA kills it.

---

## The Vision

A developer creates a repo with this structure:

```
my-app/
├── frontend/        ← React / Vite / whatever
├── backend/         ← Go / Python / Node API
└── paaga.yaml       ← all the config you'll ever need
```

`paaga.yaml` looks like:

```yaml
name: my-app
owner: bobbydeveaux

frontend:
  framework: react    # react | vue | next | static
  
backend:
  language: python    # python | go | node
  port: 8080
  
database: false       # false | postgres | mysql

platform:
  region: europe-west3
  billing_account: XXXXXX-XXXXXX-XXXXXX
  org_id: ""          # optional
```

Then in `.github/workflows/deploy.yml` — the **only** workflow file the developer writes:

```yaml
name: Deploy

on:
  push:
    branches: [main]
  pull_request:

jobs:
  deploy:
    uses: bobbydeveaux/paaga/.github/workflows/platform.yml@main
    secrets: inherit
```

That's it. The platform handles:
- ✅ Detecting what changed (frontend / backend / both)
- ✅ Building and testing
- ✅ Provisioning GCP infra (first time, idempotent after)
- ✅ Deploying Firebase Hosting (frontend)
- ✅ Deploying Cloud Run (backend)
- ✅ Wiring up secrets / env vars
- ✅ Optional: Cloud SQL, with creds injected automatically

---

## Architecture

### Phase 1 — POC (Let's build this now)

Shared infra lives in a **single GCP project** per environment:

```
bj-platform-dev
bj-platform-prod
```

Each app gets:
- Firebase Hosting → `<app-name>.web.app` (or custom subdomain)
- Cloud Run service → `<app-name>-api-<region>.run.app`
- Namespace isolation via naming convention

No per-app GCP projects. No per-app Terraform bootstrap.

Terraform runs **once** for the platform project itself (done). After that, each new app is just a Cloud Run service + Firebase site added to the existing project.

### Phase 2 — Shared Database

Single Cloud SQL instance per environment. Each app gets its own database + user. Credentials injected into Cloud Run via Secret Manager — the app just reads standard env vars:

```
DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
```

Developer never touches SQL, never knows the password.

### Phase 3 — K8s (future)

Migrate Cloud Run → shared GKE cluster. Each app gets its own namespace. RBAC per developer. Same `paaga.yaml` interface, different backend.

---

## Repository Structure

```
bobbydeveaux/paaga/
├── README.md                          ← this file
├── .github/
│   └── workflows/
│       ├── platform.yml               ← the reusable workflow (entry point)
│       ├── _detect-changes.yml        ← what changed?
│       ├── _build-frontend.yml        ← build + deploy Firebase Hosting
│       ├── _build-backend.yml         ← build + deploy Cloud Run
│       └── _provision-infra.yml       ← terraform plan/apply (idempotent)
├── terraform/
│   ├── bootstrap/                     ← one-time platform setup (per-env)
│   └── platform/                     ← per-app infra module (Cloud Run + Firebase site)
├── platform-action/                   ← composite action (reads paaga.yaml)
│   └── action.yml
└── docs/
    ├── getting-started.md
    ├── paaga-yaml-reference.md
    └── database-guide.md
```

---

## Getting Started (for a new app)

1. **One-time**: Platform admin runs bootstrap terraform for `bj-platform-dev` / `bj-platform-prod`
2. Developer creates a new repo
3. Adds `paaga.yaml` at root
4. Adds this to `.github/workflows/deploy.yml`:

```yaml
jobs:
  deploy:
    uses: bobbydeveaux/paaga/.github/workflows/platform.yml@main
    secrets: inherit
```

5. Pushes to `main` → platform detects it's a new app, provisions automatically, deploys

---

## vs "just copy fanvote"

| | Copy fanvote | PaaGA |
|---|---|---|
| New app setup time | ~2 hours | ~5 minutes |
| Files to copy/edit | ~15 workflow + TF files | 1 workflow file + paaga.yaml |
| Per-app GCP project | Yes (x3 = dev/uat/prod) | No — shared platform project |
| Terraform bootstrap per app | Yes | No |
| WIF setup per app | Yes | No — platform SA does it all |
| Works for toucanberry devs | No | Yes |

---

## Name

PaaGA = **P**latform **a**s **a** **G**itHub **A**ction

Alternative names considered:
- **Launchpad** — clean, implies "launch your app"
- **Runway** — you taxi, then take off
- **Plinth** — thing you put stuff on (very British)

Bobby's call 🙂

---

## Status

- [ ] POC scoping (this doc)
- [ ] Platform terraform bootstrap (`bj-platform-dev`)  
- [ ] Reusable workflow — frontend path (Firebase Hosting)
- [ ] Reusable workflow — backend path (Cloud Run)
- [ ] `paaga.yaml` schema + parser
- [ ] First example app wired up
- [ ] Database injection (Phase 2)
- [ ] Toucanberry pilot
