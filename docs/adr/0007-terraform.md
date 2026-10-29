# ADR 0007: Sign-in, reports and the agenda parser move from CloudFormation to Terraform

- Status: accepted
- Date: 2026-10-29

## Context

Labs 4–6 added three CloudFormation stacks: `auth` (Cognito), `reports` (queue, builder, mailer,
schedule, SES) and `ai` (agenda parser, function URL, budget). They were deployed from a laptop with
`make aws-deploy-*`, so the only record of *who changed the infrastructure and why* was a shell history.
The project already reaches outside one AWS account (the Google OAuth client, GitHub), and it will need a
second environment. Users had signed up in the pool, and the bucket held reports, so nothing could be
re-created.

## Decision

- **Terraform** (`hashicorp/aws ~> 6.0`) describes those three parts in `infra/auth.tf`, `reports.tf`,
  `ai.tf`. One root module, one HCP Terraform workspace `spry-severyn-dev` (Remote execution).
- **Sign-in is the pool the site really uses.** `auth.yml` described a us-east-1 pool, but the site
  signs in with `eu-north-1_L3W21SVtG`, made by hand in the console and in no template: the hand-made
  resource from Part 0. `auth.tf` adopts it through a second provider (`alias = "eu_north_1"`): pool
  (deletion protection on), domain, Google IdP, both clients and their brandings, with the Google secret
  as a sensitive variable. The us-east-1 pool from `auth.yml` stays managed in `auth_legacy.tf`
  (`moved` blocks, nothing re-created) until its one user is moved or it is deleted.
- **Migration without re-creation:** `DeletionPolicy: Retain` on every resource, stacks deleted, then
  `import` blocks. The plan was `38 to import, 0 to add, 0 to destroy`, then `7 to import` for the
  eu-north-1 pool. Nothing was re-created (45 imported, 0 re-created). Two
  in-place updates: the builder's `DATABASE_URL` was marked sensitive (same value), and the mailer's code
  was re-uploaded from `infra/mailer/index.py` (same code, was inline `ZipFile`). The next plan:
  `No changes`. The Google IdP's `client_secret` was likewise only marked sensitive (value unchanged).
- **Who changes infrastructure:** anyone, through a pull request. HCP Terraform posts the plan as a check,
  a reviewer reads the plan, and the merge to `main` applies it. HCP Terraform reaches AWS with **dynamic
  credentials**: an OIDC token per run, exchanged for the role `hcp-terraform-<org>` (bootstrap, local
  state, outside this repo). No AWS key is stored anywhere. The Makefile only plans (`make infra-plan`).
- **Two roads:** Terraform owns the infrastructure, the Makefile ships code (`update-function-code`).
  The functions ignore `image_uri` after creation. When a change needs both (e.g. a new environment
  variable), **Terraform goes first**: the variable exists before the code that reads it, and the code
  must tolerate it missing.
- **ECR, API/database and site stay CloudFormation** for now (as the lab allows). Terraform reads only
  the API function (`data "aws_lambda_function"`) for its `DATABASE_URL`.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Keep CloudFormation | AWS keeps the state and rolls back for us, but it stops at one AWS account: the Google OAuth client, GitHub branch protection and DNS cannot be in the same plan. Reuse across environments means nested stacks or StackSets. |
| AWS CDK | Real code (TypeScript/Python) on top of CloudFormation, so the same one-account limit, plus a build step and a bootstrap stack. |
| OpenTofu | The same files and commands under an open-source licence. A fine choice; we use Terraform because HCP Terraform (state, locking, VCS runs, OIDC) is what the course uses, and switching later is `tofu init`. |

## Consequences

- **Secrets:** `google_client_secret` is a *sensitive* variable in the workspace (not in any file;
  plans print `(sensitive value)`). `DATABASE_URL` is copied from the API function, not typed in again.
  Both are still **in plain text in the state** (encrypted at rest in HCP Terraform, readable by
  organisation members with state access) and in the Lambda/Cognito configuration (readable with
  `lambda:GetFunctionConfiguration`). Access to the workspace is access to the secrets.
- **If HCP Terraform is down:** the application keeps running (HCP is not in the request path). Plans and
  applies wait. `make` targets that read `terraform output` fail until it returns. In an emergency, the
  latest state version can be downloaded and applied locally, then pushed back, with the workspace locked.
- **Two pools for now:** the site's (eu-north-1) and the legacy one (us-east-1, one user, not used by
  the site). `make aws-deploy-backend` / `aws-deploy-frontend` now read the eu-north-1 pool from the
  Terraform outputs, so they no longer point the site at the wrong pool.
- **Drift is visible:** every plan compares with the real resources. A console fix must become a pull
  request the same day, or the next apply undoes it.
- **Open risks:** the bootstrap role has `AdministratorAccess` (to be narrowed to IAM, Lambda, S3, SQS,
  Scheduler, Cognito, SES, Budgets, Logs, EC2 endpoints, and to one workspace in its trust).
