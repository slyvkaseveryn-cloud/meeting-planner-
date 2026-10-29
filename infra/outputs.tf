# What the Makefile and the frontend build read: terraform output -raw <name>.

# --- auth (the eu-north-1 pool the site signs in with) ---
output "cognito_region" {
  value = var.cognito_region
}

output "user_pool_id" {
  value = aws_cognito_user_pool.site.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.site.id
}

output "issuer" {
  description = "The \"iss\" of every token; its signing keys are at <issuer>/.well-known/jwks.json"
  value       = "https://cognito-idp.${var.cognito_region}.amazonaws.com/${aws_cognito_user_pool.site.id}"
}

output "hosted_domain" {
  description = "Cognito's OAuth domain, which the frontend sends Google sign-in through"
  value       = "${aws_cognito_user_pool_domain.site.domain}.auth.${var.cognito_region}.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "Must be in the Google client's \"Authorized redirect URIs\""
  value       = "https://${aws_cognito_user_pool_domain.site.domain}.auth.${var.cognito_region}.amazoncognito.com/oauth2/idpresponse"
}

output "google_enabled" {
  value = true
}

output "legacy_user_pool_id" {
  description = "The us-east-1 pool from auth.yml, not used by the site"
  value       = aws_cognito_user_pool.legacy.id
}

# --- reports ---
output "reports_bucket" {
  value = aws_s3_bucket.reports.id
}

output "queue_url" {
  value = aws_sqs_queue.requests.url
}

output "dead_letter_queue_url" {
  value = aws_sqs_queue.dlq.url
}

output "builder_function" {
  value = aws_lambda_function.builder.function_name
}

output "mailer_function" {
  value = aws_lambda_function.mailer.function_name
}

output "dkim_records" {
  description = "Add these three as CNAME records at your DNS provider"
  value = [
    for t in try(aws_sesv2_email_identity.domain[0].dkim_signing_attributes[0].tokens, []) :
    "${t}._domainkey.${var.sender_domain} CNAME ${t}.dkim.amazonses.com"
  ]
}

# --- ai ---
output "parser_url" {
  description = "NEXT_PUBLIC_PARSER_URL for the frontend build"
  value       = aws_lambda_function_url.parser.function_url
}

output "parser_function" {
  value = aws_lambda_function.parser.function_name
}
