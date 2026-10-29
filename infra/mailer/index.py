"""report-mailer: reacts to ObjectCreated on reports/*.csv and emails the file."""
import logging
import os
import urllib.parse
from email.message import EmailMessage

import boto3

log = logging.getLogger("report-mailer")
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def handler(event, context):
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
    # The line submitted for the lab: which event started the function.
    log.info("report-mailer triggered trigger=s3 event=%s key=%s",
             record.get("eventName"), key)

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    week = key.rsplit("/", 1)[-1].removesuffix(".csv")
    recipients = [r.strip() for r in os.environ["RECIPIENTS"].split(",") if r.strip()]

    msg = EmailMessage()
    msg["Subject"] = f"Weekly meetings report {week}"
    msg["From"] = os.environ["SENDER"]
    msg["To"] = ", ".join(recipients)
    msg.set_content(f"The meetings report for {week} is attached.\n")
    msg.add_attachment(body, maintype="text", subtype="csv",
                       filename=f"meetings-{week}.csv")

    sent = ses.send_email(
        FromEmailAddress=os.environ["SENDER"],
        Destination={"ToAddresses": recipients},
        Content={"Raw": {"Data": msg.as_bytes()}},
    )
    log.info("report sent key=%s to=%s message_id=%s",
             key, recipients, sent["MessageId"])
    return {"key": key, "message_id": sent["MessageId"]}
