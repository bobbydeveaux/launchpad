output "frontend_url" {
  description = "Frontend URL — custom domain if configured, otherwise Firebase .web.app URL"
  value       = var.custom_domain != "" ? "https://${var.custom_domain}" : "https://${google_firebase_hosting_site.app.site_id}.web.app"
}

output "backend_url" {
  description = "Backend Cloud Run URI"
  value       = google_cloud_run_v2_service.app.uri
}
