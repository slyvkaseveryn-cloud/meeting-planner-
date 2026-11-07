# ADR 0008: Spry's core also runs on Google Cloud

- Status: accepted
- Date: 2026-11-07

## Context

Lab 9 asks what it would take to run Spry on a second cloud, and what it would cost. On AWS the
site is S3 + CloudFront, the API is a Lambda container, the database is Aurora Serverless v2
(pauses at 0 ACU), sign-in is a Cognito pool in eu-north-1, the weekly report is EventBridge
Scheduler → SQS → Lambda → S3 → Lambda → SES, and the agenda parser is a Lambda calling Bedrock.
The Google Cloud project runs on the Free Trial ($300 for 90 days, no charge to the card); nothing
here may need an upgrade to a paid account.

## Decision

Move the core (site, API, database) to Google Cloud in `gcp/`, a separate Terraform root with its
own HCP Terraform workspace `spry-severyn-gcp`, so one plan cannot break both clouds.

| Spry on AWS | On Google Cloud | Decision |
|---|---|---|
| S3 + CloudFront, static export | Firebase Hosting | **Replace.** Free plan, HTTPS and CDN included; it rewrites `/api/**` to Cloud Run, so one origin and no CORS, as CloudFront did |
| Lambda + function URL, FastAPI | Cloud Run | **Replace.** The plain `backend/Dockerfile` (uvicorn) runs unchanged; `Dockerfile.lambda` and `lambda_handler.py` are not used. Min instances 0 |
| ECR | Artifact Registry | **Replace.** A cleanup policy keeps 3 images, inside the free 0.5 GB |
| Aurora Serverless v2 | Cloud SQL for PostgreSQL, `db-f1-micro`, 10 GB SSD | **Replace**, stopped when not demoed (`db_running = false`) |
| Cognito (eu-north-1) + Google | Identity Platform | **Keep on AWS.** Cloud Run verifies the same Cognito tokens (it has internet access to fetch the keys); the Firebase URL is one more callback URL on the pool |
| EventBridge Scheduler, SQS, S3 events | Cloud Scheduler, Pub/Sub, Eventarc | **Keep on AWS** (weekly report): the builder reads Aurora, which stays the AWS database |
| SES | none at Google | **Keep SES.** If the report moved, its credentials would be a Secret Manager secret |
| Bedrock | Vertex AI | **Keep on AWS.** The trial credit does not pay for Claude on Vertex |
| Secrets Manager / Lambda env | Secret Manager | **Replace.** The whole `DATABASE_URL`, with a Terraform-generated password |
| CloudWatch Logs | Cloud Logging | **Replace** (automatic for Cloud Run) |
| IAM roles | Service accounts | **Replace.** `spry-severyn-api` runs the API (Cloud SQL Client, one secret); `hcp-terraform` deploys |
| Terraform `aws` | Terraform `google` | Same workflow: a pull request plans, a merge applies |

**The database.** Options considered:

- *Cloud SQL around the clock*: same SQL, migrations and code; ~$9.40 a month whether used or not.
- *Cloud SQL stopped when idle* (chosen): same code; ~$1.70 a month for storage while stopped, but it
  does not wake by itself on a request, so the site only works while someone has started it.
- *Firestore*: $0 at student traffic, but every repository and migration is rewritten as documents.
  Not worth it for a lab whose point is to move the system, not rewrite it.
- *Keep Aurora and call it across clouds*: Aurora is in a private VPC, so it would need a public
  endpoint or a VPN, 100+ ms per query from us-central1 to us-east-1, and egress on every row.

The data was not copied: Aurora has no public endpoint. The API runs `alembic upgrade head` on start
against the empty Cloud SQL database; meetings are created again through the site.

**Who deploys.** HCP Terraform reaches Google Cloud through Workload Identity Federation: a pool and
provider for `app.terraform.io` that admit only the workspace id `ws-LfmHdw6JVCJn4vo7` (an id, not a
name, so it cannot be re-registered), and Workload Identity User on the `hcp-terraform` service
account. No key is created. The bootstrap is in `~/tf-bootstrap-gcp` with local state.

## Consequences

- **Not moved:** sign-in, the weekly report and the agenda parser. They depend on Cognito, Aurora and
  Bedrock; moving them is a rewrite, not a redeploy.
- **Lock-in sits in the managed services, not in compute:** the container moved without a code
  change. Cognito, SQS/S3 events and Bedrock are what would have to be rewritten.
- **The site on Google Cloud uses AWS for sign-in:** one more redirect URL in `infra/terraform.tfvars`,
  and the API fetches the pool's keys across clouds once per instance.
- **Cost trap:** Cloud SQL does not pause. A forgotten instance is ~$9.40 a month (the trial credit
  pays now, the card would after). The budget alert is $5 a month; `terraform destroy` in `gcp/`
  removes everything.
- **Open risks:** the `hcp-terraform` account holds admin roles on Run, SQL, Artifact Registry,
  Secret Manager and service accounts; Project IAM Admin is limited by a condition to granting
  Cloud SQL Client.
