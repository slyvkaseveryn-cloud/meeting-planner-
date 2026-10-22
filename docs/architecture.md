# Spry: container diagram (C4, level 2)

Updated for Lab 6: the agenda parser and Bedrock, with the two paths, **parse** and **save**.

```mermaid
flowchart LR
    user([Team lead<br/>browser])

    subgraph aws[AWS]
        cf[Static site<br/>Next.js export on S3 + CloudFront]
        cognito[Cognito user pool<br/>email + password, Google]
        subgraph outside[Outside the VPC]
            parser[agenda-parser Lambda<br/>function URL, Python]
            mailer[report-mailer Lambda]
        end
        bedrock[Amazon Bedrock<br/>Claude Opus 5.5]
        subgraph vpc[VPC, no NAT]
            api[API Lambda<br/>FastAPI, function URL]
            builder[report-builder Lambda]
            db[(Aurora Serverless v2<br/>PostgreSQL)]
        end
        s3r[(S3 reports bucket)]
        ses[Amazon SES]
        sqs[[SQS report-requests<br/>+ DLQ]]
        sched[EventBridge Scheduler]
    end

    user -->|loads the app| cf
    user -->|signs in| cognito
    user -->|"1. parse: POST text + token"| parser
    parser -->|"record_agenda tool call"| bedrock
    parser -.->|"suggested agenda (JSON)"| user
    user -->|"2. save: PUT /meetings/{id}/agenda"| api
    api -->|agenda + ai_suggestion| db

    sched --> sqs --> builder --> db
    builder --> s3r -->|ObjectCreated| mailer --> ses
```

The parser only suggests. The only path that writes is **save**, through the API that already validates
and scopes every meeting to its owner.
