# Project configuration
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "meddataflow"
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "us-central1-a"
}

# Domain configuration
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# Database configuration
variable "database_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "meddataflow"
}

variable "database_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "meddataflow_user"
}

variable "database_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "db_instance_type" {
  description = "Cloud SQL instance type"
  type        = string
  default     = "db-f1-micro"  # For development, use db-n1-standard-1 for production
}

# Environment configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Security
variable "jwt_secret_key" {
  description = "JWT secret key for signing tokens (64+ chars recommended)"
  type        = string
  sensitive   = true
}

variable "waf_sqli_bypass_path_regex" {
  description = "Regex for request.path to skip Cloud Armor SQLi inspection (use only for endpoints that legitimately carry SQL/code)."
  type        = string
  default     = "^/api/auth"
}

# Container image tags
variable "backend_image_tag" {
  description = "Backend container image tag"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Frontend container image tag"
  type        = string
  default     = "latest"
}
