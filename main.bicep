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

module workloadOne 'module.workload-vnet.bicep' = {
  name: 'workloadOne'
  params: {
    name: 'workloadOne'
    location: location
    privatelinkServiceId: privateLinkService.outputs.privateLinkServiceId 
    vmAdminPassword:vmAdminPassword
    vmAdminUsername:vmAdminUsername
  }
}

module workloadTwo 'module.workload-vnet.bicep' = {
  name: 'workloadTwo'
  params: {
    name: 'workloadTwo'
    location: location
    privatelinkServiceId: privateLinkService.outputs.privateLinkServiceId 
    vmAdminPassword:vmAdminPassword
    vmAdminUsername:vmAdminUsername
    useOutboundResolver: false
  }
}
