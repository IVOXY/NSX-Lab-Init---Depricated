

###########################
$jsonpath = ".\lab.json"
$jsonpath2 = ".\labremove.json"

#Pull in original config
try
    {
    $config = Get-Content -Raw -Path $jsonpath | ConvertFrom-Json
	Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Parsed configuration from json file."
    }
catch {throw "I don't have a config, something went wrong."}

#Pull in new spin down config
try
    {
    $configremove = Get-Content -Raw -Path $jsonpath2 | ConvertFrom-Json
	Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Parsed configuration from json file."
    }
catch {throw "I don't have a config, something went wrong."}

#Variable definitions. This is not really needed, but for compatability with the PoC variable list
$vCenterServer = $config.config.vCenterServer
$vCenterUserName = $config.config.vCenterUsername
$vCenterPassword = $config.config.vCenterPassword
$NSXManager = $config.config.NSXManager
#$NSXPassword = ConvertTo-SecureString -String $config.config.NSXPassword -AsPlainText -Force
$NSXPassword = "Go#Sand!"





#######
# POC Test

# Plugins and version check
try
    {
    Import-Module VMware.VimAutomation.Vds -ErrorAction Stop
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "Status: PowerCLI version 6.0+ found."
    }
catch
    {
    try {Add-PSSnapin VMware.VimAutomation.Vds -ErrorAction Stop} catch {throw "You are missing the VMware.VimAutomation.Vds snapin"}
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "Status: PowerCLI prior to version 6.0 found."
    }

Connect-VIServer -server $vCenterServer -user $vCenterUsername -password $vCenterPassword
$moref = @{}
$moref.Add("datacenter",(Get-Datacenter $config.config.datacenter | Get-View).MoRef.Value)
$moref.Add("cluster",(Get-Cluster $config.config.cluster | Get-View).MoRef.Value)
$moref.Add("rp",(Get-ResourcePool -Location (Get-Cluster $config.config.cluster) -Name "Resources" | Get-View).MoRef.Value)
$moref.Add("datastore",(Get-Datastore -Location (Get-Datacenter $config.config.datacenter) $config.config.datastore | Get-View).MoRef.Value)
$moref.Add("folder",(Get-Folder -name $config.config.folder | Get-View).MoRef.Value)
$moref.Add("edge_uplink",(Get-VDPortgroup $config.config.publicdvpg | Get-View).MoRef.Value)
#$moref.Add("edge_mgmt",(Get-VDPortgroup $config.edge.management.iface | Get-View).MoRef.Value)
#$moref.Add("router_mgmt",(Get-VDPortgroup $config.router.management.iface | Get-View).MoRef.Value)
	if ($moref) {
		Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Gathered MoRef IDs from $vcenter."
		Disconnect-VIServer -Confirm:$false
		}
	else {throw "I don't have any MoRefs, something went wrong."}



# Create authentication header with base64 encoding
$EncodedAuthorization = [System.Text.Encoding]::UTF8.GetBytes("admin" + ':' + "Go#Sand!")
$EncodedPassword = [System.Convert]::ToBase64String($EncodedAuthorization)

# Construct headers with authentication data + expected Accept header (xml / json)
$headers = @{"Authorization" = "Basic $EncodedPassword"}


# Build NSX base URI
$uri = "https://$NSXManager"


# Allow untrusted SSL certs
	add-type @"
	    using System.Net;
	    using System.Security.Cryptography.X509Certificates;
	    public class TrustAllCertsPolicy : ICertificatePolicy {
	        public bool CheckValidationResult(
	            ServicePoint srvPoint, X509Certificate certificate,
	            WebRequest request, int certificateProblem) {
	            return true;
	        }
	    }
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy



#######
# Get the network scope (transport zone)
# Note: I'm assuming your TZ is attached to the correct clusters
$r = Invoke-WebRequest -Uri "$uri/api/2.0/vdn/scopes" -Headers $headers -ContentType "application/xml" -ErrorAction:Stop
[xml]$rxml = $r.Content
	if (-not $rxml.vdnScopes.vdnScope.objectId) {throw "No network scope found. Create a transport zone and attach to your cluster."}
	$nsxscopeid = $rxml.vdnScopes.vdnScope.objectId


####### Remove Edge Routers

foreach ($_ in $configremove.edgerouters) {


    [string]$body =  ""

    try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$_" -Body $body -Method:delete -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180} catch { Failure }


}


####### Remove Logical Switches
## Not done, and I don't know how to do this


####### Remove VMs
get-vm -name *$($configremove.vmstring)* -location $($config.config.folder) | Stop-VM -Confirm:$false
start-sleep 5
get-vm -name *$($configremove.vmstring)* -location $($config.config.folder) | Remove-VM -DeletePermanently:$true -Confirm:$false 
start-sleep 5



function Failure {
	$global:helpme = $body
	$global:helpmoref = $moref
	$global:result = $_.Exception.Response.GetResponseStream()
	$global:reader = New-Object System.IO.StreamReader($global:result)
	$global:responseBody = $global:reader.ReadToEnd();
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Status: A system exception was caught."
	Write-Host -BackgroundColor:Black -ForegroundColor:Red $global:responsebody
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "The request body has been saved to `$global:helpme"
	break
}
