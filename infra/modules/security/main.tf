# --- 1. Automated Secret Management (Supports Special Characters) ---
resource "random_password" "token" {
  length           = 16
  special          = true
  override_special = "<$#!"
}

resource "aws_ssm_parameter" "token" {
  name  = "/${var.project_name}/auth_token"
  type  = "SecureString"
  value = random_password.token.result
}

resource "random_password" "grafana_admin" {
  length           = 16
  special          = true
  override_special = "<$#!"
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "/${var.project_name}/grafana_admin_password"
  type  = "SecureString"
  value = random_password.grafana_admin.result
}

# --- 2. Security Groups ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_node" {
  name        = "${var.project_name}-ecs-node-sg"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. ECS Execution Role (For pulling images and logs) ---
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "execution_ssm_read" {
  name = "${var.project_name}-exec-ssm-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = aws_ssm_parameter.grafana_admin_password.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "exec_ssm_read" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.execution_ssm_read.arn
}

# --- 4. ECS Task Role (Permissions for the App itself) ---
# This is the role from your logs that was getting "AccessDenied"
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "grafana_task_role" {
  name = "${var.project_name}-grafana-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read" {
  role       = aws_iam_role.grafana_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_policy" "app_permissions" {
  name = "${var.project_name}-app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SQS permissions for queue operations
        Effect   = "Allow"
        Action   = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = var.sqs_arn
      },
      {
        # S3 write access for processed payloads
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.bucket_arn}/*"
      },
      {
        # Permission to read the specific SSM Token
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.token.arn
      },
      {
        # Permission to decrypt the SecureString using the default SSM KMS key
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.app_permissions.arn
}

# --- 5. ECS EC2 Instance Role (For the Nodes to join the cluster) ---
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.ecs_instance_role.name
}
