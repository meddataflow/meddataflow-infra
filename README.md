# MedDataFlow - Google Cloud Deployment

This Terraform configuration deploys the MedDataFlow application to Google Cloud Platform (GCP) using modern cloud-native services.

## Architecture Overview

### GCP Services Used

- **Google Artifact Registry**: Container image storage (equivalent to AWS ECR)
- **Google Cloud Run**: Serverless container hosting (equivalent to AWS Fargate)
- **Google Cloud Load Balancer**: Global HTTP(S) load balancer with SSL termination
- **Google Cloud SQL**: Managed PostgreSQL database (equivalent to AWS RDS)
- **Google VPC**: Virtual Private Cloud with private subnets
- **Google VPC Connector**: Connects Cloud Run to VPC resources

### Architecture Diagram

```
Internet → Load Balancer (HTTPS/SSL) → Cloud Run Services
                                              ↓
                                      VPC Connector
                                              ↓
                                      Private VPC
                                              ↓
                                      Cloud SQL (PostgreSQL)
```

## Prerequisites

1. **Google Cloud Account** with billing enabled
2. **Google Cloud SDK** installed and configured
3. **Terraform** installed (version >= 1.0)
4. **Docker** for building and pushing container images
5. **Domain name** that you control for SSL certificate

## Setup Instructions

### Step 1: Google Cloud Project Setup

```bash
# Create a new project (optional)
gcloud projects create your-project-id --name="MedDataFlow"

# Set the project
gcloud config set project your-project-id

# Enable billing for the project (required)
# Do this via the GCP Console: https://console.cloud.google.com/billing
```

### Step 2: Authentication

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set application default credentials for Terraform
gcloud auth application-default login
```

### Step 3: Configure Terraform Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

Required variables:
- `project_id`: Your GCP project ID
- `domain_name`: Your domain name (e.g., "meddataflow.com")
- `database_password`: Secure password for PostgreSQL

### Step 4: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Step 5: Build and Push Container Images

After Terraform completes, use the output commands to push your containers:

```bash
# Configure Docker authentication
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build and push backend
cd backend
docker build -t us-central1-docker.pkg.dev/YOUR-PROJECT/meddataflow-repo/meddataflow-backend:latest .
docker push us-central1-docker.pkg.dev/YOUR-PROJECT/meddataflow-repo/meddataflow-backend:latest

# Build and push frontend
cd ../frontend
docker build -t us-central1-docker.pkg.dev/YOUR-PROJECT/meddataflow-repo/meddataflow-frontend:latest .
docker push us-central1-docker.pkg.dev/YOUR-PROJECT/meddataflow-repo/meddataflow-frontend:latest
```

### Step 6: Configure DNS

Point your domain to the load balancer IP address:

```bash
# Get the load balancer IP
terraform output load_balancer_ip
```

Create an A record in your DNS provider:
- **Name**: `your-domain.com` (or subdomain)
- **Type**: A
- **Value**: The IP address from terraform output
- **TTL**: 300

### Step 7: Wait for SSL Certificate

Google will automatically provision an SSL certificate for your domain. This can take 10-60 minutes.

## Environment Variables

The following environment variables are automatically configured:

### Backend
- `DATABASE_URL`: PostgreSQL connection string
- `ENVIRONMENT`: Set to "production"
- `FRONTEND_URL`: Frontend URL for CORS

### Frontend
- `NEXT_PUBLIC_API_URL`: Backend API URL

## Scaling Configuration

### Cloud Run Scaling
- **Backend**: Max 10 instances, auto-scales based on requests
- **Frontend**: Max 5 instances, auto-scales based on requests

### Database
- **Development**: `db-f1-micro` (1 vCPU, 0.6GB RAM)
- **Production**: Change to `db-n1-standard-1` (1 vCPU, 3.75GB RAM)

## Security Features

1. **Private Database**: Cloud SQL instance is not publicly accessible
2. **VPC Isolation**: Services communicate through private VPC
3. **SSL/TLS**: Automatic HTTPS with Google-managed SSL certificates
4. **Service Accounts**: Minimal required permissions
5. **Network Security**: Private subnets and VPC connectors

## Monitoring & Logging

All services automatically integrate with Google Cloud's monitoring:
- **Cloud Run Metrics**: Request latency, error rates, instance count
- **Cloud SQL Metrics**: Connection count, query performance
- **Load Balancer Metrics**: Request count, response codes
- **Logs**: Centralized in Google Cloud Logging

## Cost Optimization

### Development Environment
- Use `db-f1-micro` for database
- Cloud Run only charges for actual usage
- Load balancer has minimal fixed costs

### Production Considerations
- Upgrade database instance type
- Configure proper monitoring alerts
- Consider Cloud CDN for static assets

## Troubleshooting

### Common Issues

1. **SSL Certificate Not Working**
   - Ensure DNS is properly configured
   - Wait up to 60 minutes for certificate provisioning
   - Check domain ownership

2. **Cloud Run Services Not Starting**
   - Check container logs: `gcloud run services logs tail SERVICE_NAME --region=us-central1`
   - Verify environment variables
   - Check container registry permissions

3. **Database Connection Issues**
   - Verify VPC connector configuration
   - Check service account permissions
   - Confirm private IP connectivity

### Useful Commands

```bash
# Check Cloud Run service status
gcloud run services list --region=us-central1

# View service logs
gcloud run services logs tail meddataflow-backend --region=us-central1

# Check SSL certificate status
gcloud compute ssl-certificates list

# Monitor database connections
gcloud sql operations list --instance=meddataflow-postgres
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data including the database!

## Support

For issues with this deployment:
1. Check the troubleshooting section above
2. Review Google Cloud documentation
3. Check Terraform and service logs