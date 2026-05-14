variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Project name used for resource naming."
  type        = string
  default     = "synapse"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for private subnets."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c", "ap-northeast-2d"]
}

variable "eks_cluster_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.30"
}

variable "eks_node_instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "synapse"
}

variable "database_username" {
  description = "PostgreSQL admin username."
  type        = string
  default     = "synapse_admin"
}

variable "database_password" {
  description = "PostgreSQL admin password. Pass with TF_VAR_database_password or a secret manager."
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Redis AUTH token. Pass with TF_VAR_redis_auth_token or a secret manager."
  type        = string
  sensitive   = true
}

variable "admin_cidr_blocks" {
  description = "Temporary administrative CIDR blocks. Keep empty unless a controlled VPN/bastion path is approved."
  type        = list(string)
  default     = []
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version."
  type        = string
  default     = "7.3.11"
}
