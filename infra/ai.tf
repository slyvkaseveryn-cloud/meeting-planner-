# Paste an agenda (Lab 6): the agenda-parser Lambda behind its own function
# URL, outside the VPC, calling Claude on Amazon Bedrock. It receives text and
# returns JSON; it needs no database and never writes anything. Saving goes
# through the normal API. Plus a $5 monthly AWS Budgets alarm.

resource "aws_iam_role" "parser" {
  name               = "${var.project_name}-ai-ParserRole-ZftFnR6tTLMp"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "parser" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser" {
  name = "call-claude"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # "*" for now: narrowing it to one model and one region is a
      # discussion question (see docs/adr/0006-llm-agenda-parsing.md).
      Effect   = "Allow"
      Action   = ["bedrock-mantle:CreateInference", "bedrock:InvokeModel"]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 14
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Parses pasted text into an agenda with Claude on Bedrock (suggests, never writes)"
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = [var.architecture]
  role          = aws_iam_role.parser.arn
  memory_size   = 512
  timeout       = 30

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  # No vpc_config: no database, and the internet (Bedrock, Cognito's JWKS)
  # without a NAT gateway or an endpoint.
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = var.region
      APP_TIMEZONE         = var.app_timezone
      COGNITO_REGION       = var.cognito_region
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
      COGNITO_CLIENT_ID    = var.cognito_client_id
      # Never opened: the parser has no database. Set so settings load.
      DATABASE_URL = "postgresql+asyncpg://unused@localhost/unused"
    }
  }

  # Code ships through the Makefile (update-function-code), not Terraform.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Public, but the handler rejects any request without a valid Cognito token.
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_origins = var.cors_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

resource "aws_lambda_permission" "parser_url" {
  statement_id           = "${var.project_name}-ai-ParserUrlPermission-0SInJVOE7bub"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id  = "${var.project_name}-ai-ParserUrlInvokePermission-tBMowSfG9MiN"
  function_name = aws_lambda_function.parser.function_name
  action        = "lambda:InvokeFunction"
  principal     = "*"
  # Only through the function URL (InvokedViaFunctionUrl in CloudFormation).
  invoked_via_function_url = true
}

# The cheapest insurance in the course.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = var.budget_usd
  limit_unit   = "USD"

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
}
