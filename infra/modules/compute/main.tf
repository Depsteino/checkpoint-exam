# --- ALB ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "instance"
  health_check { path = "/health" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check { path = "/api/health" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
  condition {
    path_pattern { values = ["/grafana*"] }
  }
}

# --- ECS Cluster & ASG ---
resource "aws_ecs_cluster" "main" { name = "${var.project_name}-cluster" }

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.micro" # Free Tier

  iam_instance_profile { name = var.instance_profile_name }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.ecs_sg_id]
  }
  user_data = base64encode("#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config")
}

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = var.public_subnets
  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }
  min_size         = 1
  max_size         = 2
  desired_capacity = 1
  tag {
    key = "AmazonECSManaged"
    value = true
    propagate_at_launch = true
  }
}
