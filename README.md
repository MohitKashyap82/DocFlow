# DocFlow

Event-driven document processing pipeline on AWS, provisioned entirely with Terraform and deployed through GitHub Actions.

Users upload a file through a FastAPI service; the pipeline processes it asynchronously, tracks its status, and fans out a completion notification — a pattern used throughout real-world fintech/enterprise ingestion systems.

## Architecture

```
Browser ──▶ ALB ──▶ ECS Fargate (FastAPI) ──▶ S3 (presigned PUT)
                                                    │
                                          S3 ObjectCreated event
                                                    ▼
                                              SQS ──────────▶ SQS DLQ
                                          (complyflow-processing)   (after 3 failed attempts)
                                                    │
                                                    ▼
                                          Lambda worker (compliance check stub)
                                                    │
                                        ┌───────────┴───────────┐
                                        ▼                       ▼
                                  DynamoDB (status)         SNS topic
                                                                 │
                                                    ┌────────────┴────────────┐
                                                    ▼                         ▼
                                              Email alert              SQS audit-log queue
```

- **API layer** — FastAPI on ECS Fargate behind an Application Load Balancer. Issues S3 presigned URLs so uploads go straight from the browser to S3, never through the API server itself.
- **Ingestion decoupling** — an S3 event notification lands on an SQS queue rather than invoking the worker directly, so a slow or unavailable worker never blocks uploads. A dead-letter queue catches messages that fail processing three times.
- **Processing** — a Lambda function consumes the queue, runs a (stubbed) compliance check, and writes status transitions to DynamoDB.
- **Fan-out** — on completion, SNS publishes to two independent subscribers in parallel: an email alert and an SQS queue for audit logging — the classic SNS+SQS fan-out pattern for one event needing multiple independent consumers.

## Infrastructure & CI/CD

Everything above is defined in [`infra/`](infra/) as three independent Terraform stacks:

| Stack | Contents | Lifecycle |
|---|---|---|
| `bootstrap` | Terraform state backend (S3 + DynamoDB lock table), GitHub OIDC deploy role | Applied once, by hand |
| `backbone` | S3, DynamoDB, SQS + DLQ, Lambda, SNS | Always on — free/near-free when idle |
| `compute` | ALB, ECS cluster/service/task definition, security groups | Spun up and torn down on demand |

Splitting `compute` out separately means the only AWS spend that scales with "is anyone actually using this right now" — the ALB and Fargate task — can be toggled independently of the always-on data pipeline, without touching stored data or SNS subscriptions.

[GitHub Actions](.github/workflows/) drives all three:
- **`build-and-push.yml`** — builds and pushes the API image to ECR on changes to `api/`
- **`backbone.yml`** — plans on every change, applies on manual approval
- **`compute.yml`** — manual `up`/`down` dispatch to stand up or tear down the ALB + ECS service

Every workflow authenticates to AWS via **OIDC federation** — no long-lived AWS access keys are stored in GitHub.

## Tech stack

**API:** Python, FastAPI, boto3, Docker
**Data/messaging:** S3, SQS, Lambda, DynamoDB, SNS
**Compute:** ECS Fargate, Application Load Balancer
**IaC/CI:** Terraform, GitHub Actions, GitHub OIDC

## Repo layout

```
api/          FastAPI presigned-upload service
infra/        Terraform: bootstrap / backbone / compute stacks
.github/      CI/CD workflows
```

See [`infra/README.md`](infra/README.md) for setup and day-to-day operation.
