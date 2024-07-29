# DNS via Resolver and Private Link

This sets up three vnets, with no peering between them.

1. The DNS server provider vnet:
    This vnet contains a single VM that hosts a CoreDNS server that forwards DNS requests to Google (`8.8.8.8`).
2. The `workloadOne` vnet contains a vnet that is configured to use AzureDNS by default and 
   the following attached forwarding rules:
    * `.` to blackhole (forward everything by default to a non-routable IP address)
    * `slashdot.org` to the private link endpoint linked, via a load balancer, to the CoreDNS VM.
    
    These rules effectively deny resolution of any DNS names that isn't `slashdot.org`. On the  `workloadOne` demo VM  other DNS requests will timeout. There seems to be an exception for Microsoft hosted DNS names. e.g. `microsoft.com` and `intenral.cloudapp.net` will continue to resolve. 
3. The `workloadTwo` vnet contains a vnet that is configured, via DHCP options to default to using the private link endpoint directly, with no azure outbound resolver or attached rulesets. By default it will only block requests for `google.com`, however it doesn't stop things like `dig @168.63.129.16 google.com` from working though. In order to do that you will need to attach a NSG that denies the `AzurePlatformDNS` tag (as mentioned https://github.com/MicrosoftDocs/azure-docs/issues/61213).



