#Requires -Version 4.0

<#  
.SYNOPSIS  Creates a virtual network tier for VMware NSX
.DESCRIPTION Creates a virtual network tier for VMware NSX
.NOTES  Author:  Chris Wahl, @ChrisWahl, WahlNetwork.com
.PARAMETER NSX
	NSX Manager IP or FQDN
.PARAMETER NSXPassword
	NSX Manager credentials with administrative authority
.PARAMETER NSXUsername
	NSX Manager username with administrative authority
.PARAMETER JSONPath
	Path to your JSON configuration file
.PARAMETER vCenter
	vCenter Server IP or FQDN
.PARAMETER NoAskCreds
	Use your current login credentials for vCenter
.EXAMPLE
	PS> Create-NSXTier -NSX nsxmgr.tld -vCenter vcenter.tld -JSONPath "c:\path\prod.json"
#>

[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true,Position=0,HelpMessage="NSX Manager IP or FQDN")]
	[ValidateNotNullorEmpty()]
	[String]$NSX,
	[Parameter(Mandatory=$true,Position=1,HelpMessage="NSX Manager credentials with administrative authority")]
	[ValidateNotNullorEmpty()]
	[System.Security.SecureString]$NSXPassword,
	[Parameter(Mandatory=$true,Position=2,HelpMessage="Path to your JSON configuration file")]
	[ValidateNotNullorEmpty()]
	[String]$JSONPath,
	[Parameter(Mandatory=$true,Position=3,HelpMessage="vCenter Server IP or FQDN")]
	[ValidateNotNullorEmpty()]
	[String]$vCenter,
	[String]$NSXUsername = "admin",
	[Parameter(HelpMessage="Use your current login credentials for vCenter")]
	[Switch]$NoAskCreds
	)


# Time this puppy!
$startclock = (Get-Date)

# Create NSX authorization string and store in $head
$nsxcreds = New-Object System.Management.Automation.PSCredential "admin",$NSXPassword
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSXUsername+":"+$($nsxcreds.GetNetworkCredential().password)))
$head = @{"Authorization"="Basic $auth"}
$uri = "https://$nsx"



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


