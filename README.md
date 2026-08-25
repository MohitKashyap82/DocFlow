# DocFlow
Event-Driven Document Processing Pipeline on AWS


Project: Distributed Document Processing & Alerting Pipeline

Concept: Users upload files (invoices, logs, compliance reports — tie it to your PCI DSS angle for narrative consistency with NetGuard) through an API. The system processes them asynchronously, fans out notifications, and tracks state — a pattern used everywhere in real fintech/enterprise systems.

Architecture flow:

ALB → ECS/EC2 API layer — Application Load Balancer fronts a small API (FastAPI again, for consistency with NetGuard) that accepts file uploads and issues presigned URLs.
S3 — Raw files land here. S3 event notification triggers the pipeline on ObjectCreated.
SQS — S3 event pushes to an SQS queue (decouples ingestion from processing — if your processor is down or slow, uploads don't fail, they just queue up). Use this to demonstrate dead-letter queues for poison messages — a detail interviewers specifically listen for.
Worker (Lambda or ECS task) — Polls SQS, processes the file (e.g., virus scan stub, metadata extraction, compliance check against a ruleset), writes results to DynamoDB.
DynamoDB — Stores processing status/results per file (partition key: file ID, sort key: timestamp) — good place to show single-table design and on-demand vs provisioned capacity reasoning.
SNS — On completion (or failure), publish to an SNS topic that fans out to multiple subscribers: an email notification (SES or just SNS email), a Slack webhook via Lambda subscriber, and optionally another SQS queue for downstream audit logging. This demonstrates fan-out pattern, which is the single most interview-relevant use of SNS+SQS together.

Why this is a strong CV project specifically for you:

It's the SNS+SQS fan-out + queue decoupling pattern, which is one of the most commonly asked "design a system" interview questions — you'll have a real repo to point to instead of whiteboarding cold.
ALB + ECS/Lambda shows you're comfortable with both container and serverless compute choices, and can justify when to use which.
DynamoDB single-table design is a genuinely differentiating skill — most candidates only know RDS.
You can layer in Terraform (consistent with NetGuard) and a GitLab/GitHub Actions CI/CD pipeline, so the two repos read as a coherent portfolio built by someone who thinks in IaC, not console clicks.
Natural place to add a DLQ + CloudWatch alarm + SNS alert loop, which shows operational maturity (not just "happy path" building).

Scope for a realistic timeline: This is buildable in 1-2 weeks if you keep the "processing" logic simple (a stub compliance check is fine — the infrastructure pattern is the point, not the business logic).

Want me to draft the Terraform module structure and repo layout for this one, the way we've been doing for NetGuard?

what will be suitable project heading ?

A few options depending on how you want to position it — technical/precise vs. slightly more narrative:

Straightforward/technical (good for CV bullet + repo name):

DocFlow — Event-Driven Document Processing Pipeline on AWS
PipelineGuard — Serverless Document Processing & Compliance Pipeline
FlowSentry — Async Document Processing Pipeline (SNS/SQS/DynamoDB/S3)

Ties it to your compliance/security narrative (consistent with NetGuard's positioning):

ComplyFlow — Event-Driven Compliance Document Processing Pipeline
AuditPipe — Serverless Compliance Ingestion & Alerting Pipeline

CV bullet version (what actually matters most):

DocFlow — Event-driven document processing pipeline on AWS using SNS/SQS fan-out, DynamoDB, S3, ALB-fronted API, and Terraform-managed infra with GitLab CI/CD.

My pick: go with DocFlow or ComplyFlow — short, readable, and the repo name doubles as something recruiters can actually remember and Google if they want to check it out. If you want it to echo NetGuard's naming style (single word, capitalized, descriptive), ComplyFlow pairs better thematically since both projects would then read as "security/compliance-minded infrastructure engineer," which is your strongest positioning angle given CISSP + PCNSE.

Want me to set up the repo structure and README skeleton for whichever name you land on?