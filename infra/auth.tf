# Sign-in (Lab 4): a Cognito user pool where people sign up with their email
# and a password, optionally federated with Google, plus the public app client
# the Next.js frontend signs in through.

locals {
  has_google = var.google_client_id != ""
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # People sign in with their email address; Cognito mails them a code to
  # confirm it on sign-up and to reset a forgotten password.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Cognito's own mailer: free, but capped at 50 emails a day.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Managed login (the hosted sign-in page) needs Essentials; the first
  # 10,000 monthly active users are free.
  user_pool_tier = "ESSENTIALS"

  admin_create_user_config {
    allow_admin_create_user_only = false
  }
}

# Hosts the OAuth endpoints Google sign-in goes through:
# https://<prefix>.auth.<region>.amazoncognito.com
resource "aws_cognito_user_pool_domain" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  # Domain prefixes are unique per region across all accounts.
  domain                = "${var.project_name}-${local.account_id}"
  managed_login_version = 2
}

resource "aws_cognito_identity_provider" "google" {
  count = local.has_google ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
  }
}

# Public client for the browser: no secret (generate_secret unset, i.e.
# false), SRP for passwords (the password never leaves the browser), and the
# authorization-code flow with PKCE for Google.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity = 1
  id_token_validity     = 1
  # Hours, hours and days: the default token_validity_units, which the
  # provider does not read back, so the block is left out.
  refresh_token_validity = 30

  supported_identity_providers = concat(["COGNITO"], aws_cognito_identity_provider.google[*].provider_name)

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.app_urls
  logout_urls                          = var.app_urls
}

# A version 2 domain has no sign-in page until it has a branding style.
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = true
}
