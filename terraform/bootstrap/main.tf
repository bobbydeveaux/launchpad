# PaaGA Platform Bootstrap
# Run ONCE per environment (dev / prod) to set up the shared platform project.
# After this, individual apps require NO terraform — they just push code.

locals {
  platform_project = var.platform_project  # e.g. bj-platform-dev
  region           = "europe-west3"
}

provider "google" {
  project = local.platform_project
  region  = local.region
}

# ── APIs ──────────────────────────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# ── Artifact Registry ─────────────────────────────────────────────────────────
# All apps share one registry: paaga-images/<app-name>:<sha>

resource "google_artifact_registry_repository" "paaga_images" {
  location      = local.region
  repository_id = "paaga-images"
  format        = "DOCKER"
  description   = "PaaGA shared container registry"
  depends_on    = [google_project_service.apis]
}

# ── Platform CI/CD Service Account ───────────────────────────────────────────
# This SA is used by ALL apps' GitHub Actions — no per-app SA needed

resource "google_service_account" "platform_cicd" {
  account_id   = "platform-cicd-sa"
  display_name = "PaaGA Platform CI/CD"
  description  = "Shared SA for all app deployments via GitHub Actions"
}

resource "google_project_iam_member" "platform_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.admin",
    "roles/firebase.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountUser",
    "roles/cloudsql.admin",
  ])

  project = local.platform_project
  role    = each.value
  member  = "serviceAccount:${google_service_account.platform_cicd.email}"
}

# ── Workload Identity Federation ──────────────────────────────────────────────
# ONE pool for the whole platform — all repos in the org can use it

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Allow any repo owned by the configured GitHub owner
  attribute_condition = "attribute.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Bind platform SA to the WIF pool (all repos in org can assume it)
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.platform_cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_owner/${var.github_owner}"
}

# ── Terraform State Bucket ────────────────────────────────────────────────────

resource "google_storage_bucket" "tf_state" {
  name          = "${local.platform_project}-tf-state"
  location      = local.region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}

# ── Cloud SQL (Phase 2 — shared DB instance) ──────────────────────────────────
# Uncomment when you're ready to add database support

# resource "google_sql_database_instance" "platform" {
#   name             = "platform-db"
#   database_version = "POSTGRES_15"
#   region           = local.region
#
#   settings {
#     tier      = "db-f1-micro"
#     edition   = "ENTERPRISE"
#
#     backup_configuration {
#       enabled = true
#     }
#   }
# }
