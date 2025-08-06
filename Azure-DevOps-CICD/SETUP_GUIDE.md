# Azure DevOps CI/CD Pipeline Setup Guide

## Overview
This guide explains how to configure the complete CI/CD pipeline for the iRail Azure Functions project using Azure DevOps.

## Prerequisites
- Azure DevOps organization
- Azure subscription with appropriate permissions
- Azure Container Registry (ACR)
- Azure Function App (existing or will be created by Terraform)
- Azure Data Factory (existing or will be created by Terraform)

## 1. Service Connections Configuration

### 1.1 Azure Service Connection
Create a service connection to authenticate with Azure:

1. Go to Project Settings > Service connections
2. Create new service connection
3. Choose "Azure Resource Manager"
4. Select "Service principal (automatic)"
5. Name: `azure-service-connection`
6. Select your subscription and resource group
7. Grant access permission to all pipelines

### 1.2 Container Registry Service Connection
Create a service connection for Azure Container Registry:

1. Go to Project Settings > Service connections
2. Create new service connection
3. Choose "Docker Registry"
4. Registry type: "Azure Container Registry"
5. Name: `azure-container-registry-connection`
6. Select your ACR: `traindataacr1754421294.azurecr.io`
7. Grant access permission to all pipelines

## 2. Variable Groups Configuration

### 2.1 azure-secrets Variable Group
Contains sensitive Azure credentials and connection strings:

```
AZURE_CLIENT_ID: [Service Principal Client ID]
AZURE_CLIENT_SECRET: [Service Principal Client Secret] (mark as secret)
AZURE_TENANT_ID: [Azure Tenant ID]
AZURE_SUBSCRIPTION_ID: b63db937-8e75-4757-aa10-4571a475c185
SQL_CONNECTION_STRING: [Database connection string] (mark as secret)
APPLICATIONINSIGHTS_CONNECTION_STRING: [App Insights connection] (mark as secret)
AZURE_WEB_JOBS_STORAGE: [Storage account connection] (mark as secret)
ACR_USERNAME: [Container Registry username]
ACR_PASSWORD: [Container Registry password] (mark as secret)
```

### 2.2 function-config Variable Group
Contains application configuration:

```
AZURE_FUNCTION_APP_NAME: irail-functions-simple
AZURE_RESOURCE_GROUP: rg-irail-dev-i6lr9a
AZURE_DATA_FACTORY_NAME: df-irail-data-pobm4m
AZURE_APP_INSIGHTS_NAME: [Your App Insights name]
AZURE_LOCATION: West Europe
ENVIRONMENT: production
```

### 2.3 terraform-config Variable Group
Contains Terraform configuration:

```
TF_VAR_subscription_id: b63db937-8e75-4757-aa10-4571a475c185
TF_VAR_resource_group_name: rg-irail-dev-i6lr9a
TF_VAR_location: West Europe
TF_VAR_environment: dev
ARM_CLIENT_ID: [Same as AZURE_CLIENT_ID]
ARM_CLIENT_SECRET: [Same as AZURE_CLIENT_SECRET] (mark as secret)
ARM_TENANT_ID: [Same as AZURE_TENANT_ID]
ARM_SUBSCRIPTION_ID: [Same as AZURE_SUBSCRIPTION_ID]
```

## 3. Environment Configuration

### 3.1 Create Environments
1. Go to Pipelines > Environments
2. Create the following environments:
   - `infrastructure` (for Terraform deployments)
   - `production` (for Function App deployments)

### 3.2 Environment Approvals (Optional)
Configure manual approval gates for production deployments:
1. Go to environment settings
2. Add approval checks
3. Configure required reviewers

## 4. Pipeline Permissions

Ensure the pipeline has the following permissions:
- Contribute to the repository
- Read/Write access to Variable Groups
- Use Service Connections
- Deploy to target environments

## 5. Pipeline Execution Flow

The complete CI/CD pipeline includes these stages:

1. **Pre-Validation**: Code quality, security scanning, Dockerfile validation
2. **Infrastructure**: Terraform deployment of Azure resources
3. **Build**: Docker image build and push to ACR
4. **Deploy**: Container deployment to Azure Functions
5. **Tests**: Comprehensive API testing using existing test scripts
6. **Data Factory Validation**: Validate and start Data Factory pipelines
7. **Monitoring**: Setup Application Insights alerts and final validation

## 6. Manual Pipeline Trigger

To manually trigger the pipeline:
1. Go to Pipelines
2. Select the pipeline
3. Click "Run pipeline"
4. Choose branch and variables if needed

## 7. Monitoring and Troubleshooting

### Pipeline Logs
- Check each stage's logs for detailed output
- Failed stages will show error details
- Use the timeline view for stage dependencies

### Application Monitoring
- Application Insights dashboards
- Function App logs in Azure Portal
- Data Factory monitoring

### Common Issues
1. **Permission errors**: Check service connection permissions
2. **Variable not found**: Verify Variable Groups configuration
3. **Terraform errors**: Check terraform state and resource conflicts
4. **Container deployment fails**: Verify ACR permissions and image availability

## 8. Best Practices

### Security
- Mark all secrets as secret variables
- Use managed identities where possible
- Regularly rotate service principal credentials
- Review pipeline permissions periodically

### Performance
- Use Docker layer caching
- Minimize artifact sizes
- Parallel job execution where possible
- Cache dependencies between runs

### Reliability
- Implement proper error handling
- Use appropriate timeouts
- Configure retry policies
- Monitor pipeline success rates

## 9. Continuous Improvement

### Metrics to Track
- Pipeline success rate
- Deployment frequency
- Lead time for changes
- Mean time to recovery

### Regular Maintenance
- Update dependencies regularly
- Review and update variable values
- Optimize pipeline performance
- Update documentation

## Support

For issues with this pipeline configuration:
1. Check the pipeline logs first
2. Verify all variable groups are configured correctly
3. Ensure service connections are working
4. Contact the DevOps team for advanced troubleshooting
