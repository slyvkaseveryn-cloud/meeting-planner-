# Lab 5: a weekly report, built by events

## What runs where

| Piece | File | Trigger |
|---|---|---|
| `build_weekly_report(week)`: the CSV, no AWS | `backend/app/reports/weekly.py` | called by the builder, or `python -m app.reports.weekly 2026-W40` locally |
| report-builder Lambda (backend image, in the VPC) | `backend/app/reports/lambda_handler.py` | SQS message (from the schedule or `make report-now`) |
| report-mailer Lambda (inline, outside the VPC) | `infra/reports.yml` (`MailerFunction`) | S3 `ObjectCreated` on `reports/*.csv` |
| Queue + DLQ, bucket, S3 gateway endpoint, schedule, SES identities | `infra/reports.yml` | `make aws-deploy-reports` |

The schedule sends a **command** (`{"week": null, "source": "schedule"}`) to SQS. The builder writes
`reports/<week>.csv`; S3 turns that into an **event** (`ObjectCreated`). The mailer reacts to the event.
The builder does not know the mailer exists.

Commands:

```bash
make aws-deploy-reports            # build+push the image, deploy the stack
make report-now WEEK=2026-W40      # on-demand report through SQS
make reports-ls                    # aws s3 ls s3://<bucket>/reports/ --recursive
make reports-logs                  # the "triggered" log lines of both functions
```

## Answers (Part 3, Step 7)

**Same week sent twice: how many emails?** Two. The builder overwrites the same key
(`reports/2026-W40.csv`), so S3 holds one file. That step is idempotent. But every `PutObject` is a new
`ObjectCreated` event, even when the bytes are identical, and the mailer sends one email per event.
Sending an email is not idempotent.

**1. The mailer got the same `ObjectCreated` event twice. Where would you store "already sent", and what is
the key?** Store it in a small DynamoDB table, written with a conditional put
(`attribute_not_exists(pk)`) *before* sending. The key is the object's identity *and* its content:
`<bucket>/<key>#<eTag>`, or `#<versionId>` if versioning is on. A duplicate delivery of the same
event has the same ETag, so the put fails and the mailer skips it. A deliberately rebuilt report with
changed data has a new ETag and is sent again. DynamoDB on-demand costs nothing at this volume. A
"sent" tag on the S3 object would also work, but tags are not conditional writes, so two parallel
deliveries could both see "not sent".

**2. The builder in the VPC cannot reach SES. Three fixes and their monthly cost (us-east-1):**

| Option | Cost | Notes |
|---|---|---|
| NAT gateway | ~$32.85/month ($0.045/h) + $0.045/GB processed, plus its public IPv4 (~$3.65) | Opens the whole internet to the VPC. Costs more than the rest of the stack together |
| VPC interface endpoint for SES (`email-smtp`/SES API) | ~$7.30/month per AZ ($0.01/h), ~$14.60 for two AZs, + $0.01/GB | Private path to SES only. Still billed by the hour |
| The split built here: builder in the VPC, mailer outside, joined by an S3 event | ~$0 (gateway endpoint free, Lambda/S3 events within the free tier) | One more function, and eventual delivery instead of a call |

With ten more emails a week: the split, because the hourly options cost money every hour to send a few
emails. With a million emails a week, the cost is SES itself (~$100/week at $0.10 per 1,000), not the
network. The split still works: S3 events and Lambda scale. But a million emails means batching, and
mailer concurrency limited by SES's sending rate (SQS between S3 and the mailer). An interface endpoint
(~$15/month) becomes noise at that scale, and is the better choice if the builder ever needs to call SES
directly. A NAT gateway only if the VPC needs general internet access for other reasons anyway.

**3. A link that works for a week instead of an attachment.** A presigned URL is only valid while the
credentials that signed it are, and a Lambda role's session expires in hours. Options:
- **Preferred:** email a link to our own site, e.g. `https://<site>/reports/2026-W40`. When it is opened,
  the API checks the user is signed in and allowed, then redirects to a *fresh* presigned URL valid for a
  few minutes. The link in the email never expires on its own, and access can be revoked.
- **CloudFront signed URL:** serve the bucket through CloudFront with OAC and sign the URL with a CloudFront
  key pair, with `Expires` set 7 days ahead. It does not depend on IAM session lifetime.
- Sign with long-lived IAM user keys (SigV4 max is 7 days). This works, but means storing a long-lived
  access key, which is what the course tells us to avoid.
