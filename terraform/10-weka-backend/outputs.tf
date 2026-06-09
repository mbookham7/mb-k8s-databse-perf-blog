output "weka_deployment_output" {
  description = "Full output from the upstream weka/weka/aws module"
  value       = module.weka_backend.weka_deployment_output
  sensitive   = false
}

output "cluster_name" {
  description = "WEKA backend cluster name (use as --backend-name for the deploy/generate scripts)"
  value       = var.cluster_name
}

output "backend_sg_ids" {
  description = "Security group IDs of the WEKA backend (attach to EKS nodes so clients can reach the cluster)"
  value       = module.weka_backend.weka_deployment_output.sg_ids
}

output "weka_secret_arn" {
  description = "Secrets Manager secret holding the WEKA admin password (use as --secret-arn)"
  value       = module.weka_backend.weka_deployment_output.weka_cluster_admin_password_secret_id
}

output "alb_dns_name" {
  description = "WEKA ALB DNS name (web UI / API on port 14000)"
  value       = module.weka_backend.weka_deployment_output.alb_dns_name
}

output "get_password_command" {
  description = "Shell command to retrieve the WEKA admin password"
  value       = module.weka_backend.weka_deployment_output.cluster_helper_commands.get_password
}
