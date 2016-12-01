add-pssnapin VMware.VimAutomation.Core

#Connect to vCnter
connect-viserver -Server vcenter.lab.local -User administrator@vsphere.local -Password Clab4911!

#Read the labs
$LabList = get-childitem .\labs

foreach ($lab in $LabList) {
    Write-host $LabList.IndexOf($lab),")", $lab.Name

}
$input = Read-Host "Please make selection:"


# || die operation goes here
#if ($input -gt $LabList.length) 

foreach ($VMTemplateName in get-content -path $LabList[$input].fullname) {
    $ResourcePool = Get-Resourcepool -name Resources
    $Template =  get-template -name $VMTemplateName
    #new-vm -name Testvm01 -template $template -ResourcePool $ResourcePool
    foreach ($LabNetwork in get-content -path .\LabNetworks.txt) {
        $Network = get-virtualportgroup -name *$LabNetwork*
        New-vm -name $LabNetwork-$VMTemplateName -template $template -ResourcePool $ResourcePool
        get-networkadapter -vm $LabNetwork-$VMTemplateName | Set-networkadapter -networkname $network.name -confirm:$false
        start-vm -VM $LabNetwork-$VMTemplateName


    }
}

