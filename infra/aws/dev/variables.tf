variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_node_instance_type" {
  description = "EKS node instance type"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_count" {
  description = "Number of EKS worker nodes (>=4 for observability + 5/5 app capacity)"
  type        = number
  default     = 4
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_db_name" {
  description = "RDS database name"
  type        = string
  default     = "synapse"
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
  default     = "synapse_admin"
  sensitive   = true
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

variable "msk_broker_count" {
  description = "Number of MSK brokers"
  type        = number
  default     = 3
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_auth_token" {
  description = "Redis AUTH token"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Base domain for staging hosts (e.g. example.com). Empty disables ACM."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for domain_name. Required if domain_name set."
  type        = string
  default     = ""
}
