# ComplyFlow infra

Two independent Terraform stacks, both with state in S3 (`complyflow-tf-state-261161414394-us-east-1`, locked via DynamoDB table `complyflow-tf-locks`):

- **`backbone/`** — S3, DynamoDB, SQS (+DLQ), Lambda, SNS, the Lambda's IAM role. Stays up permanently; costs ~$0 when idle. Applied automatically on push to `main` (plan) and manually via `workflow_dispatch` (apply) — see `.github/workflows/backbone.yml`.
- **`compute/`** — ALB + ECS Fargate service (+ security groups + a dedicated task IAM role). The only thing meant to be spun up/torn down on demand. Driven entirely by manual `workflow_dispatch` — see `.github/workflows/compute.yml`.
- **`bootstrap/`** — creates the state bucket/lock table/GitHub OIDC deploy role. Applied **once, locally, by hand**. Never runs in CI (it's what CI's AWS access depends on).

## One-time setup

1. Apply bootstrap locally (already done if you're reading this after that step):
   ```bash
   cd infra/bootstrap
   terraform init
   terraform apply
   terraform output github_actions_role_arn
   ```
2. Push this repo to GitHub as `MohitKashyap82/DocFlow` (or update `var.github_repo` in `infra/bootstrap/variables.tf` and re-apply if it lives elsewhere).
3. In the GitHub repo → Settings → Environments → create an environment named `AWS_ROLE_ARN` → add an **environment secret** also named `AWS_ROLE_ARN` = the `github_actions_role_arn` output from step 1. (Every workflow job references this via `environment: AWS_ROLE_ARN` + `${{ secrets.AWS_ROLE_ARN }}`.)

   This value isn't actually sensitive on its own — auth is via OIDC, so there's no static AWS key being stored, and the trust policy (scoped to `repo:MohitKashyap82/DocFlow:*`) is what actually gates access, not secrecy of the ARN. It's stored as an environment secret here mainly so the environment can later carry protection rules (e.g. required reviewers) as a manual approval gate before infra-mutating jobs run.
4. Add a repo **variable** (Settings → Secrets and variables → Actions → Variables) named `ALERT_EMAIL` set to the address that should be subscribed to the `complyflow-events` SNS topic. `backbone.yml` passes it through as `TF_VAR_alert_email`; `infra/backbone/variables.tf` has no default for it on purpose, so it isn't published in source. Running Terraform locally needs the same: `export TF_VAR_alert_email=you@example.com` (or `-var`) before `plan`/`apply`.

## Day to day

- Change something in `api/` → push to `main` → `build-and-push.yml` builds and pushes a new image to ECR automatically.
- Change something in `infra/backbone/` → push to `main` → plan runs automatically; trigger `backbone.yml` manually with `action: apply` to apply it.
- Want the app reachable → Actions tab → **Compute (ALB + ECS) Up/Down** → Run workflow → `action: up`. Grab the URL from the job's "Print app URL" step.
- Done for now / saving cost → same workflow → `action: down`. This destroys only the ALB/ECS/security-groups/task-role — the backbone (and your data) is untouched.
