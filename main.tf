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

resource "aws_security_group" "agent_security_group" {
  name        = "airplane-agent${local.full_name_suffix}"
  description = "Security group for Airplane agent"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  tags = {
    "Name" : "airplane-agent${local.full_name_suffix}",
  }

  count = length(var.vpc_security_group_ids) > 0 ? 0 : 1
}

resource "aws_security_group_rule" "agent_egress_rule" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.agent_security_group[0].id

  count = length(var.vpc_security_group_ids) > 0 ? 0 : 1
}

resource "aws_security_group" "tasks_security_group" {
  name        = "airplane-tasks${local.full_name_suffix}"
  description = "Security group for Airplane runner tasks"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  tags = {
    "Name" : "airplane-tasks${local.full_name_suffix}",
  }

  count = length(var.vpc_security_group_ids) > 0 ? 0 : 1
}

resource "aws_security_group_rule" "tasks_egress_rule" {
  type              = "egress"
  protocol          = "all"
  from_port         = -1
  to_port           = -1
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.tasks_security_group[0].id

  count = length(var.vpc_security_group_ids) > 0 ? 0 : 1
}

resource "aws_iam_policy" "default_run_policy" {
  name_prefix = var.default_run_policy_prefix
  path        = "/airplane/"
  name        = "DefaultRunRolePolicy${local.full_name_suffix}"
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
  name_prefix = var.default_run_role_prefix
  path        = "/airplane/"
  name        = "DefaultRunRole${local.full_name_suffix}"
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
  name_prefix = var.run_execution_role_prefix
  path        = "/airplane/"
  name        = "RunExecutionRole${local.full_name_suffix}"
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
  name_prefix = var.agent_role_prefix
  path        = "/airplane/"
  name        = "AgentTaskRole${local.full_name_suffix}"
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
        {
          Action = [
            "ecr:GetAuthorizationToken",
          ]
          Resource = "*"
          Effect   = "Allow"
        },
        ],
        var.ecr_cache ? [
          {
            # Support full read/write permissions on the cache repo
            Action = [
              "ecr:BatchGetImage",
              "ecr:BatchCheckLayerAvailability",
              "ecr:BatchDeleteImage",
              "ecr:CompleteLayerUpload",
              "ecr:DescribeImages",
              "ecr:GetDownloadUrlForLayer",
              "ecr:InitiateLayerUpload",
              "ecr:PutImage",
              "ecr:UploadLayerPart",
            ]
            Resource = aws_ecr_repository.ecr_cache[0].arn
            Effect   = "Allow"
          },
        ] : [],
        var.self_hosted_data_plane ? [
          {
            Action = [
              "s3:ListBucket",
            ]
            Resource = aws_s3_bucket.data_plane[0].arn
            Effect   = "Allow"
          },
          {
            Action = [
              "s3:*Object",
            ]
            Resource = "${aws_s3_bucket.data_plane[0].arn}/*"
            Effect   = "Allow"
          },
        ] : [],
        length(var.private_repositories) == 0 ? [] : [{
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
          ]
          Resource = var.private_repositories
          Effect   = "Allow"
          },
        ],
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
  name_prefix = var.agent_execution_role_prefix
  path        = "/airplane/"
  name        = "AgentTaskExecutionRole${local.full_name_suffix}"
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
  family = "airplane-agent-task-def${local.full_name_suffix}"
  container_definitions = jsonencode([
    {
      name  = "airplane-agent"
      image = var.agent_image
      environment = [
        { name = "AP_API_HOST", value = var.api_host },
        { name = "AP_API_TOKEN", value = var.api_token },
        { name = "AP_API_TOKEN_SECRET_ARN", value = var.api_token_secret_arn },
        { name = "AP_AUTO_UPGRADE", value = "true" },
        { name = "AP_AGENT_IMAGE", value = var.agent_image },
        { name = "AP_DEBUG_LOGGING", value = tostring(var.debug_logging) },
        { name = "AP_DEFAULT_CPU", value = var.default_task_cpu },
        { name = "AP_DEFAULT_MEMORY", value = var.default_task_memory },
        { name = "AP_DRIVER", value = "ecs" },
        { name = "AP_ECR_CACHE_URL", value = var.ecr_cache ? aws_ecr_repository.ecr_cache[0].repository_url : "" },
        { name = "AP_ECS_CLUSTER", value = var.cluster_arn == "" ? aws_ecs_cluster.cluster[0].arn : var.cluster_arn },
        { name = "AP_ECS_CPU_ARCHITECTURE", value = var.cpu_architecture },
        { name = "AP_ECS_EXECUTION_ROLE", value = aws_iam_role.run_execution_role.arn },
        { name = "AP_ECS_TASK_ROLE", value = aws_iam_role.default_run_role.arn },
        { name = "AP_ECS_LOG_GROUP", value = aws_cloudwatch_log_group.run_log_group.name },
        { name = "AP_ECS_REGION", value = data.aws_region.current.name },
        { name = "AP_ECS_SECURITY_GROUPS", value = length(var.vpc_security_group_ids) > 0 ? join(",", var.vpc_security_group_ids) : join(",", [for sg in aws_security_group.tasks_security_group : sg.id]) },
        { name = "AP_ECS_SUBNETS", value = join(",", var.subnet_ids) },
        { name = "AP_ENV_SLUG", value = var.env_slug },
        { name = "AP_GCP_PROJECT_ID", value = var.gcp_project_id },
        { name = "AP_GAR_REPO_URL", value = "us-central1-docker.pkg.dev/${var.gcp_project_id}" },
        { name = "AP_LABELS", value = join(" ", concat(["airplane_installer:terraform_ecs"], [for key, value in var.agent_labels : "${key}:${value}"])) },
        { name = "AP_LOCK_KEY", value = "fargate-${random_uuid.lock_key.result}" },
        { name = "AP_RUNNER_TEMPORAL_HOST", value = var.temporal_host },
        { name = "AP_TEAM_ID", value = var.team_id },
        { name = "AP_USE_ECR_PUBLIC_IMAGES", value = tostring(var.use_ecr_public_images) },

        // Self-hosted data plane settings
        { name = "AP_DATA_PLANE_ENABLED", value = tostring(var.self_hosted_data_plane) },
        { name = "AP_DATA_PLANE_TEAM_ID", value = var.self_hosted_data_plane ? var.team_id : "" },
        { name = "AP_DATA_PLANE_ZONE_SLUG", value = var.self_hosted_data_plane ? var.zone_slug : "" },
        { name = "AP_DATA_PLANE_INTERNAL_HOST", value = var.self_hosted_data_plane ? "http://${aws_alb.internal[0].dns_name}" : "" },
        { name = "AP_DATA_PLANE_EXTERNAL_URL", value = var.self_hosted_data_plane ? "https://${var.zone_slug}.${var.team_id}.${var.data_plane_domain}" : "" },
        { name = "AP_DATA_PLANE_JWT_PUBLIC_KEY", value = var.self_hosted_data_plane ? "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUF4T2pDcUxRNzZzWDBKUjhObTVoMAo5QkpYeGswN3lCNCt0Y2x1WDVDaDA5MVR2UlJ0dXJaeGtiSEFmK1lxT3RoTk5EVmtSbHJUUlZUVEY0WnZIMmRWCnJabDJkZmRlLzlSMURwOGZPRFZhemlaNmg0V29md1hlWFZyYVZXZDJkRVN2Qk83eEpPRmltQkxFd2dUOHlpRk4KNkt2VW5wMEhZL0xobUxZY0NPWVVyUWY3WlhhUEF6ckt1NTkxdm1WN254d3hrSDBuQkU3RHRVTVZVYjFRYlFxdQo3NGlQdU5xVy9rL3dtZ2twQU5JbENvc05yb0tGd002c3gvUWs1TW9UUm51UnROL1hOckJIVlBCWlI4Z1BZb1BDCnp1WStaS0xCRGlubW1CWENVVjNXVDRLTFFvZXB4aGtDNlB5ZVVzUHB4Nmw1Ylc0NTFRSUNSMkVLV0FxUkN6NVUKQlo4aWJKRUZnZkcycHE0QllWQ1NQYnZyMTBVdERMSWp4b2sreWFYOXNnc09qclE3YVY1VkNDRVNEQjNpdFdpbAo0WDB2MzJDYzBUNjVaLzF0eThjODNWS0JjUkE0TEtGOUlIYXhiRmE0Z2xCQ2dXTEQ5TkFaZG9wckhFU0xObkIwCjFnNElpcEdHN2lxNFhld2laRkxBN1AzUzBjRTNXenhlcVVkby9NWnFFOVlscjVWZVY2Y0F6dTA0ZW1rdGptaTkKTE5SVEt5Sm1KL1lSWjlOUWlIb3lHUVBOemRpVjlGT1hjVmI2V2NLV0JCcTJBR1ZpUkdmWFMrOWJ5TG5rSVVtSwpwdS94VFlwR20rSXVnTGkyeXV6anduUDRINjJJckFwOUJTODNNMjJxaXg3cVkxNHZxMXJlek52RFhUWFptWEk2CjJTbGt4RGNxLy9reGdJRXVRR1VLdjBzQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo=" : "" },
        { name = "AP_DATA_PLANE_S3_DATA_PLANE_BUCKET", value = var.self_hosted_data_plane ? aws_s3_bucket.data_plane[0].id : "" },
        { name = "AP_DATA_PLANE_REDIS_HOST", value = var.self_hosted_data_plane ? "${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:${aws_elasticache_cluster.redis[0].cache_nodes[0].port}" : "" },
      ]
      portMappings = [
        {
          containerPort = 2189
        },
        {
          containerPort = 2190
        }
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
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]

  tags = var.tags
}

resource "aws_ecs_service" "agent_service" {
  name          = "${var.service_name}${local.full_name_suffix}"
  cluster       = var.cluster_arn == "" ? aws_ecs_cluster.cluster[0].arn : var.cluster_arn
  desired_count = var.num_agents
  launch_type   = "FARGATE"
  network_configuration {
    assign_public_ip = var.assign_public_agent_ip
    security_groups  = length(var.vpc_security_group_ids) > 0 ? toset(var.vpc_security_group_ids) : toset([for sg in aws_security_group.agent_security_group : sg.id])
    subnets          = var.subnet_ids
  }
  task_definition = aws_ecs_task_definition.agent_task_def.arn

  propagate_tags = "SERVICE"
  tags           = var.tags

  count = var.self_hosted_data_plane ? 0 : 1
}

resource "aws_ecr_repository" "ecr_cache" {
  name                 = "airplane-cache${local.full_name_suffix}"
  image_tag_mutability = "MUTABLE"
  count                = var.ecr_cache ? 1 : 0
}

resource "aws_cloudwatch_log_group" "agent_log_group" {
  name_prefix = "/airplane/agents${local.full_name_suffix}"

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "run_log_group" {
  name_prefix = "/airplane/runs${local.full_name_suffix}"

  tags = var.tags
}
