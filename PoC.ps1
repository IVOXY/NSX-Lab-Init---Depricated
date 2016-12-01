

#Connect to vCnter
#connect-viserver -Server vcenter.lab.local -User administrator@vsphere.local -Password Clab4911!

# PoC Variable Denifitions
#$VirtualMachinesLocation = "LabDemo"
#$StartingIP = .123
#$LabUsers = @("Demo-Chris","Demo-Dave")
#$vCenterServer = "vcenter2.lab.ivoxy.com"
#$vCenterUserName = "chris.crow"
#$vCenterPassword = "Go#Sand!"
#$NSXManager = "10.7.72.95"
#$NSXPassword = ConvertTo-SecureString -String "Go#Sand!" -AsPlainText -Force


$jsonpath = ".\lab.json"

#######
# Read lab config file

try
    {
    $config = Get-Content -Raw -Path $jsonpath | ConvertFrom-Json
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








#############################################################################################################################################
# Create switches																															#
#############################################################################################################################################

# Create switch list
$switchlist = @()
foreach ($_ in $config.labs) {
    $switchlist +=  $config.labname + "-" + $_.student
}




foreach ($_ in $switchlist) {
		
		# Skip any duplicate switches
		#if ($switches -contains $_) {Write-Host -BackgroundColor:Black -ForegroundColor:Red "Warning: $_ exists. Skipping."}
		
		# Build any missing switches
								
			[xml]$body = "<virtualWireCreateSpec><name>$_</name><tenantId></tenantId></virtualWireCreateSpec>"
			$r = Invoke-WebRequest -Uri "$uri/api/2.0/vdn/scopes/$nsxscopeid/virtualwires" -Body $body -Method:Post -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 30
			if ($r.StatusDescription -match "Created") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully created $_ switch."}
			else {throw "Was not able to create switch. API status description was not `"created`""}
			
		}
	
	Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Switch section completed."

#############################################################################################################################################
# Create router																																#
#############################################################################################################################################

	# Get virtualwire ID for switches
	# Note: We can't assume that this script built the switches above, so let's query the API again now that all switches exist
	$r = Invoke-WebRequest -Uri "$uri/api/2.0/vdn/virtualwires" -Headers $headers -ContentType "application/xml" -ErrorAction:Stop
	[xml]$rxml = $r.Content
	$switchvwire = @{}
	foreach ($_ in $rxml.virtualWires.dataPage.virtualWire) {
		$switchvwire.Add($_.name,$_.objectId)

		}



foreach ($_ in $config.labs) {
$wirelookup = $config.labname + "-" + $_.student
	# Start a new body for the router XML payload (bleh to XML!)
	[string]$body = "<edge>
<datacenterMoid>$($moref.datacenter)</datacenterMoid>
<name>$($config.labname)-$($_.student)-router</name>
<fqdn>$($config.labname)-$($_.student)-router</fqdn>
<tenant>$($config.edge.tenant)</tenant>
<vseLogLevel>emergency</vseLogLevel>
<vnics>
<vnic>
<label>vNic_0</label>
<name>Internal</name>
<addressGroups>
<addressGroup>
<primaryAddress>$($config.gateway)</primaryAddress>
<subnetMask>255.255.255.0</subnetMask>
</addressGroup>
</addressGroups>
<mtu>1500</mtu>
<type>internal</type>
<isConnected>true</isConnected>
<index>0</index>
<portgroupId>$($switchvwire.get_Item($wirelookup))</portgroupId>
<enableProxyArp>false</enableProxyArp>
<enableSendRedirects>false</enableSendRedirects>
</vnic>
<vnic>
<label>vNic_1</label>
<name>Uplink</name>
<addressGroups>
<addressGroup>
<primaryAddress>$($_.ip)</primaryAddress>
<subnetMask>255.255.255.192</subnetMask>
</addressGroup>
</addressGroups>
<mtu>1500</mtu>
<type>uplink</type>
<isConnected>true</isConnected>
<index>1</index>
<portgroupId>$($moref.edge_uplink)</portgroupId>
<enableProxyArp>false</enableProxyArp>
<enableSendRedirects>true</enableSendRedirects>
</vnic>
</vnics>
<appliances>
<applianceSize>compact</applianceSize>
<appliance>
<resourcePoolId>$($moref.rp)</resourcePoolId>
<datastoreId>$($moref.datastore)</datastoreId>
<vmFolderId>$($moref.folder)</vmFolderId>
</appliance>
</appliances>
<cliSettings>
<remoteAccess>TRUE</remoteAccess>
<userName>admin</userName>
<password>$($config.cli.pass)</password>
<passwordExpiry>99999</passwordExpiry>
</cliSettings>
<features>
<firewall>
<enabled>TRUE</enabled>
</firewall>
<highAvailability>
<enabled>FALSE</enabled>
</highAvailability>
</features>
<type>gatewayServices</type>
</edge>"


# Debug to force edge if actual edge build is commented out
#$edgeid = "edge-13"

	# Post the edge to the API
	# Note: At this point, no routing is configured. It appears the API wants that after the build is done and not before.
	Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Creating edge. This may take a few minutes."
	try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges" -Body $body -Method:Post -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180} catch {Failure}
	if ($r.StatusDescription -match "Created") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully created $($config.edge.name) edge."
	$edgeid = ($r.Headers.get_Item("Location")).split("/") | Select-Object -Last 1
		}
	else {
		$body
		throw "Was not able to create edge. API status description was not `"created`""
		}

######
# Add firewall Rules

[string]$body =  "
<firewall>
    <enabled>true</enabled>
    <globalConfig>
        <tcpPickOngoingConnections>false</tcpPickOngoingConnections>
        <tcpAllowOutOfWindowPackets>false</tcpAllowOutOfWindowPackets>
        <tcpSendResetForClosedVsePorts>true</tcpSendResetForClosedVsePorts>
        <dropInvalidTraffic>true</dropInvalidTraffic>
        <logInvalidTraffic>false</logInvalidTraffic>
        <tcpTimeoutOpen>30</tcpTimeoutOpen>
        <tcpTimeoutEstablished>3600</tcpTimeoutEstablished>
        <tcpTimeoutClose>30</tcpTimeoutClose>
        <udpTimeout>60</udpTimeout>
        <icmpTimeout>10</icmpTimeout>
        <icmp6Timeout>10</icmp6Timeout>
        <ipGenericTimeout>120</ipGenericTimeout>
    </globalConfig>
    <defaultPolicy>
        <action>deny</action>
        <loggingEnabled>false</loggingEnabled>
    </defaultPolicy>
	<firewallRules>
     <firewallRule>
            <name>External Access</name>
            <ruleType>user</ruleType>
            <enabled>true</enabled>
            <loggingEnabled>false</loggingEnabled>
            <description></description>
            <matchTranslated>false</matchTranslated>
            <action>accept</action>
            <source>
                <exclude>false</exclude>
                <ipAddress>192.168.2.0/24</ipAddress>
            </source>
        </firewallRule>
        <firewallRule>
            <name>RDP2</name>
            <ruleType>user</ruleType>
            <enabled>true</enabled>
            <loggingEnabled>false</loggingEnabled>
            <description></description>
            <matchTranslated>false</matchTranslated>
            <action>accept</action>
            <source>
                <exclude>false</exclude>
                <ipAddress>$($config.externalallow)</ipAddress>
            </source>
            <destination>
                <exclude>false</exclude>
                <ipAddress>$($_.ip)</ipAddress>
            </destination>
            <application>
                <applicationId>application-160</applicationId>
            </application>
        </firewallRule>
    </firewallRules>
</firewall>
"

try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$edgeid/firewall/config" -Body $body -Method:Put -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180} catch { Failure }




######
# Add NAT Rules

[string]$body =  "<nat>
    <enabled>true</enabled>
    <natRules>
        <natRule>
             <ruleType>user</ruleType>
            <action>snat</action>
            <vnic>1</vnic>
            <originalAddress>$($config.internalsubnet)</originalAddress>
            <translatedAddress>$($_.ip)</translatedAddress>
            <loggingEnabled>false</loggingEnabled>
            <enabled>true</enabled>
            <description></description>
            <protocol>any</protocol>
            <originalPort>any</originalPort>
            <translatedPort>any</translatedPort>
        </natRule>
        <natRule>
            <ruleType>user</ruleType>
            <action>dnat</action>
            <vnic>1</vnic>
            <originalAddress>$($_.ip)</originalAddress>
            <translatedAddress>$($config.internaldmz)</translatedAddress>
            <loggingEnabled>false</loggingEnabled>
            <enabled>true</enabled>
            <description></description>
            <protocol>any</protocol>
            <originalPort>any</originalPort>
            <translatedPort>any</translatedPort>
        </natRule>
    </natRules>
</nat>"

try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$edgeid/nat/config" -Body $body -Method:Put -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180} catch { Failure }


######
#Add Default Gateway

[string]$body = "<routing>
    <staticRouting>
        <defaultRoute>
            <vnic>1</vnic>
            <mtu>1500</mtu>
            <description></description>
            <gatewayAddress>$($config.externalgateway)</gatewayAddress>
            <adminDistance>1</adminDistance>
        </defaultRoute>
    </staticRouting>
</routing>"

write-host $body
try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$edgeid/routing/config" -Body $body -Method:Put -Headers $headers -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180} catch { Failure }


#End Egde loop interation
}

#############################################################################################################################################
# Create VMs																															#
#############################################################################################################################################

$ResourcePool = Get-Resourcepool -name Resources
foreach ($VM in $config.vmlist) {


    foreach ($_ in $config.labs) {
        $NetworkName = $config.labname + "-" + $_.student
        $Network = get-virtualportgroup -name *$NetworkName*
        $NewVM = $config.labname + "-" + $_.student + "-" + $VM
        $template = get-vm -name $VM
        start-sleep 10
        New-vm -name $NewVM -vm $template -ResourcePool $ResourcePool -location $config.config.folder -datastore TinTri
        start-sleep 30
        get-networkadapter -vm $NewVM | Set-networkadapter -networkname $network.name -confirm:$false
        start-sleep 10
        start-vm -VM $NewVM

    }
}














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
