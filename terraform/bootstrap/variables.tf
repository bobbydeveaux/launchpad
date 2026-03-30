variable "platform_project" {
  description = "GCP project ID for the shared platform (e.g. bj-platform-dev)"
  type        = string
}

variable "github_owner" {
  description = "GitHub org or username that owns repos deploying to this platform"
  type        = string
  default     = "bobbydeveaux"
}

variable "billing_account" {
  description = "GCP billing account ID"
  type        = string
  default     = ""
}
