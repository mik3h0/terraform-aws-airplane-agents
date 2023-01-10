data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  full_name_suffix = var.name_suffix == "" ? "" : "-${var.name_suffix}"
}

resource "aws_ecs_cluster" "cluster" {
  name  = "airplane-${var.name_suffix == "" ? resource.random_uuid.cluster_name_suffix.result : var.name_suffix}"
  count = var.cluster_arn == "" ? 1 : 0
}

resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = aws_ecs_cluster.cluster[0].name
  capacity_providers = ["FARGATE"]

  count = var.cluster_arn == "" ? 1 : 0
}

data "aws_subnet" "selected" {
  count = length(var.subnet_ids)
  id    = var.subnet_ids[count.index]
}

module "agent_security_group" {
  source = "terraform-aws-modules/security-group/aws"

  count = length(var.vpc_security_group_ids) > 0 ? 0 : 1

  name        = "airplane-agent${local.full_name_suffix}"
  description = "Security group for Airplane agent"
  vpc_id      = data.aws_subnet.selected[0].vpc_id

  egress_rules = ["all-all"]

  tags = var.tags
}

resource "aws_iam_policy" "default_run_policy" {
  path = "/airplane/"
  name = "DefaultRunRolePolicy${local.full_name_suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = join(":", ["arn:aws:secretsmanager", data.aws_region.current.name, data.aws_caller_identity.current.account_id, "secret:airplane/*"])
        Effect   = "Allow"
      },
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${resource.aws_cloudwatch_log_group.run_log_group.name}:*"
        Effect   = "Allow"
      },
      # Support pulling public ECR images with authentication
      {
        Action = [
          "ecr-public:GetAuthorizationToken",
          "sts:GetServiceBearerToken",
        ]
        Resource = "*"
        Effect   = "Allow"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "default_run_role" {
  path = "/airplane/"
  name = "DefaultRunRole${local.full_name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
  managed_policy_arns = concat(
    [
      aws_iam_policy.default_run_policy.arn
    ],
    var.additional_run_policy_arns
  )

  tags = var.tags
}

resource "aws_iam_role" "run_execution_role" {
  path = "/airplane/"
  name = "RunExecutionRole${local.full_name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    aws_iam_policy.default_run_policy.arn
  ]

  tags = var.tags
}

resource "aws_iam_role" "agent_role" {
  path = "/airplane/"
  name = "AgentTaskRole${local.full_name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  inline_policy {
    name = "AgentTaskRolePolicy"
    policy = jsonencode({
      Statement = concat([
        {
          Action = [
            "ecs:RunTask",
          ]
          Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/airplane-agentv2-*"
          Effect   = "Allow"
        },
        {
          Action = [
            "ecs:DescribeTasks",
            "ecs:ListTasks",
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "ecs:cluster" = var.cluster_arn == "" ? aws_ecs_cluster.cluster[0].arn : var.cluster_arn
            }
          }
          Effect = "Allow"
        },
        {
          Action = [
            "ecs:RegisterTaskDefinition",
            "ecs:DeregisterTaskDefinition",
            "ecs:ListTaskDefinitions",
            "ecs:TagResource",
            "secretsmanager:ListSecrets",
          ]
          Resource = "*"
          Effect   = "Allow"
        },
        {
          Action = [
            "logs:GetLogEvents",
          ]
          Resource = [
            "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${resource.aws_cloudwatch_log_group.run_log_group.name}:log-stream:*",
            "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${resource.aws_cloudwatch_log_group.agent_log_group.name}:log-stream:*",
          ]
          Effect = "Allow"
        },
        {
          Action = [
            "iam:PassRole",
          ]
          Resource = concat(
            [
              aws_iam_role.default_run_role.arn,
              aws_iam_role.run_execution_role.arn,
            ],
            var.allowed_iam_roles
          )
          Condition = {
            StringEquals = {
              "iam:PassedToService" = "ecs-tasks.amazonaws.com"
            }
            StringLike = {
              "iam:AssociatedResourceARN" = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/airplane-*"
            }
          }
          Effect = "Allow"
        },
        {
          Action = [
            "secretsmanager:CreateSecret",
            "secretsmanager:DeleteSecret",
            "secretsmanager:DescribeSecret",
            "secretsmanager:GetSecretValue",
            "secretsmanager:PutSecretValue",
            "secretsmanager:TagResource",
          ]
          Resource = join(":", ["arn:aws:secretsmanager", data.aws_region.current.name, data.aws_caller_identity.current.account_id, "secret:airplane/*"])
          Effect   = "Allow"
        },
        # Support pulling public ECR images with authentication
        {
          Action = [
            "ecr-public:GetAuthorizationToken",
            "sts:GetServiceBearerToken",
          ]
          Resource = "*"
          Effect   = "Allow"
        },
        ],
        length(var.private_repositories) == 0 ? [] : [{
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
          ]
          Resource = var.private_repositories
          Effect   = "Allow"
          },
          {
            Action = [
              "ecr:GetAuthorizationToken",
            ]
            Resource = ["*"]
            Effect   = "Allow"
        }],
        var.api_token_secret_arn == "" ? [] : [{
          Action = [
            "secretsmanager:GetSecretValue"
          ]
          Resource = var.api_token_secret_arn
          Effect   = "Allow"
        }],
        var.api_token_secret_kms_key_arn == "" ? [] : [{
          Action = [
            "kms:Decrypt"
          ]
          Resource = var.api_token_secret_kms_key_arn
          Effect   = "Allow"
      }])
    })
  }

  tags = var.tags
}

resource "aws_iam_role" "agent_execution_role" {
  path = "/airplane/"
  name = "AgentTaskExecutionRole${local.full_name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  inline_policy {
    name = "AgentTaskExecutionRolePolicy"
    policy = jsonencode({
      Statement = [
        {
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${resource.aws_cloudwatch_log_group.agent_log_group.name}:*"
          Effect   = "Allow"
        },
        # Support pulling public ECR images with authentication
        {
          Action = [
            "ecr-public:GetAuthorizationToken",
            "sts:GetServiceBearerToken",
          ]
          Resource = "*"
          Effect   = "Allow"
        },
      ]
    })
  }

  tags = var.tags
}

resource "random_uuid" "lock_key" {
}

resource "random_uuid" "cluster_name_suffix" {
}

resource "aws_ecs_task_definition" "agent_task_def" {
  family = "airplane-agent-task-def"
  container_definitions = jsonencode([
    {
      name  = "airplane-agent"
      image = "public.ecr.aws/airplanedev-prod/agentv2:1"
      environment = [
        { name = "AP_API_HOST", value = var.api_host },
        { name = "AP_API_TOKEN", value = var.api_token },
        { name = "AP_API_TOKEN_SECRET_ARN", value = var.api_token_secret_arn },
        { name = "AP_AUTO_UPGRADE", value = "true" },
        { name = "AP_AGENT_IMAGE", value = "public.ecr.aws/airplanedev-prod/agentv2:1" },
        { name = "AP_DEBUG_LOGGING", value = tostring(var.debug_logging) },
        { name = "AP_DEFAULT_CPU", value = var.default_task_cpu },
        { name = "AP_DEFAULT_MEMORY", value = var.default_task_memory },
        { name = "AP_DRIVER", value = "ecs" },
        { name = "AP_ECS_CLUSTER", value = var.cluster_arn == "" ? aws_ecs_cluster.cluster[0].arn : var.cluster_arn },
        { name = "AP_ECS_EXECUTION_ROLE", value = aws_iam_role.run_execution_role.arn },
        { name = "AP_ECS_TASK_ROLE", value = aws_iam_role.default_run_role.arn },
        { name = "AP_ECS_LOG_GROUP", value = aws_cloudwatch_log_group.run_log_group.name },
        { name = "AP_ECS_REGION", value = data.aws_region.current.name },
        { name = "AP_ECS_SECURITY_GROUPS", value = length(var.vpc_security_group_ids) > 0 ? join(",", var.vpc_security_group_ids) : join(",", [for sg in module.agent_security_group : sg.security_group_id]) },
        { name = "AP_ECS_SUBNETS", value = join(",", var.subnet_ids) },
        { name = "AP_ENV_SLUG", value = var.env_slug },
        { name = "AP_LABELS", value = join(" ", concat(["airplane_installer:terraform_ecs"], [for key, value in var.agent_labels : "${key}:${value}"])) },
        { name = "AP_TEAM_ID", value = var.team_id },
        { name = "AP_RUNNER_TEMPORAL_HOST", value = var.temporal_host },
        { name = "AP_LOCK_KEY", value = "fargate-${random_uuid.lock_key.result}-${var.team_id}" },
        { name = "AP_USE_ECR_PUBLIC_IMAGES", value = tostring(var.use_ecr_public_images) },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-group"         = aws_cloudwatch_log_group.agent_log_group.name
          "awslogs-stream-prefix" = "agentv2"
        }
      }
    }
  ])
  cpu                = var.agent_cpu
  memory             = var.agent_mem
  network_mode       = "awsvpc"
  task_role_arn      = aws_iam_role.agent_role.arn
  execution_role_arn = aws_iam_role.agent_execution_role.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]

  tags = var.tags
}

resource "aws_ecs_service" "agent_service" {
  name          = var.service_name
  cluster       = var.cluster_arn == "" ? aws_ecs_cluster.cluster[0].arn : var.cluster_arn
  desired_count = var.num_agents
  launch_type   = "FARGATE"
  network_configuration {
    assign_public_ip = true
    security_groups  = length(var.vpc_security_group_ids) > 0 ? toset(var.vpc_security_group_ids) : toset([for sg in module.agent_security_group : sg.security_group_id])
    subnets          = var.subnet_ids
  }
  task_definition = aws_ecs_task_definition.agent_task_def.arn

  propagate_tags = "SERVICE"
  tags           = var.tags
}

resource "aws_cloudwatch_log_group" "agent_log_group" {
  name_prefix = "/airplane/agents${local.full_name_suffix}"

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "run_log_group" {
  name_prefix = "/airplane/runs${local.full_name_suffix}"

  tags = var.tags
}
