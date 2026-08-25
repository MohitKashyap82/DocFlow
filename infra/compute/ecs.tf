resource "aws_ecs_cluster" "this" {
  name = "complyflow-cluster"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/complyflow-api"
  retention_in_days = 14
}

data "aws_iam_policy_document" "ecs_task_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Clean, purpose-built task role -- the console-era complyflow-api-task-role /
# complyflow-api-task-role1 pair were inconsistent half-finished experiments
# and are intentionally left alone rather than adopted here.
resource "aws_iam_role" "ecs_task" {
  name               = "complyflow-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
}

data "aws_iam_policy_document" "ecs_task_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${data.terraform_remote_state.backbone.outputs.uploads_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "complyflow-ecs-task-s3-access"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_permissions.json
}

resource "aws_ecs_task_definition" "api" {
  family                   = "complyflow-api-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # The image in ECR is arm64-only (built on Apple Silicon without a
  # cross-platform flag). Run the task on Graviton to match it, rather than
  # requiring an amd64 rebuild -- also cheaper per vCPU/GB than x86 Fargate.
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "complyflow-api"
      image     = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        { containerPort = 8000, protocol = "tcp" }
      ]
      environment = [
        { name = "BUCKET_NAME", value = data.terraform_remote_state.backbone.outputs.uploads_bucket_name }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "complyflow-api-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "complyflow-api"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}
