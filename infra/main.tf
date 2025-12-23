terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" { region = "us-east-1" }

variable "project_name" { default = "candidate-2" }
variable "grafana_dashboard_version" { default = "unknown" }

# 1. Pipes
module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = "10.0.0.0/16"
}

# 2. Locks & Keys
module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  bucket_arn   = module.storage.bucket_arn
  sqs_arn      = module.storage.sqs_arn
}

# 3. Hard Drives
module "storage" {
  source       = "./modules/storage"
  project_name = var.project_name
}

# 4. Engines
module "compute" {
  source                = "./modules/compute"
  project_name          = var.project_name
  vpc_id                = module.networking.vpc_id
  public_subnets        = module.networking.public_subnets
  alb_sg_id             = module.security.alb_sg_id
  ecs_sg_id             = module.security.ecs_sg_id
  instance_profile_name = module.security.instance_profile_name
}

# 5. Apps
module "services" {
  source             = "./modules/services"
  cluster_id         = module.compute.cluster_id
  project_name       = var.project_name
  execution_role_arn = module.security.execution_role_arn
  task_role_arn      = module.security.task_role_arn
  grafana_task_role_arn        = module.security.grafana_task_role_arn
  repo_urls          = module.storage.repo_urls
  sqs_url            = module.storage.sqs_url
  bucket_id          = module.storage.bucket_id
  ssm_param_name     = module.security.ssm_param_name
  target_group_arn   = module.compute.target_group_arn
  grafana_target_group_arn     = module.compute.grafana_target_group_arn
  grafana_admin_password_param_arn = module.security.grafana_admin_password_param_arn
  alb_dns            = module.compute.alb_dns
  alb_arn_suffix     = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  alb_metric_az      = module.networking.public_subnet_azs[0]
  grafana_dashboard_version = var.grafana_dashboard_version
}
