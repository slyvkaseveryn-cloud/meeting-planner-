variable "project_name" {
  type        = string
  description = "Prefix for resource names, and the PROJECT_NAME tag."
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "image_uri" {
  type        = string
  description = <<-EOT
    Backend image (repo@sha256:...) the report builder and the agenda parser
    are created with. New code is shipped by the Makefile, not by Terraform:
    both functions ignore later changes to it.
  EOT
}

variable "architecture" {
  type    = string
  default = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

# --- auth (Lab 4) -------------------------------------------------------------

variable "app_urls" {
  type        = list(string)
  description = <<-EOT
    Every URL the site is served from, each ending in "/": Cognito sends people
    back there after signing in with Google or signing out.
  EOT
}

variable "google_client_id" {
  type        = string
  default     = ""
  description = "OAuth client id of a Google \"Web application\" client. Empty leaves Google sign-in out."
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "That Google client's secret. Set it in the HCP Terraform workspace, never in a file."
}

# --- reports (Lab 5) ----------------------------------------------------------

variable "api_function_name" {
  type        = string
  description = "The API function (still CloudFormation). The report builder copies its DATABASE_URL."
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "The API function's subnets; the builder runs in the same ones."
}

variable "security_group_id" {
  type        = string
  description = "The API function's security group, which the database already admits."
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route tables of those subnets, for the S3 gateway endpoint."
}

variable "create_s3_endpoint" {
  type        = bool
  default     = true
  description = "false when the VPC already has an S3 gateway endpoint on these route tables."
}

variable "schedule_expression" {
  type        = string
  default     = "cron(0 7 ? * MON *)"
  description = "When the weekly report is requested. rate(5 minutes) for one test run, then back."
}

variable "sender_email" {
  type        = string
  description = "The From address; this configuration verifies it in SES."
}

variable "recipient_emails" {
  type        = string
  description = "Comma-separated recipients. In the SES sandbox each must be verified."
}

variable "sender_domain" {
  type        = string
  default     = ""
  description = "Optional domain to verify with DKIM. Empty verifies only sender_email."
}

variable "verify_recipient" {
  type        = bool
  default     = false
  description = "true also creates an SES identity for recipient_emails (a single address)."
}

variable "fail_week" {
  type        = string
  default     = ""
  description = "A week (e.g. 2026-W30) the builder fails on, to watch the DLQ. Empty in normal use."
}

# --- ai (Lab 6) ---------------------------------------------------------------

variable "parser_model" {
  type        = string
  default     = "us.anthropic.claude-opus-4-6-v1"
  description = "Bedrock model ID. Configuration, not code."
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins of the site that may call the parser."
}

variable "cognito_region" {
  type        = string
  description = "Region of the user pool the site signs in with (the parser checks its tokens)."
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_client_id" {
  type = string
}

variable "budget_email" {
  type        = string
  description = "Who gets the AWS Budgets alarm."
}

variable "budget_usd" {
  type    = number
  default = 5
}
