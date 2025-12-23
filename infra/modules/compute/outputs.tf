output "cluster_id" { value = aws_ecs_cluster.main.id }
output "target_group_arn" { value = aws_lb_target_group.app.arn }
output "target_group_arn_suffix" { value = aws_lb_target_group.app.arn_suffix }
output "grafana_target_group_arn" { value = aws_lb_target_group.grafana.arn }
output "alb_dns" { value = aws_lb.main.dns_name }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
