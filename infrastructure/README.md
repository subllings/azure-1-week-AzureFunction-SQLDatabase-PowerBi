# Infrastructure Documentation

## Overview
This directory contains the complete Terraform infrastructure for the iRail Train Data pr### Cost Optimization

### Development/Testing
- Use Flex Consumption plan (FC1) for Functions - Better performance than classic Y1
- Basic SQL Database SKU
- LRS storage replication
- Shorter backup retentionincluding Azure Functions, SQL Server, Data Factory, and all supporting resources.

## Architecture Components

### Core Infrastructure
- **Resource Group**: Container for all related resources
- **App Service Plan**: Hosting plan for Azure Functions (FC1 for staging, EP1 for production)
- **Azure Functions**: Serverless compute for iRail API endpoints
- **SQL Server + Database**: Managed database for train data storage
- **Application Insights**: Monitoring and telemetry
- **Storage Account**: Function runtime and file storage
- **Key Vault**: Secure secret management
- **Container Registry**: Docker image repository
- **Managed Identity**: Secure authentication without passwords

### Data Processing
- **Azure Data Factory**: Automated data collection and ETL pipelines
- **Data Factory Pipelines**: Scheduled data collection from iRail API
- **Data Factory Triggers**: Time-based execution (every 5 minutes)

## File Structure

```
infrastructure/
├── main.tf                    # Core resource definitions and providers
├── variables.tf               # Input variables and validation
├── outputs.tf                 # Output values for CI/CD integration
├── app-service-plan.tf        # App Service Plan for Azure Functions
├── azure-functions.tf         # Azure Functions App configuration
├── sql-server.tf              # SQL Server and Database
├── data-factory.tf            # Data Factory setup
├── data-factory-pipeline.tf   # Data collection pipelines
├── data-factory-triggers.tf   # Automated scheduling
├── data-factory-outputs.tf    # Data Factory outputs
├── staging.tfvars             # Staging environment variables
├── production.tfvars          # Production environment variables
└── README.md                  # This documentation
```

## Environment Configurations

### Environment to App Service Plan Mapping

| Environment | SKU | Plan Type | Monthly Cost |
|-------------|-----|-----------|--------------|
| staging | FC1 | Flex Consumption | ~&euro;20-30 |
| dev | FC1 | Flex Consumption | ~&euro;10-20 |
| production | EP1 | Elastic Premium | ~&euro;150-200 |

### Staging Environment
**Purpose**: Testing and validation before production deployment

**Resources:**
- App Service Plan: FC1 (Flex Consumption) - Pay per execution with better performance than Y1
- SQL Database: Basic SKU (5 DTU) - Minimal performance for testing
- Backup Retention: 7 days
- Storage: LRS (Locally Redundant Storage)

**Cost**: ~&euro;20-40/month

### Production Environment
**Purpose**: Live production workload with high availability

**Resources:**
- App Service Plan: EP1 (Elastic Premium) - Always-on with better performance
- SQL Database: S2 Standard (50 DTU) - Production workload capacity
- Backup Retention: 35 days with long-term retention
- Storage: GRS (Geo-Redundant Storage)

**Cost**: ~&euro;150-200/month

## Deployment Commands

### Deploy ONLY Staging (Recommended to start)

**Option 1: Automated script (Simpler)**
```bash
# Windows
./deploy-staging.bat

# Linux/macOS/Git Bash
./deploy-staging.sh
```

**Option 2: Manual commands**
```bash
# 1. Initialize Terraform (first time only)
cd infrastructure
terraform init

# 2. Set SQL password
export TF_VAR_sql_admin_password="YourSecurePassword123!"

# 3. (Optional) Allow your IP for direct SQL access
export TF_VAR_developer_ip="YOUR.PUBLIC.IP.ADDRESS"

# 4. Plan staging deployment
terraform plan -var-file="staging.tfvars"

# 5. Deploy staging
terraform apply -var-file="staging.tfvars"
```

### Complete Deployment (Staging + Production)

### Initialize Terraform
```bash
cd infrastructure
terraform init
```

### Plan Deployment (Staging)
```bash
terraform plan -var-file="staging.tfvars" -var="sql_admin_password=YourSecurePassword123!"
```

### Apply Deployment (Staging)
```bash
terraform apply -var-file="staging.tfvars" -var="sql_admin_password=YourSecurePassword123!"
```

### Plan Deployment (Production)
```bash
terraform plan -var-file="production.tfvars" -var="sql_admin_password=YourSecurePassword123!"
```

### Apply Deployment (Production)
```bash
terraform apply -var-file="production.tfvars" -var="sql_admin_password=YourSecurePassword123!"
```

## Security Features

### Authentication
- **Managed Identity**: Azure Functions authenticate to SQL and Key Vault without passwords
- **Azure AD Integration**: SQL Server supports Azure AD authentication
- **Key Vault**: All secrets stored securely with access policies

### Network Security
- **Firewall Rules**: SQL Server restricted to Azure services and specific IPs
- **TLS 1.2**: Minimum encryption for all connections
- **HTTPS Only**: All Function App endpoints use HTTPS

### Access Control
- **RBAC**: Role-based access control for all resources
- **Least Privilege**: Each service has minimal required permissions
- **Audit Logging**: All resource changes logged via Activity Log

## Monitoring and Alerting

### Application Insights
- **Performance Monitoring**: Function execution times and success rates
- **Error Tracking**: Automatic exception tracking and alerting
- **Custom Metrics**: Train data collection statistics
- **Dashboard**: Real-time monitoring of all components

### Data Factory Monitoring
- **Pipeline Execution**: Track success/failure of data collection runs
- **Schedule Monitoring**: Ensure triggers execute as expected
- **Error Alerts**: Notification when data collection fails

## Backup and Disaster Recovery

### SQL Database Backups
- **Point-in-time Restore**: Restore to any point within retention period
- **Automated Backups**: Daily full, hourly differential, every 5-10 min transaction log
- **Geo-Restore**: Restore from geo-redundant backups in case of regional failure

### Infrastructure Recovery
- **Infrastructure as Code**: Complete infrastructure can be recreated from Terraform
- **State Backup**: Terraform state stored in Azure Storage with versioning
- **Configuration Management**: All settings defined in code for consistency

## Cost Optimization

### Development/Testing
- Use Flex Consumption plan (FC1) for Functions - Better performance and cost-effective
- Basic SQL Database SKU
- LRS storage replication
- Shorter backup retention

### Production
- Elastic Premium (EP1) for consistent performance
- Standard SQL Database for production workload
- GRS storage for disaster recovery
- Extended backup retention for compliance

## Troubleshooting

### Common Issues

1. **Terraform State Lock**
   - Check for existing locks: `terraform force-unlock [LOCK_ID]`
   - Ensure only one deployment runs at a time

2. **SQL Authentication Failures**
   - Verify Managed Identity has SQL permissions
   - Check firewall rules allow Azure services
   - Confirm connection string format

3. **Function App Deployment Issues**
   - Check App Service Plan capacity
   - Verify container registry credentials
   - Review Application Insights for errors

### Validation Commands
```bash
# Test SQL connectivity
az sql db show-connection-string --client ado.net --name [DB_NAME] --server [SERVER_NAME]

# Check Function App status
az functionapp show --name [FUNCTION_NAME] --resource-group [RG_NAME]

# Verify Data Factory triggers
az datafactory trigger show --factory-name [DF_NAME] --name [TRIGGER_NAME] --resource-group [RG_NAME]
```

## Next Steps

After infrastructure deployment:
1. Configure Azure DevOps pipeline for automated deployments
2. Set up monitoring alerts and dashboards
3. Configure backup and disaster recovery procedures
4. Implement security scanning and compliance checks
5. Set up cost monitoring and optimization alerts
