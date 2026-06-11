# Script to remove all resource groups and resources created by the Bicep deployment
# Supports the multi-subscription SRE environment

[System.Collections.ArrayList]$SubscriptionIDs = @(
    '7b58b5b8-9b57-4083-81d3-b0b9044d1ed7',      # Hub Subscription
    '6c4975c1-149a-4a89-9593-77cdfa26417a',      # Researcher Subscription
    'bedecb48-9cb1-4240-9761-0109c2de77c9'       # Virtual Desktop Subscription
)

[System.String]$EnvironmentName = 'Demo'
[System.String]$WorkloadName = 'SRE'

# Resource group naming patterns (based on the Bicep deployment)
# The Bicep templates typically create resource groups with names containing the environment and workload names
$ResourceGroupPatterns = @(
    "rg-$EnvironmentName-*",
    "*$WorkloadName*",
    "*Researcher*",
    "*VirtualDesktop*",
    "*Hub*",
    "*AVD*",
    "*Bastion*"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SRE Resource Cleanup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$TotalResourceGroupsToDelete = 0
$AllResourceGroupsToDelete = @()

foreach ($SubscriptionID in $SubscriptionIDs) {
    Write-Host "Switching to subscription: $SubscriptionID" -ForegroundColor Yellow
    
    try {
        Get-AzSubscription -SubscriptionId $SubscriptionID | Set-AzContext -ErrorAction Stop | Out-Null
        
        Write-Host "Getting resource groups in subscription: $SubscriptionID" -ForegroundColor Green
        $ResourceGroups = Get-AzResourceGroup
        
        if ($ResourceGroups.Count -eq 0) {
            Write-Host "  No resource groups found in this subscription." -ForegroundColor Gray
            continue
        }
        
        Write-Host "  Found $($ResourceGroups.Count) resource group(s)" -ForegroundColor Green
        
        foreach ($RG in $ResourceGroups) {
            $RGName = $RG.ResourceGroupName
            
            # Check if the resource group matches the patterns
            $IsMatch = $false
            foreach ($Pattern in $ResourceGroupPatterns) {
                if ($RGName -like $Pattern) {
                    $IsMatch = $true
                    break
                }
            }
            
            if ($IsMatch) {
                $Resources = Get-AzResource -ResourceGroupName $RGName
                $ResourceCount = $Resources.Count
                
                Write-Host "  ✓ $RGName (Contains $ResourceCount resource(s))" -ForegroundColor Cyan
                $AllResourceGroupsToDelete += @{
                    'ResourceGroupName' = $RGName
                    'SubscriptionID'    = $SubscriptionID
                    'ResourceCount'     = $ResourceCount
                }
                $TotalResourceGroupsToDelete++
            }
        }
    }
    catch {
        Write-Host "Error accessing subscription $SubscriptionID : $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total resource groups to delete: $TotalResourceGroupsToDelete" -ForegroundColor Yellow

if ($TotalResourceGroupsToDelete -eq 0) {
    Write-Host "No resource groups matching the deployment patterns were found." -ForegroundColor Green
    Write-Host ""
    Write-Host "If you need to delete specific resource groups, you can:"
    Write-Host "1. Manually specify resource group names in the \`\$ManualResourceGroups array"
    Write-Host "2. List all resource groups with: Get-AzResourceGroup | Select-Object ResourceGroupName"
    Write-Host "3. Delete a resource group with: Remove-AzResourceGroup -Name '<RG-Name>' -Force -AsJob"
    exit 0
}

Write-Host ""
Write-Host "Resource groups to be deleted:" -ForegroundColor Yellow
foreach ($RG in $AllResourceGroupsToDelete) {
    Write-Host "  - $($RG.ResourceGroupName) (Subscription: $($RG.SubscriptionID), Resources: $($RG.ResourceCount))" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "WARNING: This will permanently delete all resources!" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$Confirmation = Read-Host "Do you want to proceed with deletion? (Type 'yes' to confirm)"

if ($Confirmation -ne 'yes') {
    Write-Host "Deletion cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Starting deletion process..." -ForegroundColor Yellow
Write-Host ""

$DeletedCount = 0
$FailedCount = 0

foreach ($RG in $AllResourceGroupsToDelete) {
    $RGName = $RG.ResourceGroupName
    $SubscriptionID = $RG.SubscriptionID
    
    try {
        # Switch to the correct subscription
        Get-AzSubscription -SubscriptionId $SubscriptionID | Set-AzContext -ErrorAction Stop | Out-Null
        
        Write-Host "Deleting resource group: $RGName" -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $RGName -Force -AsJob | Out-Null
        Write-Host "  ✓ Deletion job created for $RGName" -ForegroundColor Green
        $DeletedCount++
    }
    catch {
        Write-Host "  ✗ Error deleting $RGName : $_" -ForegroundColor Red
        $FailedCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deletion Process Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resource groups scheduled for deletion: $DeletedCount" -ForegroundColor Green
Write-Host "Failed deletions: $FailedCount" -ForegroundColor $(if ($FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ""
Write-Host "Note: Resource groups are being deleted asynchronously in the background." -ForegroundColor Yellow
Write-Host "You can monitor progress using: Get-Job | Receive-Job" -ForegroundColor Yellow
Write-Host ""
