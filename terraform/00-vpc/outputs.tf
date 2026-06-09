output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "All private subnet IDs (both AZs) — used for the EKS control plane"
  value       = module.vpc.private_subnets
}

output "backend_subnet_id" {
  description = "AZ-a private subnet — hosts the WEKA backend placement group and the EKS client node group"
  value       = module.vpc.private_subnets[0]
}

output "alb_subnet_id" {
  description = "AZ-b private subnet — second AZ required by the WEKA ALB"
  value       = module.vpc.private_subnets[1]
}

output "azs" {
  description = "Availability zones in use"
  value       = module.vpc.azs
}

output "key_pair_name" {
  description = "Name of the auto-generated EC2 key pair (consumed by the WEKA backend layer)"
  value       = aws_key_pair.main.key_name
}

output "private_key_path" {
  description = "Local path to the generated private key (0600, git-ignored)"
  value       = local_sensitive_file.private_key.filename
}
