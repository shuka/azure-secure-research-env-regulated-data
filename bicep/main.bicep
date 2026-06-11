targetScope = 'subscription'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = 'westus2'

@description('Short environment name used as a prefix for all resource names.')
@allowed([
  'Demo'
  'Dev'
  'Test'
  'Staging'
  'Prod'
])
param environmentName string = 'Prod'

@description('Tag - Workload Name.')
param workloadName string = 'SRERD'

@description('Tag - Solution Owner.')
param solutionOwner string = 'owner@example.com'

@description('Local administrator username for VMs.')
param adminUsername string = 'azureuser'

@description('Local administrator password for VMs.')
@secure()
param adminPassword string = ''

@description('Name of the Azure Key Vault containing the admin password secret.')
param keyVaultName string = ''

@description('Name of the secret in Key Vault containing the admin password.')
param keyVaultSecretName string = 'AdminPassword'

@description('Name of the resource group where the Key Vault is located.')
param keyVaultResourceGroupName string = ''

@description('Subscription ID where the Key Vault is located. Defaults to the hub subscription.')
param keyVaultSubscriptionId string = ''

@description('Options: Bastion or AVD. Determines whether to deploy Azure Bastion with a virtual machine or Azure Virtual Desktop for remote access to the environment. Default is Bastion.')
@allowed([
  'Bastion'
  'AVD'
])
param BastionOrAVD string = 'Bastion'

@description('Number of days to retain Azure Firewall logs and metrics in the connected Log Analytics workspace.')
param PolicyAnalyticsRetentionInDays int = 90

@description('Subscription ID where the research environment will be deployed. Used for cross-subscription resource deployments and role assignments.')
@minLength(36)
@maxLength(36)
param researcherSubscriptionID string = '00000000-0000-0000-0000-000000000000'

@description('Subscription ID where the hub VNet (with Firewall) will be deployed. Used for cross-subscription resource deployments and role assignments.')
@minLength(36)
@maxLength(36)
param hubSubscriptionID string = '00000000-0000-0000-0000-000000000000'

@description('Subscription ID where the Bastion and virtual desktop environment will be deployed. Used for cross-subscription resource deployments and role assignments.')
@minLength(36)
@maxLength(36)
param virtualDesktopSubscriptionID string = '00000000-0000-0000-0000-000000000000'

@description('VM size for Data Science VMs.')
param researcherVMSize string = 'Standard_D4ds_v5'

@description('Number of Data Science VMs.')
@minValue(1)
@maxValue(1)
param researcherVMCount int = 1

@description('The email address of the data approver, who will receive notifications and approval requests when researchers attempt to upload data to the secure environment.')
param dataApproverEmail string = 'dataapprover@example.com'

#disable-next-line no-hardcoded-env-urls
param blobPrivateLinkZoneName string = 'privatelink.blob.core.windows.net'

param privateDnsZoneNames array = [
  'privatelink.vaultcore.azure.net'
  'privatelink.datafactory.azure.net'
  'privatelink.azureml.ms'
]

@description('The string array of FQDNs needed to allow Azure Machine Configuration to access Microsoft-managed Storage Accounts in Azure. These URLs are used in the Azure Firewall Policy and are region-specific. Default values are for West US 2. Refer to this article for more information:')
param azureMachineConfigStorageFQDNs array = [
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigeuss1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigeus2s1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigwuss1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigwus2s1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigncuss1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigcuss1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigscuss1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigwus3s1.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'oaasguestconfigwcuss1.blob.core.windows.net'
]

// ── Hub VNET Parameters ───────────────────────────────────────────────────────────
@description('Address prefix for the hub virtual network.')
param net_hub_vnetAddressPrefix string = '10.100.0.0/23'

@description('Address prefix for the GatewaySubnet (minimum /28).')
param net_hub_gatewaySubnetPrefix string = '10.100.0.0/26'

@description('Address prefix for AzureFirewallSubnet (minimum /26).')
param net_hub_firewallSubnetPrefix string = '10.100.0.64/26'

@description('Address prefix for Azure DNS Private Resolver Inbound Subnet (minimum /28).')
param net_hub_azDNSPrivateResolverInboundSubnetPrefix string = '10.100.0.128/28'

@description('Address prefix for Azure DNS Private Resolver Outbound Subnet (minimum /28).')
param net_hub_azDNSPrivateResolverOutboundSubnetPrefix string = '10.100.0.144/28'

// ── Remote Desktop VNET Parameters ───────────────────────────────────────────────────────────
@description('Address prefix for the virtual network.')
param net_RemoteDesktop_vnetAddressPrefix string = '10.100.40.0/21'

@description('Address prefix for the Azure Bastion subnet.')
param net_RemoteDesktop_bastionSubnetPrefix string = '10.100.40.0/26'

param net_RemoteDesktop_webSubnetPrefix string = '10.100.40.64/27'
param net_RemoteDesktop_appSubnetPrefix string = '10.100.40.96/27'
param net_RemoteDesktop_dbSubnetPrefix string = '10.100.40.128/27'
@description('Address prefix for the storage subnet, used with Azure Storage Accounts and FSLogix.')
param net_RemoteDesktop_storageSubnetPrefix string = '10.100.40.160/27'

param net_RemoteDesktop_webVNETIntegrationSubnetPrefix string = '10.100.40.192/27'

@description('Address prefix for the Remote Desktop Server subnet.')
param net_RemoteDesktop_rdServerSubnetPrefix string = '10.100.41.0/24'

@description('Address prefix for the first Azure Virtual Desktop subnet.')
param net_RemoteDesktop_avdSubnetPrefix string = '10.100.42.0/24'

// ── Researcher VNET Parameters ───────────────────────────────────────────────────────────
@description('Address prefix for the Researcher Spoke Azure Virtual Network.')
param net_researcher_vnetAddressPrefix string = '10.100.56.0/21'

param net_researcher_webSubnetPrefix string = '10.100.56.64/27'
param net_researcher_appSubnetPrefix string = '10.100.56.96/27'
param net_researcher_dbSubnetPrefix string = '10.100.56.128/27'

@description('Address prefix for the storage subnet, used with Azure Storage Accounts and FSLogix.')
param net_researcher_storageSubnetPrefix string = '10.100.56.160/27'

param net_researcher_webVNETIntegrationSubnetPrefix string = '10.100.56.192/27'

@description('Address prefix for the first Data Science Server subnet.')
param net_researcher_ServerSubnetPrefix string = '10.100.61.0/28'

@description('The date and time in UTC format. Used as part of the deployment name')
param deploymentTimestamp string = utcNow()

// ── Variables ───────────────────────────────────────────────────────────
var privateDnsZoneNamesArray = concat([blobPrivateLinkZoneName], privateDnsZoneNames)

var blobStoragePrivateDnsZoneId = resourceId(
  hubSubscriptionID,
  hubSub_framing.outputs.privateDNSZonesRGName,
  'Microsoft.Network/privateDnsZones',
  blobPrivateLinkZoneName
)

var keyVaultPrivateDnsZoneId = resourceId(
  hubSubscriptionID,
  hubSub_framing.outputs.privateDNSZonesRGName,
  'Microsoft.Network/privateDnsZones',
  'privatelink.vaultcore.azure.net'
)

var dataFactoryPrivateDnsZoneId = resourceId(
  hubSubscriptionID,
  hubSub_framing.outputs.privateDNSZonesRGName,
  'Microsoft.Network/privateDnsZones',
  'privatelink.datafactory.azure.net'
)

var azureMLPrivateDnsZoneId = resourceId(
  hubSubscriptionID,
  hubSub_framing.outputs.privateDNSZonesRGName,
  'Microsoft.Network/privateDnsZones',
  'privatelink.azureml.ms'
)

@description('Azure DNS Private Resolver Inbound Endpoint Static Private IP Address. Must be within the address range of the AzDNSPRInbound01 subnet defined in the hub virtual network.')
var azDNSPRInboundStaticIPCIDR = cidrSubnet(net_hub_azDNSPrivateResolverInboundSubnetPrefix, 32, 4)

var net_hub_azDNSPRInboundStaticIP = first(split(azDNSPRInboundStaticIPCIDR, '/'))

@description('Azure Firewall Private IP Address. This is the 5th usable IP in the AzureFirewallSubnet.')
var firewallPrivateIPCIDR = cidrSubnet(net_hub_firewallSubnetPrefix, 32, 4)

var net_hub_azureFirewallPrivateIP = first(split(firewallPrivateIPCIDR, '/'))

var vNETDNSServers = [
  net_hub_azureFirewallPrivateIP
]

@description('Tags applied to every resource.')
var tags = {
  Description: 'Secure Research Environment for Regulated Data'
  Environment: environmentName
  Owner: solutionOwner
  WorkloadName: workloadName
}

@description('Key Vault reference ID for audit purposes. Indicates the source of the admin password.')
var keyVaultSecretId = !empty(keyVaultName) && !empty(keyVaultResourceGroupName) ? '/subscriptions/${keyVaultSubscriptionId}/resourceGroups/${keyVaultResourceGroupName}/providers/Microsoft.KeyVault/vaults/${keyVaultName}/secrets/${keyVaultSecretName}' : ''

/// ── Subscription Deployments - Foundation (VNETs, RTs, NSGs) ───────────────────────
@description('Hub Subscription - Foundational components.')
module hubSub_foundation 'modules/subscriptions/hubSub_foundation.bicep' = {
  name: 'hubSub_foundation_${deploymentTimestamp}'
  scope: subscription(hubSubscriptionID)
  params: {
    location: location
    environmentName: environmentName
    net_hub_vnetAddressPrefix: net_hub_vnetAddressPrefix
    net_hub_gatewaySubnetPrefix: net_hub_gatewaySubnetPrefix
    net_hub_firewallSubnetPrefix: net_hub_firewallSubnetPrefix
    net_hub_azDNSPrivateResolverInboundSubnetPrefix: net_hub_azDNSPrivateResolverInboundSubnetPrefix
    net_hub_azDNSPrivateResolverOutboundSubnetPrefix: net_hub_azDNSPrivateResolverOutboundSubnetPrefix
    vNETDNSServers: vNETDNSServers
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}

@description('Virtual Desktop Subscription - Foundational components.')
module virtualDesktopSub_foundation 'modules/subscriptions/virtualDesktopSub_foundation.bicep' = {
  name: 'virtualDesktopSub_foundation_${deploymentTimestamp}'
  scope: subscription(virtualDesktopSubscriptionID)
  params: {
    location: location
    environmentName: environmentName
    net_RemoteDesktop_vnetAddressPrefix: net_RemoteDesktop_vnetAddressPrefix
    net_RemoteDesktop_bastionSubnetPrefix: net_RemoteDesktop_bastionSubnetPrefix
    net_RemoteDesktop_webSubnetPrefix: net_RemoteDesktop_webSubnetPrefix
    net_RemoteDesktop_appSubnetPrefix: net_RemoteDesktop_appSubnetPrefix
    net_RemoteDesktop_dbSubnetPrefix: net_RemoteDesktop_dbSubnetPrefix
    net_RemoteDesktop_storageSubnetPrefix: net_RemoteDesktop_storageSubnetPrefix
    net_RemoteDesktop_webVNETIntegrationSubnetPrefix: net_RemoteDesktop_webVNETIntegrationSubnetPrefix
    net_RemoteDesktop_rdServerSubnetPrefix: net_RemoteDesktop_rdServerSubnetPrefix
    net_RemoteDesktop_avdSubnetPrefix: net_RemoteDesktop_avdSubnetPrefix
    net_hub_azureFirewallPrivateIP: net_hub_azureFirewallPrivateIP
    vNETDNSServers: vNETDNSServers
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}

@description('Researcher Subscription - Foundational components.')
module researcherSub_foundation 'modules/subscriptions/researcherSub_foundation.bicep' = {
  name: 'researcherSub_foundation_${deploymentTimestamp}'
  scope: subscription(researcherSubscriptionID)
  params: {
    location: location
    environmentName: environmentName
    net_researcher_vnetAddressPrefix: net_researcher_vnetAddressPrefix
    net_researcher_webSubnetPrefix: net_researcher_webSubnetPrefix
    net_researcher_appSubnetPrefix: net_researcher_appSubnetPrefix
    net_researcher_dbSubnetPrefix: net_researcher_dbSubnetPrefix
    net_researcher_storageSubnetPrefix: net_researcher_storageSubnetPrefix
    net_researcher_webVNETIntegrationSubnetPrefix: net_researcher_webVNETIntegrationSubnetPrefix
    net_researcher_ServerSubnetPrefix: net_researcher_ServerSubnetPrefix
    vNETDNSServers: vNETDNSServers
    net_hub_azureFirewallPrivateIP: net_hub_azureFirewallPrivateIP
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}

/// ── Subscription Deployments - Framing (VNET Peerings) ───────────────────────

module hubSub_framing 'modules/subscriptions/hubSub_framing.bicep' = {
  name: 'hubSub_framing_${deploymentTimestamp}'
  scope: subscription(hubSubscriptionID)
  params: {
    location: location
    environmentName: environmentName
    net_hub_vnetId: hubSub_foundation.outputs.hubVNETId
    net_hub_firewallSubnetId: hubSub_foundation.outputs.hubVNETFirewallSubnetId
    PolicyAnalyticsRetentionInDays: PolicyAnalyticsRetentionInDays
    logAnalyticsWorkspaceId: hubSub_foundation.outputs.logAnalyticsWorkspaceResourceId
    remoteDesktopVnetId: virtualDesktopSub_foundation.outputs.rdVnetId
    researcherVnetId: researcherSub_foundation.outputs.researcherVnetId
    net_hub_azDNSPRInboundStaticIP: net_hub_azDNSPRInboundStaticIP
    privateDnsZoneNamesArray: privateDnsZoneNamesArray
    net_hub_azureFirewallPrivateIP: net_hub_azureFirewallPrivateIP
    deploymentTimestamp: deploymentTimestamp
    azureMachineConfigStorageFQDNs: azureMachineConfigStorageFQDNs
    tags: tags
  }
}

module virtualDesktopSub_framing 'modules/subscriptions/virtualDesktopSub_framing.bicep' = {
  name: 'virtualDesktopSub_framing_${deploymentTimestamp}'
  scope: subscription(virtualDesktopSubscriptionID)
  params: {
    remoteDesktopVnetRgName: virtualDesktopSub_foundation.outputs.rdVnetResourceGroupName
    remoteDesktopVnetName: virtualDesktopSub_foundation.outputs.rdVnetName
    hubVnetName: hubSub_foundation.outputs.hubVNETName
    hubVnetId: hubSub_foundation.outputs.hubVNETId
    deploymentTimestamp: deploymentTimestamp
  }
}

module researcherSub_framing 'modules/subscriptions/researcherSub_framing.bicep' = {
  name: 'researcherSub_framing_${deploymentTimestamp}'
  scope: subscription(researcherSubscriptionID)
  params: {
    researcherVnetRgName: researcherSub_foundation.outputs.researcherVnetResourceGroupName
    researcherVnetName: researcherSub_foundation.outputs.researcherVnetName
    hubVnetName: hubSub_foundation.outputs.hubVNETName
    hubVnetId: hubSub_foundation.outputs.hubVNETId
    deploymentTimestamp: deploymentTimestamp
  }
}

/// ── Subscription Deployments - Workloads (DNS, Storage, AVD, etc.) ───────────────────────
@description('Hub Subscription - Workload components, including Azure Firewall and Private DNS Resolver.')
module hubSub_workload 'modules/subscriptions/hubSub_workload.bicep' = {
  name: 'hubSub_workload_${deploymentTimestamp}'
  scope: subscription(hubSubscriptionID)
  params: {
    location: location
    environmentName: environmentName
    net_hub_vnetId: hubSub_foundation.outputs.hubVNETId
    net_hub_azDNSPRInboundSubnetId: hubSub_foundation.outputs.hubVNETDNSPRInboundSubnetId
    net_hub_azDNSPRInboundStaticIP: net_hub_azDNSPRInboundStaticIP
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}

@description('Virtual Desktop Subscription - Workload components, including Bastion, Azure Virtual Desktop, and related resources.')
module virtualDesktopSub_workload 'modules/subscriptions/virtualDesktopSub_workload.bicep' = {
  name: 'virtualDesktopSub_workload_${deploymentTimestamp}'
  scope: subscription(virtualDesktopSubscriptionID)
  dependsOn: [hubSub_workload, hubSub_framing]
  params: {
    location: location
    environmentName: environmentName
    BastionOrAVD: BastionOrAVD
    adminUsername: adminUsername
    adminPassword: adminPassword
    logAnalyticsWorkspaceId: hubSub_foundation.outputs.logAnalyticsWorkspaceResourceId
    net_RemoteDesktop_bastionSubnetId: virtualDesktopSub_foundation.outputs.bastionSubnetId
    net_RemoteDesktop_rdServerSubnetId: virtualDesktopSub_foundation.outputs.rdServerSubnetId
    net_RemoteDesktop_avdSubnetId: virtualDesktopSub_foundation.outputs.avdSubnetId
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}

@description('Researcher Subscription - Workload components.')
module researcherSub_workload 'modules/subscriptions/researcherSub_workload.bicep' = {
  name: 'researcherSub_workload_${deploymentTimestamp}'
  scope: subscription(researcherSubscriptionID)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [hubSub_workload, hubSub_framing]
  params: {
    location: location
    environmentName: environmentName
    net_researcher_vnetId: researcherSub_foundation.outputs.researcherVnetId
    net_researcher_App01SubnetId: researcherSub_foundation.outputs.App01SubnetId
    net_researcher_Storage01SubnetId: researcherSub_foundation.outputs.Storage01SubnetId
    net_researcher_KeyVault01SubnetId: researcherSub_foundation.outputs.KeyVault01SubnetId
    net_researcher_ResearcherVMSubnet01SubnetId: researcherSub_foundation.outputs.ResearcherVMSubnet01SubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    researcherVMSize: researcherVMSize
    researcherVMCount: researcherVMCount
    dataApproverEmail: dataApproverEmail
    logAnalyticsWorkspaceId: hubSub_foundation.outputs.logAnalyticsWorkspaceResourceId
    blobStoragePrivateDnsZoneId: blobStoragePrivateDnsZoneId
    keyVaultPrivateDnsZoneId: keyVaultPrivateDnsZoneId
    dataFactoryPrivateDnsZoneId: dataFactoryPrivateDnsZoneId
    azureMLPrivateDnsZoneId: azureMLPrivateDnsZoneId
    deploymentTimestamp: deploymentTimestamp
    tags: tags
  }
}
// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Firewall.')
output firewallResourceID string = hubSub_framing.outputs.firewallId

@description('Resource ID of the Bastion.')
output bastionResourceID string = ((BastionOrAVD == 'Bastion')
  ? virtualDesktopSub_workload.outputs.bastionResourceId
  : 'Bastion deployment not selected, no Bastion resource created.')

@description('Resource ID of the hub virtual network.')
output hubVnetId string = hubSub_foundation.outputs.hubVNETId

@description('Resource ID of the spoke virtual network.')
output remoteDesktopVnetId string = virtualDesktopSub_foundation.outputs.rdVnetId

@description('Resource ID of the research virtual network.')
output researchVnetId string = researcherSub_foundation.outputs.researcherVnetId

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsWorkspaceId string = hubSub_foundation.outputs.logAnalyticsWorkspaceResourceId
