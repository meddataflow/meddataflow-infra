# Configure Terraform and Google Cloud provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "containerregistry.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com"
  ])

  service = each.value
  disable_dependent_services = true
}

# Wait for APIs to be fully activated
resource "time_sleep" "wait_for_apis" {
  depends_on = [time_sleep.wait_for_apis]
  create_duration = "60s"
}

# Create VPC Network
resource "google_compute_network" "meddataflow_vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.wait_for_apis]
}

# Create private subnet for Cloud Run services
resource "google_compute_subnetwork" "private_subnet" {
  name          = "${var.project_name}-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.meddataflow_vpc.id

  private_ip_google_access = true
}

# Create VPC connector for Cloud Run to access private resources
resource "google_vpc_access_connector" "meddataflow_connector" {
  name          = "${var.project_name}-vpc-connector"
  region        = var.region
  ip_cidr_range = "10.1.0.0/28"
  network       = google_compute_network.meddataflow_vpc.name

  depends_on = [time_sleep.wait_for_apis]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "meddataflow_repo" {
  location      = var.region
  repository_id = "${var.project_name}-repo"
  description   = "MedDataFlow application container images"
  format        = "DOCKER"

  depends_on = [time_sleep.wait_for_apis]
}

# Create Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "meddataflow_postgres" {
  name             = "${var.project_name}-postgres"
  database_version = "POSTGRES_15"
  region           = var.region
  deletion_protection = false

  settings {
    tier = var.db_instance_type

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.meddataflow_vpc.id
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    backup_configuration {
      enabled = true
      start_time = "03:00"
      backup_retention_settings {
        retained_backups = 7
      }
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Create private services connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.project_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.meddataflow_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.meddataflow_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Create database and user
resource "google_sql_database" "meddataflow_database" {
  name     = var.database_name
  instance = google_sql_database_instance.meddataflow_postgres.name
}

resource "google_sql_user" "meddataflow_user" {
  name     = var.database_user
  instance = google_sql_database_instance.meddataflow_postgres.name
  password = var.database_password
}

# Create Cloud Run service for backend
resource "google_cloud_run_service" "meddataflow_backend" {
  name     = "${var.project_name}-backend"
  location = var.region

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = "10"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.meddataflow_connector.name
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
      }
    }

    spec {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-backend:latest"

        ports {
          container_port = 8001
        }

        env {
          name  = "DATABASE_URL"
          # URL-encode credentials to avoid breaking DSN when special characters (e.g. '?') are present
          value = "postgresql://${urlencode(var.database_user)}:${urlencode(var.database_password)}@${google_sql_database_instance.meddataflow_postgres.private_ip_address}:5432/${var.database_name}"
        }

        env {
          name  = "ENVIRONMENT"
          value = "production"
        }

        env {
          name  = "FRONTEND_URL"
          value = "https://${var.domain_name}"
        }

        env {
          name  = "JWT_SECRET_KEY"
          value = var.jwt_secret_key
        }

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
        }
      }

      service_account_name = google_service_account.meddataflow_backend_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Create Cloud Run service for frontend
resource "google_cloud_run_service" "meddataflow_frontend" {
  name     = "${var.project_name}-frontend"
  location = var.region

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "5"
      }
    }

    spec {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.meddataflow_repo.repository_id}/meddataflow-frontend:latest"

        ports {
          container_port = 3000
        }

        env {
          name  = "NEXT_PUBLIC_API_URL"
          value = google_cloud_run_service.meddataflow_backend.status[0].url
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Service accounts for Cloud Run services
resource "google_service_account" "meddataflow_backend_sa" {
  account_id   = "${var.project_name}-backend-sa"
  display_name = "MedDataFlow Backend Service Account"
}

resource "google_service_account" "meddataflow_frontend_sa" {
  account_id   = "${var.project_name}-frontend-sa"
  display_name = "MedDataFlow Frontend Service Account"
}

# IAM bindings for service accounts
resource "google_project_iam_member" "backend_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.meddataflow_backend_sa.email}"
}

# Allow public access to Cloud Run services (we'll restrict via Load Balancer)
resource "google_cloud_run_service_iam_member" "backend_public" {
  service  = google_cloud_run_service.meddataflow_backend.name
  location = google_cloud_run_service.meddataflow_backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "frontend_public" {
  service  = google_cloud_run_service.meddataflow_frontend.name
  location = google_cloud_run_service.meddataflow_frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Global IP address for Load Balancer
resource "google_compute_global_address" "meddataflow_ip" {
  name = "${var.project_name}-global-ip"

  depends_on = [time_sleep.wait_for_apis]
}

# SSL certificate (managed by Google)
resource "google_compute_managed_ssl_certificate" "meddataflow_ssl_cert" {
  name = "${var.project_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Network Endpoint Groups for Cloud Run services
resource "google_compute_region_network_endpoint_group" "backend_neg" {
  name                  = "${var.project_name}-backend-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.meddataflow_backend.name
  }
}

resource "google_compute_region_network_endpoint_group" "frontend_neg" {
  name                  = "${var.project_name}-frontend-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.meddataflow_frontend.name
  }
}

# Backend services
resource "google_compute_backend_service" "backend_service" {
  name                            = "${var.project_name}-backend-service"
  connection_draining_timeout_sec = 10

  backend {
    group = google_compute_region_network_endpoint_group.backend_neg.id
  }
}

resource "google_compute_backend_service" "frontend_service" {
  name                            = "${var.project_name}-frontend-service"
  connection_draining_timeout_sec = 10

  backend {
    group = google_compute_region_network_endpoint_group.frontend_neg.id
  }
}

# URL map for routing
resource "google_compute_url_map" "meddataflow_url_map" {
  name            = "${var.project_name}-url-map"
  default_service = google_compute_backend_service.frontend_service.id

  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.frontend_service.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.backend_service.id
    }

    path_rule {
      paths   = ["/docs/*"]
      service = google_compute_backend_service.backend_service.id
    }
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "meddataflow_https_proxy" {
  name             = "${var.project_name}-https-proxy"
  url_map          = google_compute_url_map.meddataflow_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.meddataflow_ssl_cert.id]
}

# Global forwarding rule (Load Balancer entry point)
resource "google_compute_global_forwarding_rule" "meddataflow_forwarding_rule" {
  name       = "${var.project_name}-forwarding-rule"
  target     = google_compute_target_https_proxy.meddataflow_https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.meddataflow_ip.address
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "meddataflow_http_redirect" {
  name = "${var.project_name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_compute_target_http_proxy" "meddataflow_http_proxy" {
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.meddataflow_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "meddataflow_http_forwarding_rule" {
  name       = "${var.project_name}-http-forwarding-rule"
  target     = google_compute_target_http_proxy.meddataflow_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.meddataflow_ip.address
}
