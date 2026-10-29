# Adopt what the three CloudFormation stacks created. Delete this file after
# the first apply.

# --- auth ---
import {
  to = aws_cognito_user_pool.main
  id = "us-east-1_Z8TDQbL9f"
}
import {
  to = aws_cognito_user_pool_domain.main
  id = "spry-severyn-637965527585"
}
import {
  to = aws_cognito_user_pool_client.web
  id = "us-east-1_Z8TDQbL9f/49s1e3a98jsd241baglo5mqthk"
}
import {
  to = aws_cognito_managed_login_branding.web
  id = "us-east-1_Z8TDQbL9f,aff0e4de-9c0f-4666-b5c5-1ac645c21305"
}

# --- reports ---
import {
  to = aws_s3_bucket.reports
  id = "spry-severyn-reports-637965527585"
}
import {
  to = aws_s3_bucket_public_access_block.reports
  id = "spry-severyn-reports-637965527585"
}
import {
  to = aws_s3_bucket_server_side_encryption_configuration.reports
  id = "spry-severyn-reports-637965527585"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "spry-severyn-reports-637965527585"
}
import {
  to = aws_s3_bucket_notification.reports
  id = "spry-severyn-reports-637965527585"
}
import {
  to = aws_vpc_endpoint.s3[0]
  id = "vpce-047fb6029857d2487"
}
import {
  to = aws_sqs_queue.dlq
  id = "https://sqs.us-east-1.amazonaws.com/637965527585/spry-severyn-report-requests-dlq"
}
import {
  to = aws_sqs_queue.requests
  id = "https://sqs.us-east-1.amazonaws.com/637965527585/spry-severyn-report-requests"
}
import {
  to = aws_iam_role.builder
  id = "spry-severyn-reports-BuilderRole-n50wtalXBLNP"
}
import {
  to = aws_iam_role_policy_attachment.builder["arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"]
  id = "spry-severyn-reports-BuilderRole-n50wtalXBLNP/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
import {
  to = aws_iam_role_policy_attachment.builder["arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"]
  id = "spry-severyn-reports-BuilderRole-n50wtalXBLNP/arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}
import {
  to = aws_iam_role_policy.builder
  id = "spry-severyn-reports-BuilderRole-n50wtalXBLNP:write-reports"
}
import {
  to = aws_cloudwatch_log_group.builder
  id = "/aws/lambda/spry-severyn-report-builder"
}
import {
  to = aws_lambda_function.builder
  id = "spry-severyn-report-builder"
}
import {
  to = aws_lambda_event_source_mapping.builder
  id = "137ea3f1-b9aa-4a7a-97c6-92e15c7ee3f3"
}
import {
  to = aws_iam_role.scheduler
  id = "spry-severyn-reports-SchedulerRole-Sjz36Y2a5HFL"
}
import {
  to = aws_iam_role_policy.scheduler
  id = "spry-severyn-reports-SchedulerRole-Sjz36Y2a5HFL:send-report-request"
}
import {
  to = aws_scheduler_schedule.weekly
  id = "default/spry-severyn-weekly-report"
}
import {
  to = aws_iam_role.mailer
  id = "spry-severyn-reports-MailerRole-LM6WBHX2rt0i"
}
import {
  to = aws_iam_role_policy_attachment.mailer
  id = "spry-severyn-reports-MailerRole-LM6WBHX2rt0i/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.mailer
  id = "spry-severyn-reports-MailerRole-LM6WBHX2rt0i:read-and-send"
}
import {
  to = aws_cloudwatch_log_group.mailer
  id = "/aws/lambda/spry-severyn-report-mailer"
}
import {
  to = aws_lambda_function.mailer
  id = "spry-severyn-report-mailer"
}
import {
  to = aws_lambda_permission.mailer_s3
  id = "spry-severyn-report-mailer/spry-severyn-reports-MailerInvokePermission-Lp4YPd9BBrLj"
}
import {
  to = aws_sesv2_email_identity.sender
  id = "slyvkaseveryn@gmail.com"
}

# --- ai ---
import {
  to = aws_iam_role.parser
  id = "spry-severyn-ai-ParserRole-ZftFnR6tTLMp"
}
import {
  to = aws_iam_role_policy_attachment.parser
  id = "spry-severyn-ai-ParserRole-ZftFnR6tTLMp/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.parser
  id = "spry-severyn-ai-ParserRole-ZftFnR6tTLMp:call-claude"
}
import {
  to = aws_cloudwatch_log_group.parser
  id = "/aws/lambda/spry-severyn-agenda-parser"
}
import {
  to = aws_lambda_function.parser
  id = "spry-severyn-agenda-parser"
}
import {
  to = aws_lambda_function_url.parser
  id = "spry-severyn-agenda-parser"
}
import {
  to = aws_lambda_permission.parser_url
  id = "spry-severyn-agenda-parser/spry-severyn-ai-ParserUrlPermission-0SInJVOE7bub"
}
import {
  to = aws_lambda_permission.parser_url_invoke
  id = "spry-severyn-agenda-parser/spry-severyn-ai-ParserUrlInvokePermission-tBMowSfG9MiN"
}
import {
  to = aws_budgets_budget.monthly
  id = "637965527585:spry-severyn-monthly"
}
