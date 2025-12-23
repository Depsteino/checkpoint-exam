# Shared log group for ECS task logging
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"
}

locals {
  grafana_datasources_b64 = base64encode(file("${path.module}/../../grafana/datasources.yaml"))
  grafana_dashboards_b64  = base64encode(file("${path.module}/../../grafana/dashboards.yaml"))
  grafana_dashboard_b64   = base64encode(templatefile("${path.module}/../../grafana/dashboard.json.tmpl", {
    alb_arn_suffix     = var.alb_arn_suffix
    target_group_arn_suffix = var.target_group_arn_suffix
    alb_metric_az      = var.alb_metric_az
    grafana_dashboard_version = var.grafana_dashboard_version
    cluster_name       = "${var.project_name}-cluster"
    service_api_name   = "microservice-1-producer"
    service_worker_name = "microservice-2-consumer"
    log_group          = "/ecs/${var.project_name}"
  }))
  grafana_init_cmd = join("", [
    "mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards && ",
    "echo \"$GRAFANA_DATASOURCES_B64\" | base64 -d > /etc/grafana/provisioning/datasources/datasources.yaml && ",
    "echo \"$GRAFANA_DASHBOARDS_B64\" | base64 -d > /etc/grafana/provisioning/dashboards/dashboards.yaml && ",
    "echo \"$GRAFANA_DASHBOARD_B64\" | base64 -d > /var/lib/grafana/dashboards/microservices.json && ",
    "exec /run.sh"
  ])
}

# Service 1: API
resource "aws_ecs_task_definition" "ms1" {
  family                   = "microservice-1-producer"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu = 128
  memory = 128
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([{
    name = "microservice-1-producer"
    image = "${var.repo_urls[0]}:latest"
    cpu = 128
    memory = 128
    essential = true
    portMappings = [{ containerPort = 8080, hostPort = 0 }]
    environment = [
      { name = "SQS_QUEUE_URL", value = var.sqs_url },
      { name = "SSM_PARAM_NAME", value = var.ssm_param_name },
      { name = "AWS_REGION", value = "us-east-1" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/${var.project_name}"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "microservice-1-producer"
      }
    }
  }])
}

resource "aws_ecs_service" "ms1" {
  name            = "microservice-1-producer"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.ms1.arn
  desired_count   = 1
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "microservice-1-producer"
    container_port   = 8080
  }
}

# Service 2: Worker
resource "aws_ecs_task_definition" "ms2" {
  family                   = "microservice-2-consumer"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu = 128
  memory = 128
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([{
    name = "microservice-2-consumer"
    image = "${var.repo_urls[1]}:latest"
    cpu = 128
    memory = 128
    essential = true
    environment = [
      { name = "SQS_QUEUE_URL", value = var.sqs_url },
      { name = "S3_BUCKET_NAME", value = var.bucket_id },
      { name = "AWS_REGION", value = "us-east-1" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/${var.project_name}"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "microservice-2-consumer"
      }
    }
  }])
}

resource "aws_ecs_service" "ms2" {
  name            = "microservice-2-consumer"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.ms2.arn
  desired_count   = 1
  launch_type     = "EC2"
}

# Grafana (Monitoring UI)
resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu = 128
  memory = 128
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.grafana_task_role_arn

  container_definitions = jsonencode([{
    name = "grafana"
    image = "grafana/grafana:10.2.3"
    cpu = 128
    memory = 128
    essential = true
    portMappings = [{ containerPort = 3000, hostPort = 0 }]
    environment = [
      { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
      { name = "GF_SERVER_DOMAIN", value = var.alb_dns },
      { name = "GF_SERVER_ROOT_URL", value = "http://${var.alb_dns}/grafana/" },
      { name = "GF_SERVER_SERVE_FROM_SUB_PATH", value = "true" },
      { name = "AWS_REGION", value = "us-east-1" },
      { name = "AWS_DEFAULT_REGION", value = "us-east-1" },
      { name = "GRAFANA_DATASOURCES_B64", value = local.grafana_datasources_b64 },
      { name = "GRAFANA_DASHBOARDS_B64", value = local.grafana_dashboards_b64 },
      { name = "GRAFANA_DASHBOARD_B64", value = local.grafana_dashboard_b64 }
    ]
    secrets = [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = var.grafana_admin_password_param_arn }
    ]
    entryPoint = ["/bin/sh", "-c"]
    command = [local.grafana_init_cmd]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/${var.project_name}"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "grafana"
      }
    }
  }])
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = var.grafana_target_group_arn
    container_name   = "grafana"
    container_port   = 3000
  }
}
