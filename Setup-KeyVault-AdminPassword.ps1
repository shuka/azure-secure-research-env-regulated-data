#requires -Version 7.0
#requires -Modules @{ ModuleName='Az.KeyVault'; ModuleVersion='4.0.0' }

<#
.SYNOPSIS
    Sets up Azure Key Vault and securely stores the admin password for the SRE deployment.

.DESCRIPTION
    This script helps you:
    1. Create an Azure Key Vault (if it doesn't exist)
    2. Store the admin password as a secret in Key Vault
    3. Configure access policies for secure retrieval during deployment
    
    The admin password is never stored in plain text in your scripts or version control.

.PARAMETER SubscriptionId
    The Azure subscription ID where the Key Vault should be created.

.PARAMETER ResourceGroupName
    The name of the resource group where the Key Vault will be created.

.PARAMETER KeyVaultName
    The name of the Key Vault. If not provided, a default name will be generated.

.PARAMETER SecretName
    The name of the secret in Key Vault. Default is 'AdminPassword'.

.PARAMETER AdminPassword
    The admin password to store. If not provided, you will be prompted to enter it securely.

.EXAMPLE
    .\Setup-KeyVault-AdminPassword.ps1 -SubscriptionId "7b58b5b8-9b57-4083-81d3-b0b9044d1ed7" -ResourceGroupName "Demo-RG-Hub-01" -KeyVaultName "demo-kv-sre"

.EXAMPLE
    # Interactive mode - you'll be prompted for the password
    .\Setup-KeyVault-AdminPassword.ps1 -SubscriptionId "7b58b5b8-9b57-4083-81d3-b0b9044d1ed7" -ResourceGroupName "Demo-RG-Hub-01"

.NOTES
    Author: SRE Deployment Team
    Date: 2026-06-11
    Security Best Practice: Always use secure methods to store and retrieve passwords.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateLength(36, 36)]
    [System.String]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [System.String]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [System.String]$KeyVaultName = '',

    [Parameter(Mandatory = $false)]
    [System.String]$SecretName = 'AdminPassword',

    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$AdminPassword
)

$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

function New-KeyVaultIfNotExists {
    param(
        [System.String]$Name,
        [System.String]$ResourceGroupName,
        [System.String]$Location = 'westus2'
    )

    $existingKV = Get-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if ($null -ne $existingKV) {
        Write-Host "✓ Key Vault '$Name' already exists in resource group '$ResourceGroupName'" -ForegroundColor Green
        return $existingKV
    }

    Write-Host "Creating Azure Key Vault: $Name"
    $keyVault = New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Verbose

    if ($null -ne $keyVault) {
        Write-Host "✓ Key Vault '$Name' created successfully" -ForegroundColor Green
    }
    else {
        throw "Failed to create Key Vault '$Name'"
    }

    return $keyVault
}

function Set-KeyVaultSecret {
    param(
        [System.String]$VaultName,
        [System.String]$SecretName,
        [System.Security.SecureString]$SecretValue
    )

    Write-Host "Setting secret '$SecretName' in Key Vault '$VaultName'..."

    try {
        $secret = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $SecretValue

        if ($null -ne $secret) {
            Write-Host "✓ Secret '$SecretName' stored successfully" -ForegroundColor Green
            Write-Host "  Secret ID: $($secret.Id)" -ForegroundColor Gray
        }
        else {
            throw "Failed to store secret '$SecretName'"
        }
    }
    catch {
        Write-Error "Error storing secret: $_"
        throw
    }
}

function Show-KeyVaultInfo {
    param(
        [System.String]$KeyVaultName,
        [System.String]$ResourceGroupName,
        [System.String]$SecretName
    )

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║             Key Vault Setup Complete                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Key Vault Details:" -ForegroundColor Yellow
    Write-Host "  Name:              $KeyVaultName"
    Write-Host "  Resource Group:    $ResourceGroupName"
    Write-Host "  Secret Name:       $SecretName"
    Write-Host "  Secret URI:        https://$KeyVaultName.vault.azure.net/secrets/$SecretName"
    Write-Host ""
    Write-Host "Update Deploy-SRE.ps1 with these values:" -ForegroundColor Yellow
    Write-Host '  $KeyVaultName = "' + $KeyVaultName + '"'
    Write-Host '  $SecretName = "' + $SecretName + '"'
    Write-Host ""
    Write-Host "The deployment script will automatically retrieve the password from Key Vault." -ForegroundColor Green
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────

try {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        Azure Key Vault - Admin Password Setup                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Set Azure context
    Write-Host "Setting Azure context to subscription: $SubscriptionId"
    $azContext = Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
    Write-Host "✓ Azure context set to subscription: $($azContext.Name)" -ForegroundColor Green
    Write-Host ""

    # Verify resource group exists
    Write-Host "Verifying resource group: $ResourceGroupName"
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        throw "Resource group '$ResourceGroupName' not found in subscription '$SubscriptionId'. Please create it first."
    }

    Write-Host "✓ Resource group found: $ResourceGroupName (Location: $($resourceGroup.Location))" -ForegroundColor Green
    Write-Host ""

    # Generate Key Vault name if not provided
    if ([System.String]::IsNullOrWhiteSpace($KeyVaultName)) {
        # Key Vault names must be globally unique and lowercase
        $randomSuffix = -join ((48..57) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
        $KeyVaultName = "kv-sre-$randomSuffix".ToLower()
        Write-Host "Generated Key Vault name: $KeyVaultName"
    }

    # Create or get Key Vault
    $keyVault = New-KeyVaultIfNotExists -Name $KeyVaultName -ResourceGroupName $ResourceGroupName -Location $resourceGroup.Location
    Write-Host ""

    # Get or prompt for admin password
    if ($null -eq $AdminPassword) {
        Write-Host "Enter the admin password for the SRE environment."
        Write-Host "Requirements: At least 12 characters, include uppercase, lowercase, numbers, and special characters"
        Write-Host ""

        while ($true) {
            $password1 = Read-Host -Prompt "Enter admin password" -AsSecureString
            $password2 = Read-Host -Prompt "Confirm admin password" -AsSecureString

            # Convert secure strings to plain text for comparison in a cross-platform way
            $plainPassword1 = (New-Object System.Management.Automation.PSCredential('user',$password1)).GetNetworkCredential().Password
            $plainPassword2 = (New-Object System.Management.Automation.PSCredential('user',$password2)).GetNetworkCredential().Password

            if ($plainPassword1 -eq $plainPassword2) {
                $AdminPassword = $password1
                Write-Host "✓ Password confirmed" -ForegroundColor Green
                break
            }
            else {
                Write-Host "✗ Passwords do not match. Please try again." -ForegroundColor Red
            }
        }
    }

    Write-Host ""

    # Store the secret in Key Vault
    Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName $SecretName -SecretValue $AdminPassword

    # Display summary information
    Show-KeyVaultInfo -KeyVaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -SecretName $SecretName

    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Update the KeyVaultName variable in Deploy-SRE.ps1 (line ~7)"
    Write-Host "2. Ensure the resource group name matches: $ResourceGroupName"
    Write-Host "3. Run Deploy-SRE.ps1 to deploy the SRE with secure credentials"
    Write-Host ""

}
catch {
    Write-Error "Setup failed: $_"
    exit 1
}
