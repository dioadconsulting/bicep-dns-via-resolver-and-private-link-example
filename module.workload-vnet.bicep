@description('Location for all resources.')
param location string = resourceGroup().location
param name string
param privatelinkServiceId string

//var vnetName = 'myVirtualNetwork'
var vnetWorkloadName = '${name}VNet'
var vnetAddressPrefix = '10.0.0.0/16'

var endpointSubnetPrefix = '10.0.2.0/24'
var endpointSubnetName = '${name}BackendSubnet'
var workloadSubnetPrefix = '10.0.0.0/24'
var workloadSubnetName = '${name}EndpointSubnet'
var resolverSubnetPrefix = '10.0.4.0/24'
var resolverSubnetName = '${name}ResolverSubnet'

var workloadNetworkInterfaceName = '${name}ConsumerNic'

@description('Username for the Virtual Machine.')
param vmAdminUsername string

@description('Password for the Virtual Machine. The password must be at least 12 characters long and have lower case, upper characters, digit and a special character (Regex match)')
@secure()
param vmAdminPassword string

@description('If set to false, the DHCP DNS server list will be set to the IP address of the private link endpoint, if false will use Azure DNS and outbound resolver')
param useOutboundResolver bool = true

var privateEndpointName = '${name}DnsEndpoint'

var vmWorkloadName = take('${name}${uniqueString(resourceGroup().id)}', 15)

var networkInterfaceConsumerName = '${vmWorkloadName}NetInt'

var resolverEndpointIpAddress = '10.0.2.32'
var dnsResolverName = '${name}Resolver'

var customDnsServers = useOutboundResolver ? null : [ resolverEndpointIpAddress ]

resource vnetWorkload 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetWorkloadName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: customDnsServers
    }
  }
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnetWorkload
  name: workloadSubnetName
  properties: {
    addressPrefix: workloadSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
  dependsOn : [
    endpointSubnet
  ]
}

resource endpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnetWorkload
  name: endpointSubnetName
  properties: {
    addressPrefix: endpointSubnetPrefix
    networkSecurityGroup: {
      id: endpointSecurityGroup.id
    }
  }
}

resource resolverSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = if (useOutboundResolver) {
  parent: vnetWorkload
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
  dependsOn : [
    endpointSubnet
  ]
}


resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = if (useOutboundResolver) {
  name: dnsResolverName
  location: location
  properties: {
    virtualNetwork: {
      id: vnetWorkload.id
    }
  }
}


resource outEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = if (useOutboundResolver) {
  parent: resolver
  name: '${name}DnsOutbound'
  location: location
  properties: {
    subnet: {
      id: resolverSubnet.id
    }
  }
}

resource fwruleSet 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = if (useOutboundResolver) {
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

resource resolverLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = if (useOutboundResolver) {
  parent: fwruleSet
  name: '${dnsResolverName}DnsVnetLink'
  properties: {
    virtualNetwork: {
      id: vnetWorkload.id
    }
  }
}


// this could be used to blackhole all domains by default
resource blackholeAllDnsRequests 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = if (useOutboundResolver){
  parent: fwruleSet
  name: '${dnsResolverName}ForwardAllDnsRequests'
  properties: {
    domainName: '.' // forward all requests
    targetDnsServers: [
      {
        ipAddress: '192.0.2.53' // 192.0.2.0/24 TEST-NET-1 (RFC-5737) , resolverEndpointIpAddress
        port: 53
      }
    ]
  }
}

resource allowSlashdotAllDnsRequests 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = if (useOutboundResolver){
  parent: fwruleSet
  name: '${dnsResolverName}AllowSlashdotDnsRequests'
  properties: {
    domainName: 'slashdot.org.' // forward all requests
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
      id: endpointSubnet.id
    }
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
    vnetWorkload
  ]
}

resource vmWorkloadPip 'Microsoft.Network/publicIPAddresses@2023-04-01' =  {
  name: '${vmWorkloadName}PublicIp'
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

resource workloadSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
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
      //   name: 'AllowDnsInbound'
      //   properties: {
      //     description: 'Allow DNS Inbound Traffic (resolver to private-link endpoint)'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRanges: [
      //       '53'
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
    ]
  }
}

resource endpointSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${name}BackendSecurityGroup-${location}'
  location: location
  properties: {
    securityRules: [
      // { 
      //   name: 'AllowDnsOutbound'
      //   properties: {
      //     description: 'Allow Workload Outbound DNS Traffic (resolver to private-link endpoint)'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRanges: [
      //       '53'
      //     ]
      //     sourceAddressPrefix: 'virtualNetwork'
      //     destinationAddressPrefix: 'virtualNetwork'
      //     access: 'Allow'
      //     priority: 101
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
      //   name: 'AllowSSHInbound'
      //   properties: {
      //     description: 'Allow SSH Traffic'
      //     protocol: 'Tcp'
      //     sourcePortRange: '*'
      //     destinationPortRanges: [
      //       '22'
      //     ]
      //     sourceAddressPrefix: '0.0.0.0/0'
      //     destinationAddressPrefix: 'virtualNetwork'
      //     access: 'Allow'
      //     priority: 100
      //     direction: 'Inbound'
      //   }
      // }
    ]
  }
}

resource workloadNetworkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: workloadNetworkInterfaceName
  location: location
  tags: {
    displayName: workloadNetworkInterfaceName
  }
  properties: {
    networkSecurityGroup: {
      id: workloadSecurityGroup.id
    }
    ipConfigurations: [
      {
        name: 'IpConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: vmWorkloadPip.id
          }
          subnet: {
            id: workloadSubnet.id
          }
        }
      }
    ]
  }
}


resource vmWorkload 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmWorkloadName
  location: location
  tags: {
    displayName: vmWorkloadName
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
        offer: 'ubuntu-24_04-lts'
        sku: 'ubuntu-pro-gen1'
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
          id: workloadNetworkInterface.id
          properties: {
            deleteOption: 'Delete'
            primary: true
          }
        }
      ]
    }
    //userData: loadFileAsBase64(userDataPath)
    osProfile: {
      computerName: vmWorkloadName
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
