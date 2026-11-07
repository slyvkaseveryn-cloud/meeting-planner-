# Lab 9: Spry's core on Google Cloud, and what it costs

Site: https://meetings-slyvka.web.app (Firebase Hosting) → `/api/**` → Cloud Run → Cloud SQL.
Service choices: [ADR 0008](adr/0008-google-cloud.md). Infrastructure: [`gcp/`](../gcp).

## Data

Not copied: Aurora sits in a private VPC with no public endpoint, so `pg_dump` would need a
bastion. The API runs the migrations (`alembic upgrade head`) on start against the empty Cloud SQL
database, and meetings are created again through the site.

## Cost: Spry's core, by traffic profile

On-demand list prices in USD, AWS us-east-1, Google Cloud us-central1, 730 hours a month, no tax.

**Assumptions**

- **Free tiers:**
  - Lambda: 1M requests and 400,000 GB-s.
  - Cloud Run: 2M requests, 180,000 vCPU-s and 360,000 GiB-s.
  - CloudFront Free plan and the Firebase Hosting free plan: $0.
  - ECR (0.5 GB) and Artifact Registry (0.5 GB, newest 3 images kept): $0.
  - Secret Manager: 6 versions. Spry uses 1.
- **Aurora Serverless v2:**
  - $0.12 per ACU-hour.
  - It sits at the 0.5 ACU floor whenever it is awake (Spry's load never pushes it higher).
  - It pauses after 5 idle minutes and costs $0 for compute while paused.
  - Storage: ~1 GB at $0.10.
- **Cloud SQL `db-f1-micro`:**
  - $0.0105 an hour while running.
  - 10 GB SSD at $0.17 = $1.70 a month, also billed while stopped.
  - "Left on" means it runs all month. "Started for use" means it is started only for the hours in the profile and stopped otherwise (`db_running`).
- **API compute** stays inside the free tiers on both clouds, except "busy". There, ~2.6M requests a month cost ~$1 on either cloud.

**Profiles**

| Profile | Database awake | AWS: Aurora | GCP: Cloud SQL left on | GCP: Cloud SQL started for use |
|---|---|---|---|---|
| Nobody | 0 h | 0 + 0.10 + cents ≈ **$0.30** | 7.67 + 1.70 ≈ **$9.40** | 0 + 1.70 = **$1.70** |
| Class demos (10 × 2 h) | 20 h | 20 × 0.06 + 0.30 ≈ **$1.50** | **$9.40** | 0.21 + 1.70 ≈ **$1.90** |
| Office hours (8 h × 22 days) | 176 h | 176 × 0.06 + 0.30 ≈ **$10.90** | **$9.40** | 1.85 + 1.70 ≈ **$3.55** |
| Busy around the clock | 730 h | 730 × 0.06 + 0.30 + ~1 ≈ **$45** | 9.40 + ~1 ≈ **$10.40** | the same as left on |

At "busy", a shared-core `db-f1-micro` (0.6 GB) is not a fair match for 0.5–1 ACU (1–2 GB). With
`db-g1-small` ($0.035/h → $25.55 + $1.70 ≈ $27), Google Cloud is still cheaper than Aurora at
0.5 ACU. Against Aurora at 1 ACU (~$88), it wins by more.

**Free tier on this project:** the Google Cloud Free Trial ($300 for 90 days) pays for all of the
above. The card is not charged unless the account is upgraded. A $5/month budget alert is set.

## Answers

**Which cloud is cheaper for each profile, and which line decides it?**
The **database compute** line decides every profile. The API, site, registry and secrets are $0 on
both clouds at student traffic.

- **Nobody and class demos: AWS.** Aurora pauses, so idle hours cost nothing. Cloud SQL never
  pauses, so even stopped it bills $1.70 a month of storage.
- **Office hours: Google Cloud.** 176 awake hours of Aurora at 0.5 ACU ($10.56) already cost more
  than a `db-f1-micro` running all month ($7.67).
- **Busy: Google Cloud, clearly.** A small instance billed by the hour beats a serverless database
  that is never allowed to pause.

**Where is Lab 4's trap (Aurora costing more than an instance when something keeps it awake) on the GCP side?**
On Google Cloud the trap is the reverse: **Cloud SQL has nothing to keep awake, because it never
sleeps.** An instance created for one demo and forgotten bills ~$9.40 every month. A stopped
instance still bills its storage. The closer equivalent of "something keeps it awake" is on
**Cloud Run**:

- `min_instance_count = 1`, or CPU set to "always allocated", turns a $0 API into one billed every
  second of the month.
- An uptime check hitting `/health` every minute does not keep it awake for free either.

If the database were **Firestore**, the trap moves into the code: a list page reading 500 documents
uses up the 50,000 free daily reads after 100 visits.

## Part 4 demos

Screenshots are attached to the submission:

- a BigQuery query over a public dataset (bytes processed noted);
- a Looker Studio chart over that result;
- one Vision or Document AI OCR result.
