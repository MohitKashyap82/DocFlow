# ComplyFlow — AWS Console Build Guide

Region: **eu-west-2 (London)**. Build in this exact order — each phase is testable on its own before you move to the next.

Naming convention used throughout: `complyflow-*`. Keep it consistent — you'll thank yourself when you Terraform this later.

---

## Phase 1 — S3 Bucket

1. Console → **S3** → Create bucket.
2. Name: `complyflow-uploads-<your-aws-account-id>` (bucket names are globally unique, suffixing with account ID guarantees no clash).
3. Region: eu-west-2.
4. Block Public Access: leave **all four boxes checked** (fully private — access will go through presigned URLs only).
5. Bucket Versioning: **Enable**. This gives you a real reason to talk about accidental-overwrite protection in interviews.
6. Default encryption: **SSE-S3** is fine to start (switch to SSE-KMS later if you want a customer-managed key story for the CV).
7. Create bucket.
8. Once created, go to **Properties** tab — leave Event notifications for Phase 4, you'll come back.

**Test:** Manually upload a small file via console → Object actions → Upload. Confirm it appears.

---

## Phase 2 — DynamoDB Table

1. Console → **DynamoDB** → Create table.
2. Table name: `complyflow-status`.
3. Partition key: `fileId` (String).
4. Sort key: `timestamp` (String) — lets you query history per file, not just latest state.
5. Table settings: **On-demand** capacity mode (no need to guess throughput for a portfolio project — also cheaper when idle).
6. Create table.
7. Optional but worth it for the CV story: Console → table → **Additional settings** → enable **Point-in-time recovery** (PITR). Mention this in interviews as a durability decision.

**Test:** Console → Explore table items → Create item manually with `fileId: test-001`, `timestamp: 2026-08-17T00:00:00Z`, `status: uploaded`. Confirm it saves and you can query it back.

---

## Phase 3 — SQS Queue + Dead Letter Queue

Build the DLQ first, since the main queue needs to reference it.

1. Console → **SQS** → Create queue.
2. Type: **Standard** (not FIFO — you don't need strict ordering for this use case, and it's simpler to reason about).
3. Name: `complyflow-processing-dlq`.
4. Leave defaults, Create queue.
5. Create a second queue: `complyflow-processing`.
6. In this queue's setup, scroll to **Dead-letter queue** section:
   - Enable it.
   - Choose `complyflow-processing-dlq` (its ARN) as the target.
   - Maximum receives: **3** (after 3 failed processing attempts, the message moves to the DLQ instead of looping forever).
7. Under **Access policy**, you'll need to allow S3 to send messages — come back to this in Phase 4 once you have the bucket ARN handy (or do it now if you already have it):
   - Switch to the **Advanced** JSON editor and add a statement allowing `sqs:SendMessage` from `s3.amazonaws.com` where `aws:SourceArn` equals your bucket's ARN. The console's policy generator can do this for you — use "Advanced" → "Add statement" → Principal: `Service` → `s3.amazonaws.com`.
8. Create queue.

**Test:** Console → queue → Send and receive messages → send a test JSON message → poll for messages → confirm you can see and delete it.

---

## Phase 4 — Wire S3 → SQS (event notification)

1. Console → **S3** → your bucket → **Properties** tab → scroll to **Event notifications** → Create event notification.
2. Name: `complyflow-upload-trigger`.
3. Event types: check **All object create events** (or narrow to `PUT` only if you want to be precise).
4. Destination: **SQS queue** → select `complyflow-processing`.
5. Save.

If the console throws a permissions error here, it means the SQS access policy from Phase 3 step 7 isn't in place yet — go fix that first, then retry.

**Test:** Upload a new file into the bucket manually. Go to the SQS queue → Send and receive messages → Poll for messages. You should see a message containing the S3 event JSON (bucket name, object key, etc.) within a few seconds. **This is the most important checkpoint in the whole build** — if this works, your event-driven backbone is proven.

---

## Phase 5 — IAM Role for the Lambda Worker

1. Console → **IAM** → Roles → Create role.
2. Trusted entity: **AWS service** → **Lambda**.
3. Name: `complyflow-worker-lambda-role`.
4. Attach these managed policies to start (you'll tighten to least-privilege later — note that "later" in your CV notes as a deliberate hardening step):
   - `AWSLambdaBasicExecutionRole` (CloudWatch Logs)
   - `AmazonSQSFullAccess` — replace with a scoped custom policy once it works (only `sqs:ReceiveMessage`, `DeleteMessage`, `GetQueueAttributes` on the specific queue ARN)
   - `AmazonDynamoDBFullAccess` — same, scope down later to `PutItem`/`UpdateItem` on the specific table ARN
   - `AmazonS3ReadOnlyAccess` — the worker needs to read the uploaded object
   - `AmazonSNSFullAccess` — scope down later to `sns:Publish` on the specific topic ARN
5. Create role.

**Why full-access-then-scope-down instead of writing the tight policy immediately:** it de-risks debugging — you find out if your *logic* works before you find out if your *permissions* are too tight. Document the tightened policy afterward; that before/after is a good interview talking point about least privilege.

---

## Phase 6 — Lambda Worker Function

1. Console → **Lambda** → Create function.
2. Name: `complyflow-worker`.
3. Runtime: **Python 3.13** (or latest available).
4. Execution role: **Use an existing role** → `complyflow-worker-lambda-role`.
5. Create function.
6. **Configuration → Triggers** → Add trigger → **SQS** → select `complyflow-processing` queue.
   - Batch size: start with **1** (simpler to debug one message at a time; increase later for throughput).
7. **Configuration → General configuration** → Edit → set Timeout to **30 seconds** (default 3s will time out on real work).
8. Write the handler code (paste into the inline editor for now):

```python
import boto3
import json
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
table = dynamodb.Table('complyflow-status')
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        for s3_record in body.get('Records', []):
            bucket = s3_record['s3']['bucket']['name']
            key = s3_record['s3']['object']['key']
            file_id = key.split('/')[-1]

            # Write "processing" status
            table.put_item(Item={
                'fileId': file_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status': 'processing',
                'bucket': bucket,
                'key': key
            })

            # --- stub compliance check / metadata extraction goes here ---
            result_status = 'complete'  # or 'failed', based on your check

            table.put_item(Item={
                'fileId': file_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status': result_status,
                'bucket': bucket,
                'key': key
            })

            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f'ComplyFlow: {file_id} {result_status}',
                Message=json.dumps({'fileId': file_id, 'status': result_status})
            )

    return {'statusCode': 200}
```

9. **Configuration → Environment variables** → add `SNS_TOPIC_ARN` (leave the value blank for now, come back after Phase 7).
10. Deploy.

**Test:** Upload another file to S3. Watch **CloudWatch Logs** for this function (Lambda console → Monitor → View CloudWatch logs). Confirm invocation, and check DynamoDB for the new item.

---

## Phase 7 — SNS Topic + Fan-out Subscriptions

1. Console → **SNS** → Topics → Create topic.
2. Type: **Standard**.
3. Name: `complyflow-events`.
4. Create topic. Copy the **Topic ARN**.
5. Go back to Lambda (Phase 6, step 9) and paste this ARN into the `SNS_TOPIC_ARN` environment variable. Redeploy.
6. Back in SNS → your topic → **Create subscription**:
   - Protocol: **Email** → enter your own address → confirm via the email you'll receive.
   - Add a second subscription: Protocol: **SQS** → target a new queue `complyflow-audit-log` (create it first in SQS, same as Phase 3 but no DLQ needed) — this is your compliance audit trail.
   - Slack subscription is the more advanced one: create a second small Lambda (`complyflow-slack-notifier`) subscribed to this SNS topic, which posts to a Slack **Incoming Webhook** URL. Do this last, once email + audit queue are proven — it's the least essential piece for the architecture to "work."

**Test:** Upload a file, confirm you get the email, and check the audit SQS queue for the message.

---

## Phase 8 — API Layer (ALB + ECS Fargate)

This is the most involved phase — build it last since everything before it can be tested by uploading directly through the S3 console.

1. **ECR repo first:** Console → ECR → Create repository → `complyflow-api`. Build your FastAPI presigned-URL app locally, `docker build`, authenticate (`aws ecr get-login-password`), and push the image.
2. **VPC:** Use the default VPC to start (don't build a custom one until you're doing this in Terraform — it's not worth the console clicking). Note its subnets — you'll need at least 2 AZs for the ALB.
3. **ECS Cluster:** Console → ECS → Create cluster → Fargate → name `complyflow-cluster`.
4. **Task Definition:** Create → Fargate → name `complyflow-api-task` → point the container to your ECR image → set port 8000 (or whatever your FastAPI app listens on) → attach a task role with `s3:PutObject`/`s3:GetObject` scoped to your bucket (for generating presigned URLs).
5. **Application Load Balancer:** Console → EC2 → Load Balancers → Create → Application Load Balancer → internet-facing → select the same VPC and at least 2 public subnets → create a target group of type **IP** (Fargate tasks use IP targets, not instance targets) pointing at port 8000.
6. **ECS Service:** In your cluster → Create service → Launch type Fargate → use the task definition → desired count 1 → attach to the ALB target group you just created → select the same subnets, and a security group allowing inbound 8000 from the ALB's security group only (not from the internet directly).
7. **Security groups:** ALB security group allows inbound 443/80 from `0.0.0.0/0`. ECS task security group allows inbound 8000 **only from the ALB security group** — this is the detail that shows you understand defense in depth, don't skip it.

**Test:** Hit the ALB's DNS name in a browser, confirm your FastAPI app responds, and confirm a real upload through it lands in S3 and triggers the whole pipeline end to end.

---

## Build order summary

| Phase | What | Proves |
|---|---|---|
| 1 | S3 bucket | Storage works |
| 2 | DynamoDB table | State store works |
| 3 | SQS + DLQ | Queue mechanics work |
| 4 | S3 → SQS event | Event trigger works |
| 5 | IAM role | Worker has permissions |
| 6 | Lambda worker | Processing logic works |
| 7 | SNS fan-out | Notifications work |
| 8 | ALB + ECS API | Full end-to-end via real HTTP |

Once all 8 phases pass their individual tests, do one final end-to-end run: hit the ALB URL → upload a file through the real API → watch it flow through SQS → Lambda → DynamoDB → SNS → your inbox, without touching the console mid-flight. That's your demo for interviews, and it's also exactly what you'll be codifying into Terraform next.
