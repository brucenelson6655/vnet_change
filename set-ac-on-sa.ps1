# 1. Define configuration variables
$ResourceGroupName  = "your-storage-rg-name"
$StorageAccountName = "yourstorageaccountname"
$ConnectorName      = "your-databricks-access-connector-name"
$ConnectorRG        = "your-connector-rg-name"
$subscriptionId      = "your-subscription-id"

Select-AzSubscription $subscriptionId

# 2. Get the Storage Account resource object
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

# 3. Get the Azure Databricks Access Connector resource identity
$AccessConnector = Get-AzResource -ResourceGroupName $ConnectorRG -Name $ConnectorName -ResourceType "Microsoft.Databricks/accessConnectors"

# 4. Extract the Principal ID (Object ID) of the connector's managed identity
$PrincipalId = $AccessConnector.Identity.PrincipalId

# 5. Assign the 'Storage Blob Data Contributor' role to the Access Connector
New-AzRoleAssignment `
    -ObjectId $PrincipalId `
    -RoleDefinitionName "Storage Blob Data Contributor" `
    -Scope $StorageAccount.Id
