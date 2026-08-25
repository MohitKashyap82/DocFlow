# DocFlow — Interview Prep Q&A

Questions I might get asked about this project, with answers I can actually defend.

---

### Q: Why did you use FastAPI and not Flask?

**A:** This service is I/O-bound, not CPU-bound — it just accepts a filename/content-type and calls out to S3 to generate a presigned URL. FastAPI's ASGI/async foundation means the API layer can handle many concurrent presign requests without blocking a worker thread on each outbound AWS call, which matters when this sits behind an ALB and needs to scale horizontally on ECS Fargate.

Supporting points:

- **Validation/contracts for free** — request/response shapes (`PresignRequest`, `PresignResponse`) are Pydantic models, so invalid input is rejected automatically with a clear 422 error, and I get free OpenAPI docs at `/docs` — useful since this API is meant to be consumed by other services in the pipeline (SQS/Lambda/DynamoDB), not just a human clicking a form.
- **Type hints as documentation** — the function signature is the contract: `create_presigned_upload(req: PresignRequest) -> PresignResponse` tells you the API shape without a separate schema file.
- **Consistency across my portfolio** — I used the same framework on my other project (NetGuard) so the two repos read as a coherent stack decision rather than picking tools ad hoc.
- **Honest tradeoff** — Flask is a completely reasonable choice too, especially for simpler synchronous services or content-heavy server-rendered pages. The decision here was driven by the I/O profile of the workload (async calls to AWS), not a blanket preference.

https://www.youtube.com/watch?v=iWS9ogMPOI0

---

### Q: Walk me through how you build and deploy your API image to ECR.

**A:** The API is packaged into a Docker image and pushed to a private ECR repository, which ECS Fargate then pulls from to run the task. The flow is: authenticate Docker to ECR → build the image locally → tag it with the ECR registry URI → push.

```bash
# 1. Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# 2. Build the image (context = api/, where the Dockerfile lives)
docker build -t complyflow-api:latest ./api

# 3. Tag it for the ECR repo
docker tag complyflow-api:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/complyflow-api:latest

# 4. Push
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/complyflow-api:latest

# 5. (Optional) Also tag with the git commit hash, not just "latest"
docker tag complyflow-api:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/complyflow-api:$(git rev-parse --short HEAD)
docker push \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/complyflow-api:$(git rev-parse --short HEAD)

# 6. Verify the push landed
aws ecr describe-images --repository-name complyflow-api --region us-east-1

# 7. Roll a running ECS service onto the new image
aws ecs update-service \
  --cluster complyflow-cluster \
  --service <service-name> \
  --force-new-deployment \
  --region us-east-1
```

**Command-by-command, what's actually happening and why:**

1. **`aws ecr get-login-password`** — ECR doesn't use a static username/password. This CLI command asks AWS (using your already-configured AWS credentials/IAM identity) to mint a **short-lived authorization token** (valid ~12 hours) scoped to your account's ECR registry.
   **`docker login --password-stdin`** — feeds that token to Docker over stdin rather than as a plaintext CLI argument, so it never lands in shell history or `ps` output. This is the detail worth mentioning if asked "how does Docker authenticate to a private registry without a saved password?"

2. **`docker build -t complyflow-api:latest ./api`** — builds an image from the `Dockerfile` in `api/`, following its steps: base off `python:3.13-slim`, install `requirements.txt`, copy the `app/` source, expose port 8000, and set the container's start command to run `uvicorn`. The `./api` at the end is the **build context** — the set of files Docker can `COPY` from — which is why the Dockerfile lives inside `api/` rather than the repo root.

3. **`docker tag`** — Docker images are locally named whatever you want (`complyflow-api:latest`), but to push to a specific registry, the image needs a tag whose prefix matches that registry's URI (`<account-id>.dkr.ecr.<region>.amazonaws.com/<repo-name>:<tag>`). Tagging doesn't rebuild anything — it just gives the same image layers an additional name/pointer.

4. **`docker push`** — uploads the image layers to ECR. Only layers that changed since the last push are actually uploaded (image layers are content-addressed and cached), which is why iterative pushes after a small code change are fast.

5. **Tagging with a commit hash, not just `latest`** — `latest` gets overwritten every push, so if you ever need to roll back or you're debugging "which code is actually running in prod," a mutable `latest` tag tells you nothing. A tag tied to `git rev-parse --short HEAD` lets you trace a running container straight back to the exact commit — a point worth raising if asked about deployment traceability or rollback strategy.

6. **`aws ecr describe-images`** — sanity check that the push actually landed and to confirm the tag/digest you expect is present, before wiring it into ECS.

7. **`aws ecs update-service --force-new-deployment`** — pushing a new image to ECR does **not** automatically restart already-running ECS tasks; ECS only pulls a new image when a task is (re)started. This command tells the service to spin up new tasks (pulling the current image behind whatever tag the task definition references — typically `latest`) and drain the old ones, which is how a new image actually reaches production.

**Security note worth mentioning in an interview:** never hardcode your AWS account ID, image URIs with the account ID baked in, or credentials into a public repo/README if you can avoid it — use placeholders (`<account-id>`) in docs and pull the real value at runtime via `aws sts get-caller-identity`, exactly as done above. Small detail, but it's the kind of hygiene that reads well given the compliance/security framing of this project.

---

<!-- Add new questions below this line -->
