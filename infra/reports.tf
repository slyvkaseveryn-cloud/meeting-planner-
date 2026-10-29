# The weekly meetings report, built by events (Lab 5). EventBridge Scheduler
# (every Monday 07:00 Kyiv) and `make report-now` put a message on an SQS
# queue; the report-builder Lambda (backend image, in the VPC) reads Aurora and
# writes reports/<week>.csv to S3 through a gateway endpoint; the ObjectCreated
# event starts the report-mailer Lambda (outside the VPC), which emails the CSV
# through SES.

locals {
  reports_bucket = "${var.project_name}-reports-${local.account_id}"
}

# The API stack is still CloudFormation; the builder uses the same database.
data "aws_lambda_function" "api" {
  function_name = var.api_function_name
}

# --- storage ------------------------------------------------------------------

# In CloudFormation the bucket, the mailer's permission and the notification
# formed a cycle, broken with a constructed bucket name. Here they are three
# resources, and the references order them.
resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-reports"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_s3]
}

# The builder has no NAT; without this its PutObject hangs until the timeout.
resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_endpoint ? 1 : 0

  vpc_endpoint_type = "Gateway"
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = var.route_table_ids
}

# --- queue --------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600 # 14 days, the most SQS keeps
  max_message_size          = 1048576 # 1 MiB, SQS's default since 2025
}

resource "aws_sqs_queue" "requests" {
  name = "${var.project_name}-report-requests"
  # 6 x the builder's 60 s timeout: a message must not reappear while the
  # first attempt is still running, or a second builder starts on it.
  visibility_timeout_seconds = 360
  max_message_size           = 1048576

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# --- builder (in the VPC) -----------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Role names are the ones CloudFormation generated: renaming a role replaces it.
resource "aws_iam_role" "builder" {
  name               = "${var.project_name}-reports-BuilderRole-n50wtalXBLNP"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "builder" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole",
  ])

  role       = aws_iam_role.builder.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "builder" {
  name = "write-reports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.reports.arn}/reports/*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = 14
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds reports/<week>.csv from Aurora (backend image, other handler)"
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = [var.architecture]
  role          = aws_iam_role.builder.arn
  memory_size   = 512
  # Aurora may need ~15 s to resume from a pause.
  timeout = 60

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.builder.name
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      DATABASE_URL     = sensitive(data.aws_lambda_function.api.environment[0].variables["DATABASE_URL"])
      APP_TIMEZONE     = var.app_timezone
      REPORTS_BUCKET   = aws_s3_bucket.reports.id
      REPORT_FAIL_WEEK = var.fail_week
    }
  }

  # Code ships through the Makefile (update-function-code), not Terraform.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Lambda polls the queue for the function, so a VPC without NAT is fine.
resource "aws_lambda_event_source_mapping" "builder" {
  event_source_arn = aws_sqs_queue.requests.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
}

# --- schedule -----------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-reports-SchedulerRole-Sjz36Y2a5HFL"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "send-report-request"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name                = "${var.project_name}-weekly-report"
  description         = "Request last week's report every Monday morning"
  schedule_expression = var.schedule_expression
  # Without it the cron runs in UTC and the report drifts with DST.
  schedule_expression_timezone = "Europe/Kyiv"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.requests.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{\"week\": null, \"source\": \"schedule\"}"
  }
}

# --- mailer (outside the VPC) -------------------------------------------------

resource "aws_iam_role" "mailer" {
  name               = "${var.project_name}-reports-MailerRole-LM6WBHX2rt0i"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "mailer" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer" {
  name = "read-and-send"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read only: a mailer that could write to reports/ would trigger itself.
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendRawEmail", "ses:SendEmail"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = 14
}

data "archive_file" "mailer" {
  type        = "zip"
  source_file = "${path.module}/mailer/index.py"
  output_path = "${path.module}/.build/mailer.zip"
}

resource "aws_lambda_function" "mailer" {
  function_name    = "${var.project_name}-report-mailer"
  description      = "Emails a new reports/*.csv through SES"
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256
  role             = aws_iam_role.mailer.arn
  memory_size      = 256
  timeout          = 30

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.mailer.name
  }

  environment {
    variables = {
      SENDER     = var.sender_email
      RECIPIENTS = var.recipient_emails
    }
  }
}

# Lets S3 (only from this bucket, in this account) invoke the mailer.
resource "aws_lambda_permission" "mailer_s3" {
  statement_id   = "${var.project_name}-reports-MailerInvokePermission-Lp4YPd9BBrLj"
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

# --- SES ----------------------------------------------------------------------

# SES mails a verification link to this address; click it once.
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.sender_email
}

resource "aws_sesv2_email_identity" "recipient" {
  count          = var.verify_recipient ? 1 : 0
  email_identity = var.recipient_emails
}

resource "aws_sesv2_email_identity" "domain" {
  count          = var.sender_domain != "" ? 1 : 0
  email_identity = var.sender_domain
}
