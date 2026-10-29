# Non-secret values only. Secrets (google_client_secret) are sensitive
# variables in the HCP Terraform workspace.

project_name = "spry-severyn"
region       = "us-east-1"
image_uri    = "637965527585.dkr.ecr.us-east-1.amazonaws.com/spry-severyn-backend@sha256:7d2e6eb6eff821031c1e9a69484457b2a5d9e75051cfa183449fb17fe7bad36e"

# auth: the eu-north-1 pool (auth.tf); app_urls belong to the legacy us-east-1 pool
cognito_region   = "eu-north-1"
site_urls        = ["https://d1nzs10xorfo1q.cloudfront.net/"]
google_client_id = "167569518265-kq7dvgsr9s2ltbb6okob14k8rvpjaheh.apps.googleusercontent.com"
app_urls         = ["http://localhost:3000/", "https://d1nzs10xorfo1q.cloudfront.net/"]

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

# ai
cors_origins = ["https://d1nzs10xorfo1q.cloudfront.net", "http://localhost:3000"]
budget_email = "slyvkaseveryn@gmail.com"
