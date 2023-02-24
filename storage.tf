// Agent storage Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "airplane-redis${local.full_name_suffix}"
  subnet_ids = var.subnet_ids

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group" "redis" {
  name        = "airplane-redis${local.full_name_suffix}"
  description = "Security group for Airplane redis"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  tags = {
    "Name" : "airplane-redis${local.full_name_suffix}",
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "redis_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis[0].id
  source_security_group_id = aws_security_group.agent_security_group[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "airplane-redis${local.full_name_suffix}"
  engine               = "redis"
  node_type            = "cache.t3.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  engine_version       = "6.2"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis[0].id]

  count = var.self_hosted_agent_storage ? 1 : 0
}

// Agent storage bucket
resource "aws_s3_bucket" "agent_storage" {
  bucket = "airplane-data-${var.team_id}${local.full_name_suffix}"

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_s3_bucket_public_access_block" "agent_storage" {
  bucket = aws_s3_bucket.agent_storage[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  count = var.self_hosted_agent_storage ? 1 : 0
}

// External ALB
resource "aws_security_group" "external_alb" {
  name        = "ap-alb-ext${local.full_name_suffix}"
  description = "Security group for Airplane external LB"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  tags = {
    "Name" : "ap-alb-ext${local.full_name_suffix}",
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "external_alb_ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.external_alb[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "external_alb_https_ingress_rule" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.external_alb[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "external_alb_egress" {
  type                     = "egress"
  from_port                = 2190
  to_port                  = 2190
  protocol                 = "tcp"
  security_group_id        = aws_security_group.external_alb[0].id
  source_security_group_id = aws_security_group.agent_security_group[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb" "external" {
  name            = "ap-alb-ext${local.full_name_suffix}"
  internal        = false
  security_groups = [aws_security_group.external_alb[0].id]
  subnets         = var.subnet_ids

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb_target_group" "external" {
  name        = "ap-alb-ext${local.full_name_suffix}"
  port        = 2190
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  target_type = "ip"

  health_check {
    path = "/healthz"
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

data "aws_secretsmanager_secret" "api_token_secret" {
  arn = var.api_token_secret_arn

  count = var.api_token_secret_arn == "" ? 0 : 1
}

data "aws_secretsmanager_secret_version" "api_token_secret_version" {
  secret_id = data.aws_secretsmanager_secret.api_token_secret[0].id

  count = var.api_token_secret_arn == "" ? 0 : 1
}

data "http" "verify_zone_dns" {
  url    = "${var.api_host}/v0/zones/updateDNS"
  method = "POST"

  request_headers = {
    "X-Airplane-API-Key" = var.api_token_secret_arn != "" ? data.aws_secretsmanager_secret_version.api_token_secret_version[0].secret_string : var.api_token
  }
  request_body = jsonencode({
    verificationCName = tolist(aws_acm_certificate.alb_external_certificate[0].domain_validation_options)[0].resource_record_name
    verificationValue = tolist(aws_acm_certificate.alb_external_certificate[0].domain_validation_options)[0].resource_record_value
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Status code invalid"
    }
  }
  count = var.self_hosted_agent_storage ? 1 : 0
}

data "http" "update_external_alb_dns" {
  url    = "${var.api_host}/v0/zones/updateDNS"
  method = "POST"

  request_headers = {
    "X-Airplane-API-Key" = var.api_token_secret_arn != "" ? data.aws_secretsmanager_secret_version.api_token_secret_version[0].secret_string : var.api_token
  }
  request_body = jsonencode({
    hostname             = "${var.zone_slug}.${var.team_id}.${var.agent_storage_domain}."
    loadBalancerHostname = "${aws_alb.external[0].dns_name}."
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Status code invalid"
    }
  }
  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_acm_certificate" "alb_external_certificate" {
  domain_name       = "${var.zone_slug}.${var.team_id}.${var.agent_storage_domain}"
  validation_method = "DNS"
  count             = var.self_hosted_agent_storage ? 1 : 0

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "alb_external_certificate_validation" {
  certificate_arn = aws_acm_certificate.alb_external_certificate[0].arn
  count           = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb_listener" "alb_external_https" {
  load_balancer_arn = aws_alb.external[0].arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.alb_external_certificate[0].arn

  default_action {
    target_group_arn = aws_alb_target_group.external[0].arn
    type             = "forward"
  }

  count = var.self_hosted_agent_storage ? 1 : 0
  depends_on = [
    resource.aws_acm_certificate_validation.alb_external_certificate_validation[0]
  ]
}

// Internal ALB
resource "aws_security_group" "internal_alb" {
  name        = "ap-alb-int${local.full_name_suffix}"
  description = "Security group for Airplane internal LB"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  tags = {
    "Name" : "ap-alb-int${local.full_name_suffix}",
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "internal_alb_ingress" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.internal_alb[0].id
  source_security_group_id = aws_security_group.tasks_security_group[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "internal_alb_egress" {
  type                     = "egress"
  from_port                = 2189
  to_port                  = 2189
  protocol                 = "tcp"
  security_group_id        = aws_security_group.internal_alb[0].id
  source_security_group_id = aws_security_group.agent_security_group[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb" "internal" {
  name            = "ap-alb-int${local.full_name_suffix}"
  internal        = true
  security_groups = [aws_security_group.internal_alb[0].id]
  subnets         = var.subnet_ids
  count           = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb_target_group" "internal" {
  name        = "ap-alb-int${local.full_name_suffix}"
  port        = 2189
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.selected[0].vpc_id
  target_type = "ip"

  health_check {
    path = "/healthz"
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_alb_listener" "internal_alb_http" {
  load_balancer_arn = aws_alb.internal[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.internal[0].arn
    type             = "forward"
  }

  count = var.self_hosted_agent_storage ? 1 : 0
}

// Extra agent security group rules
resource "aws_security_group_rule" "agent_egress_redis" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.agent_security_group[0].id
  source_security_group_id = aws_security_group.redis[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "agent_ingress_internal_alb" {
  type                     = "ingress"
  from_port                = 2189
  to_port                  = 2189
  protocol                 = "tcp"
  security_group_id        = aws_security_group.agent_security_group[0].id
  source_security_group_id = aws_security_group.internal_alb[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_security_group_rule" "agent_ingress_external_alb" {
  type                     = "ingress"
  from_port                = 2190
  to_port                  = 2190
  protocol                 = "tcp"
  security_group_id        = aws_security_group.agent_security_group[0].id
  source_security_group_id = aws_security_group.external_alb[0].id

  count = var.self_hosted_agent_storage ? 1 : 0
}

resource "aws_ecs_service" "agent_service_self_hosted_storage" {
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

  load_balancer {
    target_group_arn = aws_alb_target_group.internal[0].arn
    container_name   = "airplane-agent"
    container_port   = 2189
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.external[0].arn
    container_name   = "airplane-agent"
    container_port   = 2190
  }

  propagate_tags = "SERVICE"
  tags           = var.tags

  count = var.self_hosted_agent_storage ? 1 : 0
}
