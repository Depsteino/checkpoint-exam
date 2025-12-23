output "alb_url" { value = module.compute.alb_dns }
output "ecr_repos" { value = module.storage.repo_urls }
output "ssm_param" { value = module.security.ssm_param_name }
output "grafana_url" { value = "http://${module.compute.alb_dns}/grafana/" }
output "grafana_admin_password_param" { value = module.security.grafana_admin_password_param_name }
