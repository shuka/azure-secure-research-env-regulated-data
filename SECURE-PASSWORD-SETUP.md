# Secure Password Management for SRE Deployment

## Overview

The Deploy-SRE.ps1 deployment script has been updated to use **Azure Key Vault** for secure password management instead of storing credentials in plain text. This follows security best practices and prevents accidental exposure of credentials in version control.

## What Changed

### Before (Insecure ❌)
```powershell
[System.String]$AdminPassword = 'CAESPassword123!'
[System.Security.SecureString]$AdminPasswordSecure = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
```

### After (Secure ✓)
```powershell
[System.String]$KeyVaultName = 'demo-kv-sre'
[System.String]$SecretName = 'AdminPassword'

$secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
$AdminPasswordSecure = $secret.SecretValue
```

## Security Benefits

✓ **No plain text credentials** in source code or scripts
✓ **Centralized credential management** via Azure Key Vault
✓ **Audit trail** - all secret access is logged
✓ **RBAC control** - fine-grained permissions over who can access the password
✓ **Secret rotation** - easy to update passwords without code changes
✓ **Compliance ready** - meets regulatory requirements for credential storage

## Setup Instructions

### Step 1: Create Azure Key Vault and Store Password

Run the setup script to create the Key Vault and securely store the admin password:

```powershell
# Navigate to the repository root
cd /path/to/azure-secure-research-env-regulated-data

# Run the setup script
.\Setup-KeyVault-AdminPassword.ps1 `
    -SubscriptionId "7b58b5b8-9b57-4083-81d3-b0b9044d1ed7" `
    -ResourceGroupName "Demo-RG-Hub-01" `
    -KeyVaultName "demo-kv-sre"
```

**Parameters:**
- `SubscriptionId` (required): Your Azure subscription ID (hub subscription)
- `ResourceGroupName` (required): The resource group where the Key Vault will be created
- `KeyVaultName` (optional): Custom name for the Key Vault. If not provided, one will be auto-generated
- `SecretName` (optional): The secret name. Default is "AdminPassword"
- `AdminPassword` (optional): The password as a SecureString. If not provided, you'll be prompted interactively

**Example with manual password entry:**
```powershell
.\Setup-KeyVault-AdminPassword.ps1 `
    -SubscriptionId "7b58b5b8-9b57-4083-81d3-b0b9044d1ed7" `
    -ResourceGroupName "Demo-RG-Hub-01"
```

You will be prompted to:
1. Enter the admin password securely (without echoing)
2. Confirm the password by entering it again

**Output:**
The script will display the Key Vault details needed for the deployment script:
```
Key Vault Details:
  Name:              demo-kv-sre
  Resource Group:    Demo-RG-Hub-01
  Secret Name:       AdminPassword
```

### Step 2: Update Deploy-SRE.ps1 (if needed)

Update the Key Vault name in `Deploy-SRE.ps1` at the top of the script:

```powershell
[System.String]$KeyVaultName = 'demo-kv-sre'  # Update with your Key Vault name
```

### Step 3: Run the Deployment

Execute the deployment script as usual:

```powershell
.\Deploy-SRE.ps1
```

The script will automatically:
1. Retrieve the admin password from Azure Key Vault
2. Use the returned SecureString value directly
3. Pass it securely to the Bicep deployment

## How It Works

```
┌──────────────────────┐
│  Deploy-SRE.ps1      │
│  - Connects to Azure │
│  - Retrieves secret  │
│    from Key Vault    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│        Azure Key Vault (Secure)                  │
│  Secret: AdminPassword                           │
│  Access: RBAC controlled & Audited               │
└──────────┬──────────────────────────────────────┘
           │ (SecureString, never in plain text)
           ▼
┌──────────────────────────────────────────────────┐
│  Bicep Deployment (main.bicep)                   │
│  - Receives SecureString parameter               │
│  - Passes to VM modules                          │
│  - Never logs/displays password                  │
└──────────────────────────────────────────────────┘
```

## Troubleshooting

### Error: "Failed to retrieve secret from Key Vault"

**Cause:** The script cannot find the Key Vault or secret.

**Solution:**
1. Verify the Key Vault exists: `Get-AzKeyVault -VaultName "demo-kv-sre"`
2. Verify the secret exists: `Get-AzKeyVaultSecret -VaultName "demo-kv-sre" -Name "AdminPassword"`
3. Ensure you're in the correct subscription: `Get-AzContext`
4. Check your RBAC permissions to access Key Vault

### Error: "Access denied to Key Vault"

**Cause:** Your Azure account doesn't have permissions to read from the Key Vault.

**Solution:**
1. Ensure RBAC policy allows your account to read secrets
2. You may need the "Key Vault Secrets User" or "Key Vault Administrator" role
3. Ask your Azure administrator to grant the necessary permissions

### How to verify the secret exists

```powershell
# List all secrets in the Key Vault
Get-AzKeyVaultSecret -VaultName "demo-kv-sre" | Format-Table

# Retrieve metadata and a SecureString value without printing the password
$secret = Get-AzKeyVaultSecret -VaultName "demo-kv-sre" -Name "AdminPassword"
if ($null -ne $secret -and $null -ne $secret.SecretValue) {
    Write-Host "Secret exists and returned a secure value."
}
```

## Advanced: Rotating the Password

To update the admin password without modifying the deployment script:

```powershell
# Get the new password
$newPassword = Read-Host -Prompt "Enter new admin password" -AsSecureString

# Update the secret in Key Vault
Set-AzKeyVaultSecret -VaultName "demo-kv-sre" -Name "AdminPassword" -SecretValue $newPassword

# The next deployment will automatically use the new password
```

## Advanced: RBAC Configuration

For additional security, configure RBAC to limit who can access the password:

```powershell
# Grant access to specific users/groups
New-AzRoleAssignment `
    -ObjectId "user-object-id" `
    -RoleDefinitionName "Key Vault Secrets User" `
    -Scope "/subscriptions/7b58b5b8-9b57-4083-81d3-b0b9044d1ed7/resourceGroups/Demo-RG-Hub-01/providers/Microsoft.KeyVault/vaults/demo-kv-sre"
```

## Advanced: Managed Identity for Automated Deployments

For production CI/CD pipelines, configure a Managed Identity to retrieve the secret:

1. Create a Managed Identity
2. Grant it "Key Vault Secrets User" role on the Key Vault
3. Use the Managed Identity in your deployment pipeline

## Migration from Plain Text Passwords

If you have other scripts or applications using the old plain text password approach:

1. **Update Deploy-SRE.ps1** ✓ (already done)
2. **Update main.bicep** ✓ (already updated with Key Vault parameters)
3. **Update any other scripts** that reference `$AdminPassword` directly
4. **Delete or secure** the old plain text password references

## References

- [Azure Key Vault Overview](https://learn.microsoft.com/en-us/azure/key-vault/general/overview)
- [Bicep Key Vault Integration](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter?tabs=azure-cli)
- [PowerShell Get-AzKeyVaultSecret](https://learn.microsoft.com/en-us/powershell/module/az.keyvault/get-azkeyvaultsecret)
- [Azure RBAC for Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)

## Questions?

For issues or questions about the secure password setup, refer to the Bicep and PowerShell comments in:
- `Deploy-SRE.ps1` - Deployment script with Key Vault retrieval
- `bicep/main.bicep` - Bicep template with Key Vault parameters
- `Setup-KeyVault-AdminPassword.ps1` - Interactive setup script

---
**Last Updated:** 2026-06-11
**Security Classification:** Internal Use Only
