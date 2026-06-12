#requires -Version 7.0
#requires -Modules Az.Accounts
#requires -Modules @{ ModuleName='Az.KeyVault'; ModuleVersion='4.0.0' }
#requires -Modules Az.Resources

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
# INPUT VALIDATION
# ──────────────────────────────────────────────────────────────────────────────

$parsedSubscriptionId = [System.Guid]::Empty
if (-not [System.Guid]::TryParse($SubscriptionId, [ref]$parsedSubscriptionId) -or $parsedSubscriptionId -eq [System.Guid]::Empty) {
    throw 'Invalid Subscription ID format. Expected a non-empty GUID.'
}
$SubscriptionId = $parsedSubscriptionId.ToString()

if ([System.String]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'Resource Group Name cannot be empty.'
}
$ResourceGroupName = $ResourceGroupName.Trim()

if (-not [System.String]::IsNullOrWhiteSpace($KeyVaultName)) {
    $KeyVaultName = $KeyVaultName.Trim().ToLowerInvariant()
    if ($KeyVaultName -notmatch '^[a-z][a-z0-9-]{1,22}[a-z0-9]$' -or $KeyVaultName -match '--') {
        throw 'Key Vault name must be 3-24 characters, start with a letter, end with a letter or number, and contain only letters, numbers, and single hyphens.'
    }
}

if ([System.String]::IsNullOrWhiteSpace($SecretName)) {
    throw 'Secret Name cannot be empty.'
}
$SecretName = $SecretName.Trim()
if ($SecretName -notmatch '^[0-9A-Za-z-]{1,127}$') {
    throw 'Secret name must be 1-127 characters and contain only letters, numbers, and hyphens.'
}

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

    try {
        $keyVault = New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction Stop

        if ($null -ne $keyVault) {
            Write-Host "✓ Key Vault '$Name' created successfully" -ForegroundColor Green
        }
        else {
            throw "Failed to create Key Vault '$Name'"
        }
    }
    catch {
        Write-Error "Error creating Key Vault: Please verify your permissions and that the name is globally unique."
        throw
    }

    return $keyVault
}

function Test-PasswordStrength {
    param(
        [System.Security.SecureString]$Password
    )

    $valid = $true
    $feedback = @()
    $passwordPtr = [System.IntPtr]::Zero
    $hasUpper = $false
    $hasLower = $false
    $hasDigit = $false
    $hasSpecial = $false
    $hasControlOrWhitespace = $false

    if ($null -eq $Password -or $Password.Length -eq 0) {
        return @{
            IsValid  = $false
            Feedback = @('• Password cannot be empty')
        }
    }

    if ($Password.Length -lt 12) {
        $valid = $false
        $feedback += "• At least 12 characters"
    }
    if ($Password.Length -gt 123) {
        $valid = $false
        $feedback += "• No more than 123 characters"
    }

    try {
        $passwordPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)

        for ($index = 0; $index -lt $Password.Length; $index++) {
            $char = [System.Char][System.Runtime.InteropServices.Marshal]::ReadInt16($passwordPtr, ($index * 2))

            if ([System.Char]::IsUpper($char)) {
                $hasUpper = $true
            }
            elseif ([System.Char]::IsLower($char)) {
                $hasLower = $true
            }
            elseif ([System.Char]::IsDigit($char)) {
                $hasDigit = $true
            }

            if ([System.Char]::IsPunctuation($char) -or [System.Char]::IsSymbol($char)) {
                $hasSpecial = $true
            }

            if ([System.Char]::IsControl($char) -or [System.Char]::IsWhiteSpace($char)) {
                $hasControlOrWhitespace = $true
            }
        }
    }
    finally {
        if ($passwordPtr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
        }
    }

    if (-not $hasUpper) {
        $valid = $false
        $feedback += "• At least one uppercase letter"
    }
    if (-not $hasLower) {
        $valid = $false
        $feedback += "• At least one lowercase letter"
    }
    if (-not $hasDigit) {
        $valid = $false
        $feedback += "• At least one number"
    }
    if (-not $hasSpecial) {
        $valid = $false
        $feedback += "• At least one special character"
    }
    if ($hasControlOrWhitespace) {
        $valid = $false
        $feedback += "• No whitespace or control characters"
    }

    return @{
        IsValid  = $valid
        Feedback = $feedback
    }
}

function Compare-SecureStrings {
    param(
        [System.Security.SecureString]$String1,
        [System.Security.SecureString]$String2
    )

    if ($null -eq $String1 -or $null -eq $String2) {
        return $false
    }

    $ptr1 = [System.IntPtr]::Zero
    $ptr2 = [System.IntPtr]::Zero

    try {
        $ptr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($String1)
        $ptr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($String2)
        $maxLength = [System.Math]::Max($String1.Length, $String2.Length)
        $diff = [int]($String1.Length -bxor $String2.Length)

        for ($index = 0; $index -lt $maxLength; $index++) {
            $char1 = if ($index -lt $String1.Length) { [int][System.Runtime.InteropServices.Marshal]::ReadInt16($ptr1, ($index * 2)) } else { 0 }
            $char2 = if ($index -lt $String2.Length) { [int][System.Runtime.InteropServices.Marshal]::ReadInt16($ptr2, ($index * 2)) } else { 0 }
            $diff = $diff -bor ($char1 -bxor $char2)
        }

        return ($diff -eq 0)
    }
    finally {
        if ($ptr1 -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr1)
        }
        if ($ptr2 -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2)
        }
    }
}

function Set-KeyVaultSecret {
    param(
        [System.String]$VaultName,
        [System.String]$SecretName,
        [System.Security.SecureString]$SecretValue
    )

    Write-Host "Setting secret '$SecretName' in Key Vault '$VaultName'..."

    $retrieved = $null
    try {
        $secret = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $SecretValue

        if ($null -ne $secret) {
            Write-Host "✓ Secret '$SecretName' stored successfully" -ForegroundColor Green
            Write-Host "  Secret Version: $($secret.Version)" -ForegroundColor Gray

            # Verify the just-written version is retrievable without requesting plaintext output.
            $retrieved = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -ErrorAction Stop
            if ($null -ne $retrieved -and $retrieved.Version -eq $secret.Version) {
                Write-Host "✓ Secret retrieval verified successfully" -ForegroundColor Green
            }
            else {
                throw "Secret stored but could not be verified - retrieval failed"
            }
        }
        else {
            throw "Failed to store secret '$SecretName'"
        }
    }
    catch {
        Write-Error "Error storing secret in Key Vault. Please verify your permissions and try again."
        throw
    }
    finally {
        if ($null -ne $retrieved -and $null -ne $retrieved.SecretValue) {
            $retrieved.SecretValue.Dispose()
        }
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
    Write-Host ""
    Write-Host "Update Deploy-SRE.ps1 with these values:" -ForegroundColor Yellow
    Write-Host '  $KeyVaultName = "' + $KeyVaultName + '"'
    Write-Host '  $SecretName = "' + $SecretName + '"'
    Write-Host ""
    Write-Host "The deployment script will automatically retrieve the password from Key Vault." -ForegroundColor Green
    Write-Host "⚠ SECURITY: Only users with Key Vault 'Get Secret' permissions can retrieve this password." -ForegroundColor Yellow
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

            # Validate password strength
            $validation = Test-PasswordStrength -Password $password1
            if (-not $validation.IsValid) {
                Write-Host "✗ Password does not meet requirements:" -ForegroundColor Red
                $validation.Feedback | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                Write-Host ""
                $password1.Dispose()
                $password1 = $null
                continue
            }

            $password2 = Read-Host -Prompt "Confirm admin password" -AsSecureString

            # Use secure comparison without exposing plain text
            if (Compare-SecureStrings -String1 $password1 -String2 $password2) {
                $AdminPassword = $password1
                Write-Host "✓ Password confirmed" -ForegroundColor Green

                # Explicitly dispose of temporary password
                $password2.Dispose()
                $password2 = $null
                break
            }
            else {
                Write-Host "✗ Passwords do not match. Please try again." -ForegroundColor Red

                # Explicitly dispose of temporary passwords
                $password1.Dispose()
                $password2.Dispose()
                $password1 = $null
                $password2 = $null
            }
        }
    }
    else {
        # Validate provided password
        $validation = Test-PasswordStrength -Password $AdminPassword
        if (-not $validation.IsValid) {
            Write-Host "✗ Provided password does not meet requirements:" -ForegroundColor Red
            $validation.Feedback | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            throw "Password validation failed"
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
finally {
    # Final cleanup of any sensitive variables
    if ($null -ne $AdminPassword) {
        $AdminPassword.Dispose()
    }
    if ($null -ne $password1 -and -not [System.Object]::ReferenceEquals($password1, $AdminPassword)) {
        $password1.Dispose()
    }
    if ($null -ne $password2) {
        $password2.Dispose()
    }
}
