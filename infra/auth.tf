# Sign-in the site uses: the Cognito user pool in eu-north-1, created by hand in
# the console (Lab 4) and adopted by Terraform in Lab 7. Email + password, and
# Google. Two public clients: meetings-frontend-spa (the site) and the older
# meetings-frontend.

provider "aws" {
  alias  = "eu_north_1"
  region = var.cognito_region

  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
      ManagedBy    = "terraform"
    }
  }
}

resource "aws_cognito_user_pool" "site" {
  provider = aws.eu_north_1

  name = "User pool - uyman1"

  # A real pool with real users: AWS refuses to delete it while this is on.
  deletion_protection = "ACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"
  user_pool_tier           = "ESSENTIALS"

  username_configuration {
    case_sensitive = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }

  # Cognito's own mailer: free, but capped at 50 emails a day.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }
}

# https://eu-north-1l3w21svtg.auth.eu-north-1.amazoncognito.com
resource "aws_cognito_user_pool_domain" "site" {
  provider = aws.eu_north_1

  user_pool_id          = aws_cognito_user_pool.site.id
  domain                = "eu-north-1l3w21svtg"
  managed_login_version = 2
}

resource "aws_cognito_identity_provider" "google" {
  provider = aws.eu_north_1

  user_pool_id  = aws_cognito_user_pool.site.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "openid email profile"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    username       = "sub"
  }
}

# The site's client (NEXT_PUBLIC_COGNITO_CLIENT_ID): public, no secret,
# authorization code with PKCE.
resource "aws_cognito_user_pool_client" "site" {
  provider = aws.eu_north_1

  name         = "meetings-frontend-spa"
  user_pool_id = aws_cognito_user_pool.site.id

  enable_token_revocation = true
  refresh_token_validity  = 30

  supported_identity_providers         = ["COGNITO", aws_cognito_identity_provider.google.provider_name]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = var.site_urls
  logout_urls                          = var.site_urls
}

# The first client, from before the SPA one; kept as it is.
resource "aws_cognito_user_pool_client" "site_old" {
  provider = aws.eu_north_1

  name         = "meetings-frontend"
  user_pool_id = aws_cognito_user_pool.site.id

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 5

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  supported_identity_providers         = ["COGNITO", aws_cognito_identity_provider.google.provider_name]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = ["https://d1nzs10xorfo1q.cloudfront.net", "https://d1nzs10xorfo1q.cloudfront.net/"]
  logout_urls                          = ["https://d1nzs10xorfo1q.cloudfront.net", "https://d1nzs10xorfo1q.cloudfront.net/"]
}

# A version 2 domain has no sign-in page for a client until it has a style.
resource "aws_cognito_managed_login_branding" "site" {
  provider = aws.eu_north_1

  user_pool_id                = aws_cognito_user_pool.site.id
  client_id                   = aws_cognito_user_pool_client.site.id
  use_cognito_provided_values = true
}

resource "aws_cognito_managed_login_branding" "site_old" {
  provider = aws.eu_north_1

  user_pool_id                = aws_cognito_user_pool.site.id
  client_id                   = aws_cognito_user_pool_client.site_old.id
  use_cognito_provided_values = true
}
