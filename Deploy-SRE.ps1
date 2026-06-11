[System.String]$ARMTemplateFilePath = '.\bicep\main.bicep'
[System.String]$AzSubscriptionID = '7b58b5b8-9b57-4083-81d3-b0b9044d1ed7'
[System.String]$Location = 'westus2'
[System.String]$ValidationLevel = 'Provider'

# ──────────────────────────────────────────────────────────────────────────────
# SECURITY NOTE: Admin password is now retrieved from Azure Key Vault
# DO NOT store passwords in plain text in scripts or version control
# ──────────────────────────────────────────────────────────────────────────────

[System.String]$AdminUsername = 'CAESAdmin'
[System.String]$KeyVaultName = 'demo-kv-sre'  # Update with your Key Vault name
[System.String]$SecretName = 'AdminPassword'

# Set Azure context to hub subscription
Get-AzSubscription -SubscriptionId $AzSubscriptionID | Set-AzContext

# Retrieve the admin password from Azure Key Vault
Write-Host "Retrieving admin password from Azure Key Vault: $KeyVaultName"
try {
    $AdminPasswordSecure = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText | ConvertTo-SecureString -AsPlainText -Force)
}
catch {
    Write-Error "Failed to retrieve secret from Key Vault. Error: $_"
    Write-Host ""
    Write-Host "SETUP INSTRUCTIONS:"
    Write-Host "1. Create a Key Vault secret by running:"
    Write-Host "   `$password = Read-Host 'Enter admin password' -AsSecureString"
    Write-Host "   `$password | ConvertFrom-SecureString -AsPlainText | Set-AzKeyVaultSecret -VaultName '$KeyVaultName' -Name '$SecretName'"
    Write-Host "2. Ensure the Key Vault is created in the hub resource group"
    Write-Host "3. Update `$KeyVaultName above with your actual Key Vault name"
    exit 1
}

[System.Collections.Hashtable]$ARMTemplateParameterObject = @{
    'location'                     = $Location;
    'environmentName'              = 'Demo';
    'workloadName'                 = 'SRE';
    'adminUsername'                = $AdminUsername;
    'adminPassword'                = $AdminPasswordSecure;
    'keyVaultName'                 = $KeyVaultName;
    'keyVaultSecretName'           = $SecretName;
    'keyVaultResourceGroupName'    = 'Demo-RG-Hub-01';
    'BastionOrAVD'                 = 'Bastion';
    'researcherSubscriptionID'     = '6c4975c1-149a-4a89-9593-77cdfa26417a';
    'hubSubscriptionID'            = $AzSubscriptionID;
    'virtualDesktopSubscriptionID' = 'bedecb48-9cb1-4240-9761-0109c2de77c9';
    'researcherVMSize'             = 'Standard_D4ds_v5';
    'researcherVMCount'            = 1;
    'dataApproverEmail'            = 'ssmith@ucdavis.edu';
}

$GetARMTemplateFile = Get-Item -Path $ARMTemplateFilePath
$GetARMTemplateFileBaseName = $GetARMTemplateFile.BaseName
$GetARMTemplateFilePath = $GetARMTemplateFile.ResolvedTarget
[System.String]$DateTime = Get-Date -Format FileDateTime
[System.String]$DeploymentName = [System.String]::Concat($GetARMTemplateFileBaseName, '_', $DateTime)

Write-Host "Starting Bicep deployment: $DeploymentName"
Write-Host "Location: $Location"
Write-Host "Environment: $($ARMTemplateParameterObject['environmentName'])"

New-AzDeployment -Name $DeploymentName -Location $Location -TemplateFile $GetARMTemplateFilePath -TemplateParameterObject $ARMTemplateParameterObject -ValidationLevel $ValidationLevel -Verbose