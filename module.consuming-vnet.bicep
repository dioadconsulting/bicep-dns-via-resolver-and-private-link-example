@description('Location for all resources.')
param location string = resourceGroup().location
param name string
param privatelinkServiceId string

//var vnetName = 'myVirtualNetwork'
var vnetConsumerName = '${name}VNet'
var vnetAddressPrefix = '10.0.0.0/16'

var backendSubnetPrefix = '10.0.2.0/24'
var backendSubnetName = 'backendSubnet'
var consumerSubnetPrefix = '10.0.0.0/24'
var consumerSubnetName = 'endpointSubnet'
var resolverSubnetPrefix = '10.0.1.0/24'
var resolverSubnetName = 'resolverSubnet'

var consumerNetworkInterfaceName = '${name}ConsumerNic'

@description('Username for the Virtual Machine.')
param vmAdminUsername string

@description('Password for the Virtual Machine. The password must be at least 12 characters long and have lower case, upper characters, digit and a special character (Regex match)')
@secure()
param vmAdminPassword string

var privateEndpointName = '${name}DnsEndpoint'

var vmConsumerName = take('${name}${uniqueString(resourceGroup().id)}', 15)

var networkInterfaceConsumerName = '${vmConsumerName}NetInt'

var resolverEndpointIpAddress = '10.0.2.32'
var dnsResolverName = '${name}Resolver'


resource vnetConsumer 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetConsumerName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // subnets: [
    //   // {
    //   //   name: consumerSubnetName
    //   //   properties: {
    //   //     addressPrefix: consumerSubnetPrefix
    //   //     privateEndpointNetworkPolicies: 'Disabled'
    //   //   }
    //   // }
    //   // {
    //   //   name: backendSubnetName
    //   //   properties: {
    //   //     addressPrefix: backendSubnetPrefix
    //   //     networkSecurityGroup: {
    //   //       id: consumerSecurityGroup.id
    //   //     }
    //   //   }
    //   // }
    //   // {
    //   //   name: resolverSubnetName
    //   //   properties: {
    //   //     addressPrefix: resolverSubnetPrefix
    //   //     delegations: [
    //   //       {
    //   //         name: 'Microsoft.Network.dnsResolvers'
    //   //         properties: {
    //   //           serviceName: 'Microsoft.Network/dnsResolvers'
    //   //         }
    //   //       }
    //   //     ]
    //   //   }
    //   // }
    // ]
  }
}

resource consumerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnetConsumer
  name: consumerSubnetName
  properties: {
    addressPrefix: consumerSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnetConsumer
  name: backendSubnetName
  properties: {
    addressPrefix: backendSubnetPrefix
    networkSecurityGroup: {
      id: consumerSecurityGroup.id
    }
  }
}

resource resolverSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnetConsumer
  name: resolverSubnetName
  properties: {
    addressPrefix: resolverSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.Network/dnsResolvers'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}


resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: dnsResolverName
  location: location
  properties: {
    virtualNetwork: {
      id: vnetConsumer.id
    }
  }
}

resource outEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: resolver
  name: '${name}DnsOutbound'
  location: location
  properties: {
    subnet: {
      id: resolverSubnet.id
    }
  }
}

resource fwruleSet 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: '${dnsResolverName}RuleSet'
  location: location
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outEndpoint.id
      }
    ]
  }
}

resource resolverLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: fwruleSet
  name: '${dnsResolverName}DnsVnetLink'
  properties: {
    virtualNetwork: {
      id: vnetConsumer.id
    }
  }
}


// this could be used to blackhole all domains by default
resource fwRules 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = {
  parent: fwruleSet
  name: '${dnsResolverName}ForwardAllDnsRequests'
  properties: {
    domainName: '.' // forward all requests
    targetDnsServers: [
      {
        ipAddress: resolverEndpointIpAddress
        port: 53
      }
    ]
  }
}


resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: backendSubnet.id
    }
    // customNetworkInterfaceName: networkInterfaceConsumer.name
    // ipConfigurations: [
    //   {
    //     name: 'privateEndpointIpConfig'
    //     properties: {
    //       groupId: 'Dynamic'
    //       memberName: 'myMember'
    //     }
    //   }
    // ]
    customNetworkInterfaceName: networkInterfaceConsumerName
    ipConfigurations: [
      {
        name: 'IpConfig'
        properties: {
          privateIPAddress: resolverEndpointIpAddress
          
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: privatelinkServiceId
        }
      }
    ]
  }
  dependsOn: [
    vnetConsumer
  ]
}

resource vmConsumerPip 'Microsoft.Network/publicIPAddresses@2023-04-01' =  {
  name: '${vmConsumerName}PublicIp'
  location: location
  sku: {
    name: 'Standard'
  }

  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

resource consumerSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${name}ConsumerSecurityGroup-${location}'
  location: location
  properties: {
    securityRules: [
      { 
        name: 'AllowDnsOutbound'
        properties: {
          description: 'Allow Workload Outbound DNS Traffic (resolver to private-link endpoint)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
          ]
          sourceAddressPrefix: 'virtualNetwork'
          destinationAddressPrefix: 'virtualNetwork'
          access: 'Allow'
          priority: 101
          direction: 'Outbound'
        }
      }
      // { 
      //   name: 'AllowDNSOutboundLocal'
      //   properties: {
      //     description: 'Allow Workload Outbound Traffic'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRanges: [
      //       '53'
      //     ]
      //     sourceAddressPrefix: 'virtualNetwork'
      //     destinationAddressPrefix: '168.63.129.16/32'
      //     access: 'Allow'
      //     priority: 102
      //     direction: 'Outbound'
      //   }
      // }
      { 
        name: 'AllowDnsInbound'
        properties: {
          description: 'Allow DNS Inbound Traffic (resolver to private-link endpoint)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
          ]
          sourceAddressPrefix: 'virtualNetwork'
          destinationAddressPrefix: 'virtualNetwork'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      // { 
      //   name: 'AllowDNSInbound'
      //   properties: {
      //     description: 'Allow DNS Traffic'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRanges: [
      //       '54'
      //     ]
      //     sourceAddressPrefix: 'virtualNetwork'
      //     destinationAddressPrefix: 'virtualNetwork'
      //     access: 'Allow'
      //     priority: 101
      //     direction: 'Inbound'
      //   }
      // }
      { 
        name: 'AllowSSHInbound'
        properties: {
          description: 'Allow SSH Traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
          ]
          sourceAddressPrefix: '0.0.0.0/0'
          destinationAddressPrefix: 'virtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      // {
      //   name: 'DenyAllInbound'
      //   properties: {
      //     description: 'No further inbound traffic allowed.'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRange: '*'
      //     sourceAddressPrefix: '*'
      //     destinationAddressPrefix: '*'
      //     access: 'Deny'
      //     priority: 1000
      //     direction: 'Inbound'
      //   }
      // }
      // {
      //   name: 'DenyAllOutbound'
      //   properties: {
      //     description: 'No further outbound traffic allowed.'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRange: '*'
      //     sourceAddressPrefix: '*'
      //     destinationAddressPrefix: '*'
      //     access: 'Deny'
      //     priority: 1000
      //     direction: 'Outbound'
      //   }
      // }
    ]
  }
}

resource consumerNetworkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: consumerNetworkInterfaceName
  location: location
  tags: {
    displayName: consumerNetworkInterfaceName
  }
  properties: {
    networkSecurityGroup: {
      id: consumerSecurityGroup.id
    }
    ipConfigurations: [
      {
        name: 'IpConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: vmConsumerPip.id
          }
          subnet: {
            id: consumerSubnet.id
          }
        }
      }
    ]
  }
}


resource vmConsumer 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmConsumerName
  location: location
  tags: {
    displayName: vmConsumerName
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ats_v2'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        caching: 'ReadOnly'
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-mantic'
        sku: '23_10-gen2'
        version: 'latest'
      }
      dataDisks: []
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: null
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: consumerNetworkInterface.id
          properties: {
            deleteOption: 'Delete'
            primary: true
          }
        }
      ]
    }
    //userData: loadFileAsBase64(userDataPath)
    osProfile: {
      computerName: vmConsumerName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    priority: 'Regular'
  }
}
