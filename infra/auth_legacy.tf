# The pool infra/auth.yml created in us-east-1 (Lab 4). The site signs in with
# the eu-north-1 pool in auth.tf instead; this one is kept, managed, until it is
# decided whether its one user moves over (docs/adr/0007-terraform.md).

resource "aws_cognito_user_pool" "legacy" {
  name = "${var.project_name}-users"

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

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  user_pool_tier = "ESSENTIALS"

  admin_create_user_config {
    allow_admin_create_user_only = false
  }
}

resource "aws_cognito_user_pool_domain" "legacy" {
  user_pool_id = aws_cognito_user_pool.legacy.id
  # Domain prefixes are unique per region across all accounts.
  domain                = "${var.project_name}-${local.account_id}"
  managed_login_version = 2
}

# Public client: no secret (generate_secret unset, i.e. false), SRP for
# passwords, and the authorization-code flow with PKCE.
resource "aws_cognito_user_pool_client" "legacy" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.legacy.id

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity = 1
  id_token_validity     = 1
  # Hours, hours and days: the default token_validity_units, which the
  # provider does not read back, so the block is left out.
  refresh_token_validity = 30

  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.app_urls
  logout_urls                          = var.app_urls
}

resource "aws_cognito_managed_login_branding" "legacy" {
  user_pool_id                = aws_cognito_user_pool.legacy.id
  client_id                   = aws_cognito_user_pool_client.legacy.id
  use_cognito_provided_values = true
}

# Renamed from main/web when auth.tf started describing the eu-north-1 pool.
moved {
  from = aws_cognito_user_pool.main
  to   = aws_cognito_user_pool.legacy
}

moved {
  from = aws_cognito_user_pool_domain.main
  to   = aws_cognito_user_pool_domain.legacy
}

moved {
  from = aws_cognito_user_pool_client.web
  to   = aws_cognito_user_pool_client.legacy
}

moved {
  from = aws_cognito_managed_login_branding.web
  to   = aws_cognito_managed_login_branding.legacy
}
