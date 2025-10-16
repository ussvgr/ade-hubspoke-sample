@description('Location for resources.')
param locationName string = resourceGroup().location

@description('Name of the Virtual Network Manager')
param networkManagerName string = 'vnm-learn-prod-${locationName}-001'

@description('Name of the IPAM pool')
param ipamPoolName string = 'ipam-pool-learn-prod-001'

@description('Address prefix of the IPAM pool')
param ipamPoolAddressPrefix string = '10.0.0.0/16'

// Virtual Network Manager
resource networkManager 'Microsoft.Network/networkManagers@2024-05-01' = {
  name: networkManagerName
  location: locationName
  properties: {
    networkManagerScopes: {
      managementGroups: []
      subscriptions: [
        subscription().id
      ]
    }
    networkManagerScopeAccesses: [
      'Connectivity'
    ]
  }
}

// IPAM Pool
resource ipamPool 'Microsoft.Network/networkManagers/ipamPools@2024-05-01' = {
  parent: networkManager
  name: ipamPoolName
  location: locationName
  properties: {
    addressPrefixes: [
      ipamPoolAddressPrefix
    ]
  }
}
