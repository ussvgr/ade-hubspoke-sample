@description('Application name used for naming resources')
param applicationName string

@description('Location for virtual network')
param locationName string = resourceGroup().location

// Construct VNet and Subnet names from application name
var vnetName = 'vnet-${applicationName}'
var subnetName = 'snet-${applicationName}-default'

@description('IPAM Network Manager resource group name')
param ipamResourceGroup string = 'rg-network-manager'

@description('Network Manager name')
param networkManagerName string = 'vnm-learn-prod-japaneast-001'

@description('IPAM Pool name')
param ipamPoolName string = 'ipam-pool-learn-prod-001'

@description('Number of IP addresses for virtual network')
param vnetNumberOfIpAddresses string = '256'

@description('Number of IP addresses for subnet')
param subnetNumberOfIpAddresses string = '128'

@description('Remote VNet resource group name for peering')
param remoteVnetResourceGroup string = 'rg-hub'

@description('Remote VNet name for peering')
param remoteVnetName string = 'vnet-hub-001'

@description('Allow forwarded traffic from remote VNet')
param allowForwardedTraffic bool = true

@description('Allow virtual network access')
param allowVirtualNetworkAccess bool = true

@description('Allow gateway transit')
param allowGatewayTransit bool = false

@description('Use remote gateways')
param useRemoteGateways bool = false

// Get subscription ID from deployment context
var subscriptionId = subscription().subscriptionId

// Construct resource IDs dynamically
var ipamPoolId = '/subscriptions/${subscriptionId}/resourceGroups/${ipamResourceGroup}/providers/Microsoft.Network/networkManagers/${networkManagerName}/ipamPools/${ipamPoolName}'
var remoteVnetId = '/subscriptions/${subscriptionId}/resourceGroups/${remoteVnetResourceGroup}/providers/Microsoft.Network/virtualNetworks/${remoteVnetName}'

// Route Table name
var routeTableName = 'rt-${applicationName}'

// Azure Firewall IP address
var azureFirewallIp = '192.168.0.4'

// Route Table
resource routeTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: routeTableName
  location: locationName
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-azfw'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewallIp
        }
      }
    ]
  }
}

// Virtual Network
resource newVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: locationName
  properties: {
    addressSpace: {
      ipamPoolPrefixAllocations: [
        {
          numberOfIpAddresses: vnetNumberOfIpAddresses
          pool: {
            id: ipamPoolId
          }
        }
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          ipamPoolPrefixAllocations: [
            {
              numberOfIpAddresses: subnetNumberOfIpAddresses
              pool: {
                id: ipamPoolId
              }
            }
          ]
          routeTable: {
            id: routeTable.id
          }
        }
      }
    ]
  }
}

// Virtual Network Peering (Spoke to Hub)
resource vnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: newVnet
  name: '${vnetName}-to-${remoteVnetName}'
  properties: {
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
  }
}

// Module to create Hub-to-Spoke peering in the Hub resource group
module hubPeering 'hub-peering.bicep' = {
  name: 'deploy-hub-peering-${applicationName}'
  scope: resourceGroup(remoteVnetResourceGroup)
  params: {
    hubVnetName: remoteVnetName
    spokeVnetId: newVnet.id
    peeringName: '${remoteVnetName}-to-${vnetName}'
    allowForwardedTraffic: true
    allowGatewayTransit: true
    allowVirtualNetworkAccess: true
  }
}
