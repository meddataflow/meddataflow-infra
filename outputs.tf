# Network outputs
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.meddataflow_vpc.name
}

output "private_subnet_name" {
  description = "Name of the private subnet"
  value       = google_compute_subnetwork.private_subnet.name
}

# Container Registry outputs
output "artifact_registry_repository" {
  description = "Artifact Registry repository URL"
  value       = google_artifact_registry_repository.meddataflow_repo.name
}

output "container_registry_hostname" {
  description = "Container registry hostname for pushing images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}"
}

# Database outputs
output "database_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.meddataflow_postgres.name
}

output "database_private_ip" {
  description = "Cloud SQL instance private IP"
  value       = google_sql_database_instance.meddataflow_postgres.private_ip_address
  sensitive   = true
}

output "database_connection_string" {
  description = "Database connection string"
  # URL-encode credentials in output as well, to reflect the actual env used by Cloud Run
  value       = "postgresql://${urlencode(var.database_user)}:${urlencode(var.database_password)}@${google_sql_database_instance.meddataflow_postgres.private_ip_address}:5432/${var.database_name}"
  sensitive   = true
}

# Cloud Run service outputs
output "backend_service_url" {
  description = "Backend Cloud Run service URL"
  value       = google_cloud_run_service.meddataflow_backend.status[0].url
}

output "frontend_service_url" {
  description = "Frontend Cloud Run service URL"
  value       = google_cloud_run_service.meddataflow_frontend.status[0].url
}

# Load Balancer outputs
output "load_balancer_ip" {
  description = "Load balancer external IP address"
  value       = google_compute_global_address.meddataflow_ip.address
}

output "application_url" {
  description = "Application URL"
  value       = "https://${var.domain_name}"
}

# DNS Configuration instructions
output "dns_configuration" {
  description = "DNS A record configuration for your domain"
  value = {
    name  = var.domain_name
    type  = "A"
    value = google_compute_global_address.meddataflow_ip.address
    ttl   = 300
  }
}

# Deployment commands
output "docker_push_commands" {
  description = "Commands to build and push Docker images"
  value = {
    configure_auth = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    backend_push = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-backend:latest ./backend && docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-backend:latest"
    frontend_push = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-frontend:latest ./frontend && docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-frontend:latest"
  }
}
