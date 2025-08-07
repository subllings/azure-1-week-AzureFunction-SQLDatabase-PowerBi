# Infrastructure Environment Configuration

This directory contains environment-specific configuration files for Terraform infrastructure deployment.

## Files Overview

### Environment Variables
- `.env.staging` - Staging environment variables for Terraform
- `.env.production` - Production environment variables for Terraform
- `.env.template` - Template for creating new environment configurations

### Terraform Configuration
- `staging.tfvars` - Staging-specific Terraform variables
- `production.tfvars` - Production-specific Terraform variables
- `dev.tfvars` - Development-specific Terraform variables

## Usage

### Staging Deployment
```bash
# From project root
./scripts/deploy-staging.sh
```

The staging script will automatically:
1. Load variables from `infrastructure/.env.staging`
2. Run `terraform init`
3. Run `terraform plan -var-file="staging.tfvars"`
4. Prompt for confirmation
5. Run `terraform apply`

### Production Deployment
```bash
# From project root
./scripts/deploy-production.sh
```

The production script includes additional security checks and confirmation steps.

### Manual Deployment
If you prefer to run Terraform commands manually:

```bash
cd infrastructure

# Load environment variables
source .env.staging  # or .env.production

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="staging.tfvars"  # or production.tfvars

# Apply deployment
terraform apply
```

## Security Notes

### Staging Environment
- Passwords can be stored in `.env.staging` for development convenience
- Use cost-optimized resources (Basic SQL, FC1 App Service Plan)

### Production Environment
- **NEVER** store production passwords in files
- Use secure sources for `TF_VAR_sql_admin_password`:
  - Azure DevOps secret variables
  - GitHub Actions secrets
  - Azure Key Vault references
  - Secure environment variables
- Uses performance-optimized resources (S2 SQL, EP1 App Service Plan)

## Environment Variables Reference

### Required Variables
- `TF_VAR_sql_admin_username` - SQL Server admin username
- `TF_VAR_sql_admin_password` - SQL Server admin password (secure source for production)

### Optional Variables
- `TF_VAR_developer_ip` - Your IP address for direct SQL access (development only)
- `TF_VAR_environment` - Environment name (staging/production)
- `TF_VAR_location` - Azure region

## File Structure
```
infrastructure/
├── .env.staging          # Staging environment variables
├── .env.production       # Production environment variables
├── .env.template         # Template for new environments
├── staging.tfvars        # Staging Terraform variables
├── production.tfvars     # Production Terraform variables
├── main.tf              # Main Terraform configuration
├── azure-functions.tf   # Function App resources
├── sql-server.tf        # SQL Server resources
└── variables.tf         # Variable definitions
```
