@description('Deployment location')
param location string = resourceGroup().location

@description('Hub virtual network name')
param hubVnetName string = 'vnet-hub-001'

@description('Address space for hub VNet')
param hubAddressPrefix string = '192.168.0.0/24'

@description('Azure Firewall subnet name (must be AzureFirewallSubnet)')
param firewallSubnetName string = 'AzureFirewallSubnet'

@description('Address prefix for Azure Firewall subnet (must be /26 or larger)')
param firewallSubnetPrefix string = '192.168.0.0/26'

@description('Azure Firewall Management subnet name (required for Basic SKU)')
param firewallManagementSubnetName string = 'AzureFirewallManagementSubnet'

@description('Address prefix for Azure Firewall Management subnet (must be /26 or larger)')
param firewallManagementSubnetPrefix string = '192.168.0.64/26'

@description('Azure Firewall name')
param firewallName string = 'afw-hub-001'

@description('Azure Firewall Policy name')
param firewallPolicyName string = 'afwp-hub-001'

@description('Public IP name for Azure Firewall')
param firewallPublicIpName string = 'pip-afw-hub-001'

@description('Public IP name for Azure Firewall Management (required for Basic SKU)')
param firewallManagementPublicIpName string = 'pip-afw-mgmt-hub-001'

@description('Firewall SKU Tier: Basic / Standard / Premium')
@allowed([ 'Basic', 'Standard', 'Premium' ])
param firewallSkuTier string = 'Basic'

@description('Firewall SKU Name (Basic/Standard/Premiumは AZFW_VNet を使用。Hubは Virtual Hub 用)')
@allowed([ 'AZFW_VNet' ])
param firewallSkuName string = 'AZFW_VNet'

@description('Enable DNS Proxy on firewall')
param dnsProxyEnabled bool = true

@description('Create default Rule Collection Group')
param createRuleCollectionGroup bool = true

@description('Rule Collection Group name')
param ruleCollectionGroupName string = 'rcg-default'

@description('List of allowed outbound FQDNs (HTTPS) via application rules')
param allowedFqdns array = [ 'microsoft.com' ]

@description('Enable inbound SSH DNAT rule')
param enableNatSsh bool = false

@description('Private IP of target VM for SSH DNAT')
param natSshDestinationPrivateIp string = ''

@description('Source public IPs allowed for SSH ("*" means any)')
param natSshPublicSourceIpAddresses array = [ '*' ]

@description('Public SSH destination port (original)')
param natSshPublicPort int = 22

@description('Translated SSH port on target VM')
param natSshTargetPort int = 22

// Variables for rule construction
var appRules = [for fqdn in allowedFqdns: {
  name: 'allow-${replace(fqdn, '.', '-')}'
  ruleType: 'ApplicationRule'
  sourceAddresses: [ hubAddressPrefix ]
  protocols: [
    {
      protocolType: 'Https'
      port: 443
    }
  ]
  targetFqdns: [ fqdn ]
}]

// Hub Virtual Network with Firewall subnet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
	name: hubVnetName
	location: location
	properties: {
		addressSpace: {
			addressPrefixes: [ hubAddressPrefix ]
		}
		subnets: [
			{
				name: firewallSubnetName
				properties: {
					addressPrefix: firewallSubnetPrefix
				}
			}
			{
				name: firewallManagementSubnetName
				properties: {
					addressPrefix: firewallManagementSubnetPrefix
				}
			}
		]
	}
}

// Public IP for Azure Firewall
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
	name: firewallPublicIpName
	location: location
	sku: {
		name: 'Standard'
	}
	properties: {
		publicIPAllocationMethod: 'Static'
		idleTimeoutInMinutes: 4
	}
}

// Public IP for Azure Firewall Management (required for Basic SKU)
resource firewallManagementPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
	name: firewallManagementPublicIpName
	location: location
	sku: {
		name: 'Standard'
	}
	properties: {
		publicIPAllocationMethod: 'Static'
		idleTimeoutInMinutes: 4
	}
}

// Azure Firewall Policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
	name: firewallPolicyName
	location: location
	properties: {
		sku: {
			tier: firewallSkuTier
		}
		// DNS Proxy is only supported in Standard and Premium SKUs
		dnsSettings: (dnsProxyEnabled && (firewallSkuTier == 'Standard' || firewallSkuTier == 'Premium')) ? {
			enableProxy: true
		} : null
	}
}

// Firewall Policy Rule Collection Group (Network, Application, optional NAT)
resource firewallPolicyRuleGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = if (createRuleCollectionGroup) {
  name: ruleCollectionGroupName
  parent: firewallPolicy
  properties: {
    priority: 100
    ruleCollections: concat([
      {
        name: 'net-allow-outbound'
        priority: 100
        action: {
          type: 'Allow'
        }
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        rules: [
          {
            name: 'allow-any-outbound'
            ruleType: 'NetworkRule'
            ipProtocols: [ 'TCP', 'UDP' ]
            sourceAddresses: [ hubAddressPrefix ]
            destinationAddresses: [ '*' ]
            destinationPorts: [ '*' ]
          }
        ]
      }
      {
        name: 'app-allow-fqdns'
        priority: 110
        action: {
          type: 'Allow'
        }
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        rules: appRules
      }
    ], (enableNatSsh && natSshDestinationPrivateIp != '') ? [
      {
        name: 'nat-ssh'
        priority: 120
        action: {
          type: 'DNAT'
        }
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        rules: [
          {
            name: 'dnat-ssh'
            ruleType: 'NatRule'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: natSshPublicSourceIpAddresses
            destinationAddresses: [ firewallPublicIp.properties.ipAddress ]
            destinationPorts: [ string(natSshPublicPort) ]
            translatedAddress: natSshDestinationPrivateIp
            translatedPort: string(natSshTargetPort)
          }
        ]
      }
    ] : [])
  }
}

// Azure Firewall (depends on VNet subnet + public IP + policy)
resource azureFirewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
	name: firewallName
	location: location
	properties: {
    sku: {
      name: firewallSkuName
      tier: firewallSkuTier
    }
		firewallPolicy: {
			id: firewallPolicy.id
		}
		ipConfigurations: [
			{
				name: 'azureFirewallIpConfig'
				properties: {
					subnet: {
						id: hubVnet.properties.subnets[0].id
					}
					publicIPAddress: {
						id: firewallPublicIp.id
					}
				}
			}
		]
		managementIpConfiguration: {
			name: 'azureFirewallManagementIpConfig'
			properties: {
				subnet: {
					id: hubVnet.properties.subnets[1].id
				}
				publicIPAddress: {
					id: firewallManagementPublicIp.id
				}
			}
		}
	}
}

// Outputs
output hubVnetId string = hubVnet.id
output firewallId string = azureFirewall.id
output firewallPublicIp string = firewallPublicIp.properties.ipAddress
output firewallManagementPublicIp string = firewallManagementPublicIp.properties.ipAddress
output firewallPolicyId string = firewallPolicy.id
output ruleCollectionGroupId string = createRuleCollectionGroup ? firewallPolicyRuleGroup.id : ''
