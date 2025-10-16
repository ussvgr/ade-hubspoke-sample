// Module for creating Hub-to-Spoke peering in the Hub resource group
@description('Name of the Hub VNet')
param hubVnetName string

@description('Resource ID of the Spoke VNet')
param spokeVnetId string

@description('Name of the peering from Hub to Spoke')
param peeringName string

@description('Allow forwarded traffic from Spoke to Hub')
param allowForwardedTraffic bool = true

@description('Allow gateway transit in Hub VNet')
param allowGatewayTransit bool = true

@description('Allow virtual network access')
param allowVirtualNetworkAccess bool = true

// Reference to existing Hub VNet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
}

// Virtual Network Peering (Hub to Spoke)
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: hubVnet
  name: peeringName
  properties: {
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
  }
}

output peeringName string = hubToSpokePeering.name
output peeringState string = hubToSpokePeering.properties.peeringState
