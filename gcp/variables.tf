variable "project_id" {
  type        = string
  description = "The Google Cloud project (permanent, globally unique)."
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names, and the project label."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

# --- database -----------------------------------------------------------------

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Shared core, 0.6 GB: the cheapest Cloud SQL tier ($0.0105/h while running)."
}

variable "db_running" {
  type        = bool
  default     = true
  description = <<-EOT
    false stops the instance (activation policy NEVER): no compute billed, the
    10 GB of storage still is. Cloud SQL does not pause on idle like Aurora.
  EOT
}

# --- API ----------------------------------------------------------------------

variable "cors_origins" {
  type        = list(string)
  default     = []
  description = "Origins that may call the API directly. Empty when the site reaches it through the Firebase /api rewrite (same origin)."
}

# Sign-in stays on AWS: the API checks access tokens of the eu-north-1 pool
# (infra/auth.tf), which it fetches the signing keys of from the internet.
variable "cognito_region" {
  type    = string
  default = "eu-north-1"
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_client_id" {
  type = string
}
