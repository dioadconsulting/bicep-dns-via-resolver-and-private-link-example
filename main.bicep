@description('Username for the Virtual Machines.')
param vmAdminUsername string = 'dns-example'

@description('Password for the Virtual Machines. The password must be at least 12 characters long and have lower case, upper characters, digit and a special character (Regex match)')
@secure()
param vmAdminPassword string

param location string = resourceGroup().location

module privateLinkService 'module.private-link-service.bicep' = {
  name: 'private-link-service'
  params: {
    location: location
    
    vmAdminPassword:vmAdminPassword
    vmAdminUsername:vmAdminUsername
  }
}

module consumerOne 'module.consuming-vnet.bicep' = {
  name: 'consumerOne'
  params: {
    name: 'consumerOne'
    location: location
    privatelinkServiceId: privateLinkService.outputs.privateLinkServiceId 
    vmAdminPassword:vmAdminPassword
    vmAdminUsername:vmAdminUsername
  }
}

module consumerTwo 'module.consuming-vnet.bicep' = {
  name: 'consumerTwo'
  params: {
    name: 'consumerTwo'
    location: location
    privatelinkServiceId: privateLinkService.outputs.privateLinkServiceId 
    vmAdminPassword:vmAdminPassword
    vmAdminUsername:vmAdminUsername
  }
}
