output "platform_cicd_sa_email" {
  description = "Set this as PLATFORM_SA_DEV or PLATFORM_SA_PROD in GitHub Secrets"
  value       = google_service_account.platform_cicd.email
}

output "wif_provider" {
  description = "Set this as PLATFORM_WIF_DEV or PLATFORM_WIF_PROD in GitHub Secrets"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "artifact_registry_url" {
  description = "Docker registry URL for images"
  value       = "${google_artifact_registry_repository.paaga_images.location}-docker.pkg.dev/${var.platform_project}/${google_artifact_registry_repository.paaga_images.repository_id}"
}
