# What the Makefile and the frontend build read: terraform output -raw <name>.

# --- auth ---
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  description = "The \"iss\" of every token; its signing keys are at <issuer>/.well-known/jwks.json"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_domain" {
  description = "Cognito's OAuth domain, which the frontend sends Google sign-in through"
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "Add this to the Google client's \"Authorized redirect URIs\""
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}

output "google_enabled" {
  value = local.has_google
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
