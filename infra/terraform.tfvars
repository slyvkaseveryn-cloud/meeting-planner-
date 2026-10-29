# Non-secret values only. Secrets (google_client_secret) are sensitive
# variables in the HCP Terraform workspace.

project_name = "spry-severyn"
region       = "us-east-1"
image_uri    = "637965527585.dkr.ecr.us-east-1.amazonaws.com/spry-severyn-backend@sha256:7d2e6eb6eff821031c1e9a69484457b2a5d9e75051cfa183449fb17fe7bad36e"

# auth
app_urls = ["http://localhost:3000/", "https://d1nzs10xorfo1q.cloudfront.net/"]

# reports
api_function_name = "spry-severyn-backend"
vpc_id            = "vpc-0fc5b47842bd91789"
subnet_ids = [
  "subnet-0e94352662acb3bc5", "subnet-05a0142e71544d89d", "subnet-07a5b9ec4862fe4fc",
  "subnet-046e7fc87c43ea8bd", "subnet-0e3928206b44ecd35", "subnet-07aea21a96bbd0270",
]
security_group_id = "sg-0471047bfbb4797c0"
route_table_ids   = ["rtb-0d41407947e4f704a"]
sender_email      = "slyvkaseveryn@gmail.com"
recipient_emails  = "slyvkaseveryn@gmail.com"

# ai: the site signs in with the eu-north-1 pool (see docs/adr/0007-terraform.md)
cors_origins         = ["https://d1nzs10xorfo1q.cloudfront.net", "http://localhost:3000"]
cognito_region       = "eu-north-1"
cognito_user_pool_id = "eu-north-1_L3W21SVtG"
cognito_client_id    = "6mgv2evvp64htj3pdn4v9fln4m"
budget_email         = "slyvkaseveryn@gmail.com"
