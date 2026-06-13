<#
.SYNOPSIS
    Removes resource groups created by the Secure Research Environment deployment.

.DESCRIPTION
    The Bicep deployment creates a known set of environment-prefixed resource
    groups across the hub, researcher, and virtual desktop subscriptions. This
    script discovers only those expected resource group names, shows a summary,
    and deletes them after explicit confirmation. Resource groups are deleted in
    dependency waves so cross-resource-group references, such as private
    endpoints, DNS zone links, Bastion subnet attachments, and VNet peerings, are
    removed before their network dependencies.

.EXAMPLE
    .\Remove-SRE-Resources.ps1

.EXAMPLE
    .\Remove-SRE-Resources.ps1 -EnvironmentName Prod -RemoteAccessMode AVD -WhatIf

.EXAMPLE
    .\Remove-SRE-Resources.ps1 -AdditionalResourceGroups 'Demo-RG-Custom-01' -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SubscriptionIDs = @(
        '7b58b5b8-9b57-4083-81d3-b0b9044d1ed7', # Hub Subscription
        '6c4975c1-149a-4a89-9593-77cdfa26417a', # Researcher Subscription
        'bedecb48-9cb1-4240-9761-0109c2de77c9'  # Virtual Desktop Subscription
    ),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentName = 'Demo',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkloadName = 'SRE',

    [Parameter()]
    [ValidateSet('All', 'Bastion', 'AVD')]
    [string]$RemoteAccessMode = 'All',

    [Parameter()]
    [string[]]$AdditionalResourceGroups = @(),

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ResourceGroupDeletionPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NamePrefix,

        [Parameter(Mandatory = $true)]
        [ValidateSet('All', 'Bastion', 'AVD')]
        [string]$AccessMode,

        [Parameter()]
        [string[]]$ManualResourceGroupNames = @()
    )

    $workloadResourceGroupNames = [System.Collections.Generic.List[string]]::new()
    $workloadResourceGroupNames.AddRange([string[]]@(
            "$NamePrefix-RG-DataOwnerApprover-01",
            "$NamePrefix-RG-Researcher-01"
        ))

    if ($AccessMode -in @('All', 'Bastion')) {
        $workloadResourceGroupNames.AddRange([string[]]@(
                "$NamePrefix-RG-Bastion-01",
                "$NamePrefix-RG-RDServerVM-01"
            ))
    }

    if ($AccessMode -in @('All', 'AVD')) {
        $workloadResourceGroupNames.Add("$NamePrefix-RG-AVD-01")
    }

    foreach ($resourceGroupName in $ManualResourceGroupNames) {
        if (-not [string]::IsNullOrWhiteSpace($resourceGroupName)) {
            $workloadResourceGroupNames.Add($resourceGroupName.Trim())
        }
    }

    @(
        [pscustomobject]@{
            Order              = 1
            Name               = 'Workload resources'
            Reason             = 'Removes VMs, Bastion, AVD, private endpoints, Logic Apps, Data Factory, and custom workload groups before shared dependencies.'
            ResourceGroupNames = @($workloadResourceGroupNames | Select-Object -Unique)
        }
        [pscustomobject]@{
            Order              = 2
            Name               = 'Private DNS resolver'
            Reason             = 'Removes the DNS resolver and inbound endpoint before deleting the hub VNet subnet they use.'
            ResourceGroupNames = @("$NamePrefix-RG-PrivateDNSResolver-01")
        }
        [pscustomobject]@{
            Order              = 3
            Name               = 'Private DNS zones'
            Reason             = 'Removes private DNS zones and VNet links before deleting linked VNets.'
            ResourceGroupNames = @("$NamePrefix-RG-PrivateDNSZones-01")
        }
        [pscustomobject]@{
            Order              = 4
            Name               = 'Network resources'
            Reason             = 'Removes VNets, subnets, peerings, route tables, NSGs, firewall, and related network resources after consumers are gone.'
            ResourceGroupNames = @("$NamePrefix-RG-Network-01")
        }
        [pscustomobject]@{
            Order              = 5
            Name               = 'Monitoring resources'
            Reason             = 'Removes Sentinel and Log Analytics last because diagnostics from other resources target this workspace.'
            ResourceGroupNames = @("$NamePrefix-RG-Sentinel-01")
        }
    )
}

function Get-ExpectedResourceGroupName {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$DeletionWaves
    )

    $DeletionWaves |
        ForEach-Object { $_.ResourceGroupNames } |
        Select-Object -Unique
}

function Get-DeletionWaveForResourceGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [object[]]$DeletionWaves
    )

    foreach ($deletionWave in $DeletionWaves) {
        if ($ResourceGroupName -in $deletionWave.ResourceGroupNames) {
            return $deletionWave
        }
    }

    return $null
}

function Select-SubscriptionContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionID
    )

    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionID -ErrorAction Stop
    $subscription | Set-AzContext -ErrorAction Stop | Out-Null
}

function Wait-ResourceGroupDeletionJob {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$DeletionJobs
    )

    if ($DeletionJobs.Count -eq 0) {
        return [pscustomobject]@{
            Completed = 0
            Failed    = 0
        }
    }

    Write-Host "Waiting for $($DeletionJobs.Count) deletion job(s) in this wave to finish..." -ForegroundColor Yellow

    $completedCount = 0
    $failedCount = 0

    foreach ($deletionJob in $DeletionJobs) {
        $job = $deletionJob.Job
        $null = Wait-Job -Job $job
        $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)

        if ($job.State -eq 'Completed') {
            Write-Host "  Deleted $($deletionJob.ResourceGroupName) in subscription $($deletionJob.SubscriptionID)" -ForegroundColor Green
            $completedCount++
        }
        else {
            $errorMessages = @($job.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason.Message } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($errorMessages.Count -eq 0 -and $jobOutput.Count -gt 0) {
                $errorMessages = @($jobOutput | ForEach-Object { $_.ToString() })
            }

            $failureDetail = if ($errorMessages.Count -gt 0) { $errorMessages -join ' ' } else { "Job ended with state '$($job.State)'." }
            Write-Warning "Deletion failed for $($deletionJob.ResourceGroupName) in subscription $($deletionJob.SubscriptionID). $failureDetail"
            $failedCount++
        }

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Completed = $completedCount
        Failed    = $failedCount
    }
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'SRE Resource Cleanup Script' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Environment: $EnvironmentName" -ForegroundColor Cyan
Write-Host "Workload: $WorkloadName" -ForegroundColor Cyan
Write-Host "Remote access mode: $RemoteAccessMode" -ForegroundColor Cyan
Write-Host ''

$deletionWaves = @(Get-ResourceGroupDeletionPlan -NamePrefix $EnvironmentName -AccessMode $RemoteAccessMode -ManualResourceGroupNames $AdditionalResourceGroups)
$expectedResourceGroupNames = @(Get-ExpectedResourceGroupName -DeletionWaves $deletionWaves)
$allResourceGroupsToDelete = [System.Collections.Generic.List[object]]::new()

foreach ($subscriptionID in $SubscriptionIDs) {
    Write-Host "Switching to subscription: $subscriptionID" -ForegroundColor Yellow

    try {
        Select-SubscriptionContext -SubscriptionID $subscriptionID
        Write-Host "Looking for expected resource groups in subscription: $subscriptionID" -ForegroundColor Green

        foreach ($resourceGroupName in $expectedResourceGroupNames) {
            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue

            if ($null -eq $resourceGroup) {
                continue
            }

            $resources = @(Get-AzResource -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue)
            $resourceCount = $resources.Count

            Write-Host "  Found $($resourceGroup.ResourceGroupName) (contains $resourceCount resource(s))" -ForegroundColor Cyan
            $deletionWave = Get-DeletionWaveForResourceGroup -ResourceGroupName $resourceGroup.ResourceGroupName -DeletionWaves $deletionWaves
            $allResourceGroupsToDelete.Add([pscustomobject]@{
                    ResourceGroupName = $resourceGroup.ResourceGroupName
                    SubscriptionID    = $subscriptionID
                    Location          = $resourceGroup.Location
                    ResourceCount     = $resourceCount
                    DeletionWaveOrder = $deletionWave.Order
                    DeletionWaveName  = $deletionWave.Name
                }) | Out-Null
        }
    }
    catch {
        Write-Warning "Error accessing subscription $subscriptionID. $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'Summary' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "Expected resource group names checked: $($expectedResourceGroupNames.Count)" -ForegroundColor Yellow
Write-Host "Total resource groups found: $($allResourceGroupsToDelete.Count)" -ForegroundColor Yellow

if ($allResourceGroupsToDelete.Count -eq 0) {
    Write-Host 'No matching resource groups were found.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Checked these resource group names:' -ForegroundColor Yellow
    foreach ($resourceGroupName in $expectedResourceGroupNames) {
        Write-Host "  - $resourceGroupName" -ForegroundColor Gray
    }
    exit 0
}

Write-Host ''
Write-Host 'Resource groups to be deleted by dependency wave:' -ForegroundColor Yellow
foreach ($deletionWave in $deletionWaves) {
    $resourceGroupsInWave = @($allResourceGroupsToDelete | Where-Object { $_.DeletionWaveOrder -eq $deletionWave.Order })
    if ($resourceGroupsInWave.Count -eq 0) {
        continue
    }

    Write-Host ''
    Write-Host "Wave $($deletionWave.Order): $($deletionWave.Name)" -ForegroundColor Yellow
    Write-Host "  $($deletionWave.Reason)" -ForegroundColor Gray
    foreach ($resourceGroup in $resourceGroupsInWave) {
        Write-Host "  - $($resourceGroup.ResourceGroupName) (Subscription: $($resourceGroup.SubscriptionID), Location: $($resourceGroup.Location), Resources: $($resourceGroup.ResourceCount))" -ForegroundColor Cyan
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Yellow
Write-Host 'WARNING: This permanently deletes the resource groups listed above.' -ForegroundColor Red
Write-Host '========================================' -ForegroundColor Yellow
Write-Host ''

if (-not $Force) {
    $confirmation = Read-Host "Type '$EnvironmentName' to confirm deletion"

    if ($confirmation -cne $EnvironmentName) {
        Write-Host 'Deletion cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ''
Write-Host 'Starting deletion process...' -ForegroundColor Yellow
Write-Host ''

$scheduledCount = 0
$deletedCount = 0
$failedCount = 0

foreach ($deletionWave in $deletionWaves) {
    $resourceGroupsInWave = @($allResourceGroupsToDelete | Where-Object { $_.DeletionWaveOrder -eq $deletionWave.Order })
    if ($resourceGroupsInWave.Count -eq 0) {
        continue
    }

    Write-Host ''
    Write-Host "Wave $($deletionWave.Order): $($deletionWave.Name)" -ForegroundColor Yellow
    $deletionJobs = [System.Collections.Generic.List[object]]::new()
    $waveStartFailedCount = 0

    foreach ($resourceGroup in $resourceGroupsInWave) {
        try {
            Select-SubscriptionContext -SubscriptionID $resourceGroup.SubscriptionID

            $targetDescription = "$($resourceGroup.ResourceGroupName) in subscription $($resourceGroup.SubscriptionID)"
            if ($PSCmdlet.ShouldProcess($targetDescription, 'Remove Azure resource group')) {
                Write-Host "Deleting resource group: $($resourceGroup.ResourceGroupName)" -ForegroundColor Yellow
                $job = Remove-AzResourceGroup -Name $resourceGroup.ResourceGroupName -Force -AsJob -ErrorAction Stop
                Write-Host "  Deletion job created for $($resourceGroup.ResourceGroupName)" -ForegroundColor Green
                $scheduledCount++
                $deletionJobs.Add([pscustomobject]@{
                        Job               = $job
                        ResourceGroupName = $resourceGroup.ResourceGroupName
                        SubscriptionID    = $resourceGroup.SubscriptionID
                    }) | Out-Null
            }
        }
        catch {
            Write-Warning "Error starting deletion for $($resourceGroup.ResourceGroupName). $($_.Exception.Message)"
            $waveStartFailedCount++
            $failedCount++
        }
    }

    $waveResult = Wait-ResourceGroupDeletionJob -DeletionJobs @($deletionJobs)
    $deletedCount += $waveResult.Completed
    $failedCount += $waveResult.Failed

    if ($waveStartFailedCount -gt 0 -or $waveResult.Failed -gt 0) {
        $waveFailureCount = $waveStartFailedCount + $waveResult.Failed
        Write-Warning "Stopping before the next wave because $waveFailureCount deletion(s) failed in wave $($deletionWave.Order). Resolve the failed deletion(s), then rerun the script."
        break
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'Deletion Process Complete' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "Resource groups scheduled for deletion: $scheduledCount" -ForegroundColor Green
Write-Host "Resource groups confirmed deleted: $deletedCount" -ForegroundColor Green
Write-Host "Failed deletions: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ''
Write-Host 'Deletion jobs are waited per dependency wave before the next wave starts.' -ForegroundColor Yellow
Write-Host ''
