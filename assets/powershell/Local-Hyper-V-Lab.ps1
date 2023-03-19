<#
##################################################################################
# Create und configure all VMs of a  Test Enviroment                             #
# R4.5                                                                           #
# build with parts from Microsoft                                                #
# https://github.com/Microsoft/Virtualization-Documentation                      #
# 2 AD Controllers, DHCP Server,                                                 #
# 3 Node SOFS Cluster (Storage Space Direct), 3 node hyper-V cluser NanoServer   #
#                                                                                #
# Requirements:                                                                  #
# Windows 2016 ISO + evealution key                                              #
# Windows 10 or Windows 2016 with Hyper-V                                        #
# 24 GB RAM                                                                      #
#                                                                                #
# H. Eichmeyer               09.05.2017                                          #
##################################################################################
#>

$ISO = "C:\ISOs\en_windows_10_updated_nov_2020_x64_dvd_a8a592901.iso"
$WorkingPath = "c:\Hyper-V"

$buildsecad = $true # Build second AD controller (incl. DHCP/DNS) 

$builds2dcluster = $true  # S2D Cluster
$s2dclusterhyperv = $true  # enable Hyper-V on S2D cluster 
$buildVMs = $false    # Build Demo VMs on cluster (s2d)
$redirectedfolder = $true  # Redirect profile folders to S2D Cluster

$buildnano = $false  #Build Hyper-V Cluster (nano server)
$buildNanoVMs = $false    # Build Demo VMs inside Hyper-V Nano cluster

$builddocker = $false  # Build Docker test VM (upgrade needed; not yet ready)
$buildtestvm1 = $true  # empty (AD Joind) server
$buildtestvm2 = $false # empty (AD Joind) server
$buildtestvm3 = $false # empty (AD Joind) server

### Hyper-V / VM parameters
$BaseVHDs = "$($workingPath)\BaseVHDs"
$VMPath = "$($workingPath)\VMs"
$TempPath = "$($workingPath)\temp"
$virtualSwitchName = "TestNetNAT"
$virtualSwitchNAT = $false      # enable NAT von vSwitch for internet access
$virtualSwitchDNS = "8.8.8.8"  # DNS on phy. network
$subnet = "10.10.10."   
$VMRAM = 2GB  # RAM per VM
$ClsuterVMRAM = 4GB  # Cluster VM Memmory 9GB

### AD parameters
$ADName = "test.lab"
$ADAdminPassword = "Test1234"

### Sysprep parameters
$Organization = "Test Lap"
$Owner = "All Testers"
$Timezone = "W. Europe Standard Time"
$LocalAdminPassword = "Test1234"
$WindowsKey = "xxxxx-xxxxx-xxxxx-xxxxx-xxxxx"  # enter 2016 eval key

### create credationals
$localCred = new-object -typename System.Management.Automation.PSCredential `
             -argumentlist "Administrator", (ConvertTo-SecureString $LocalAdminPassword -AsPlainText -Force)
$domainCred = new-object -typename System.Management.Automation.PSCredential `
              -argumentlist "$($ADName)\Administrator", (ConvertTo-SecureString $ADAdminPassword -AsPlainText -Force)


### Sysprep unattend XML
$unattendSource = [xml]@"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <servicing></servicing>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>*</ComputerName>
            <ProductKey>Key</ProductKey> 
            <RegisteredOrganization>Organization</RegisteredOrganization>
            <RegisteredOwner>Owner</RegisteredOwner>
            <TimeZone>TZ</TimeZone>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>password</Value>
                    <PlainText>True</PlainText>
                </AdministratorPassword>
            </UserAccounts>
        </component>
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>en-us</InputLocale>
            <SystemLocale>en-us</SystemLocale>
            <UILanguage>en-us</UILanguage>
            <UILanguageFallback>en-us</UILanguageFallback>
            <UserLocale>en-us</UserLocale>
        </component>
    </settings>
</unattend>
"@
# Run us admin
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Running elevated..."
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

function deleteFile
{
    param
    (  [string] $file
    )
    
    if (Test-Path $file) 
    {  Remove-Item $file -Recurse > $null;
    }
}

function GetUnattendChunk 
{
    param
    (
        [string] $pass, 
        [string] $component, 
        [xml] $unattend
    ); 
    
    # Helper function that returns one component chunk from the Unattend XML data structure
    return $Unattend.unattend.settings | ? pass -eq $pass `
        | select -ExpandProperty component `
        | ? name -eq $component;
}

function makeUnattendFile 
{
    param
    (
        [string] $filePath
    ); 

    # Composes unattend file and writes it to the specified filepath
     
    # Reload template - clone is necessary as PowerShell thinks this is a "complex" object
    $unattend = $unattendSource.Clone();
     
    # Customize unattend XML
    GetUnattendChunk "specialize" "Microsoft-Windows-Shell-Setup" $unattend | %{$_.RegisteredOrganization = $Organization};
    GetUnattendChunk "specialize" "Microsoft-Windows-Shell-Setup" $unattend | %{$_.RegisteredOwner = $Owner};
    GetUnattendChunk "specialize" "Microsoft-Windows-Shell-Setup" $unattend | %{$_.TimeZone = $Timezone};
    GetUnattendChunk "oobeSystem" "Microsoft-Windows-Shell-Setup" $unattend | %{$_.UserAccounts.AdministratorPassword.Value = $LocalAdminPassword};
    GetUnattendChunk "specialize" "Microsoft-Windows-Shell-Setup" $unattend | %{$_.ProductKey = $WindowsKey};

    # Write it out to disk
    deleteFile $filePath; $Unattend.Save($filePath);
}


function Logger {
    param
    (
        [string]$systemName,
        [string]$message,
        [string]$iserror
    );

    # Function for displaying formatted log messages.  Also displays time in minutes since the script was started
    write-host (Get-Date).ToShortTimeString() -ForegroundColor Cyan -NoNewline;
    write-host " - [" -ForegroundColor White -NoNewline;
    if ($iserror -eq "error") {write-host $systemName -ForegroundColor Red -NoNewline;}
    if ($iserror -eq "ok") {write-host $systemName -ForegroundColor Green -NoNewline;}
    if ($iserror -eq "") {write-host $systemName -ForegroundColor Yellow -NoNewline;}
    write-Host "]::$($message)" -ForegroundColor White;
}

function waitForPSDirect([string]$VMName, $cred)
{# Check if a VM is up and running by test PS Direct logon
   logger $VMName "Waiting for PowerShell Direct (using $($cred.username))"
    while ((icm -VMName $VMName -Credential $cred {"Test"} -ea SilentlyContinue) -ne "Test") {Sleep -Seconds 1}
   logger $VMName "PowerShell Direct up" "OK"
   }

function rebootVM([string]$VMName)
{# Stop and Start a VM
    logger $VMName "Rebooting"; stop-vm $VMName; start-vm $VMName
    }

Function Remove-NatSwitch (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Name
    )
{
    Remove-NetNat $Name -Confirm:$false
    $ifindex = (Get-NetAdapter | where {$_.Name -match $Name}).ifIndex
    Remove-NetIPAddress -InterfaceIndex $ifindex -Confirm:$false
    Remove-VMSwitch -Name $Name -Force:$true -Confirm:$false
}

# Remove-NatSwitch -Name $virtualSwitchName

Function New-NatSwitch (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Name,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$InternalIPInterfaceAddressPrefix,

    [Int]$PrefixLength,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$GatewayIP, 

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()] [Boolean]$virtualSwitchNAT
    )
{
 New-VMSwitch -Name $Name -SwitchType Internal
    if ($virtualSwitchNAT) {
    $ifindex = (Get-NetAdapter | where {$_.Name -match $Name}).ifIndex
    New-NetIPAddress -IPAddress $GatewayIP -PrefixLength $PrefixLength -InterfaceIndex $ifindex
    New-NetNat -Name $Name -InternalIPInterfaceAddressPrefix "$InternalIPInterfaceAddressPrefix/$PrefixLength"
    logger $Name "Add NAT"
    }
}


Function CheckSwitch {
param
    (
       [string]$virtualSwitchName,
       [Boolean]$virtualSwitchNAT
    );

Logger "$($virtualSwitchName)" "Create Switch"
# Check is Hyper-V switch is configured / create if needed
if ((Get-VMSwitch | ? name -eq $($virtualSwitchName)) -eq $null)
{
Logger "$($virtualSwitchName)" "Create Switch"
#New-VMSwitch -Name $virtualSwitchName -SwitchType Private
New-NatSwitch -Name $($virtualSwitchName) -InternalIPInterfaceAddressPrefix "$($subnet)0" -PrefixLength 24 -GatewayIP "$($subnet)254" -virtualSwitchNAT $virtualSwitchNAT
}
else { Logger "Swicht" "Switch already exists" "OK"
}
}

function copyTextFileIntoVM([string]$VMName, $Credential, [string]$sourceFilePath, [string]$destinationFilePath)
{ 
    $content = Get-Content $sourceFilePath 
    Invoke-Command -VMName $VMName  -Credential $cred {param($Script, $file) 
          $script | set-content $file} 
          -ArgumentList (,$content), $destinationFilePath
   } 


Function BuildBaseImages {

   Mount-DiskImage $ISO
   $DVDDriveLetter = (Get-DiskImage $ISO | Get-Volume).DriveLetter
   Copy-Item "$($DVDDriveLetter):\NanoServer\NanoServerImageGenerator\Convert-WindowsImage.ps1" "$($TempPath)\Convert-WindowsImage.ps1" -Force
   Import-Module "$($DVDDriveLetter):\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1" -Force

   makeUnattendFile "$($TempPath)\unattend.xml"
   . "$TempPath\Convert-WindowsImage.ps1"
   
   if($buildnano) {
    if (!(Test-Path "$($BaseVHDs)\NanoBaseHV.vhdx")) 
    {
    New-NanoServerImage -MediaPath "$($DVDDriveLetter):\" -BasePath $BaseVHDs -TargetPath "$($BaseVHDs)\NanoBaseHV.vhdx" -DeploymentType Guest -Edition Standard  -Compute -Clustering -AdministratorPassword (ConvertTo-SecureString $LocalAdminPassword -AsPlainText -Force)
    Logger "BaseImages" "NanoBaseHV.vhdx"
    } else {Logger "BaseImages" "NanoBaseHV.vhdx already exists" "OK"}
    }

    if (!(Test-Path "$($BaseVHDs)\VMServerBaseCore.vhdx")) 
    { Logger "BaseImages" "Erstelle: $($BaseVHDs)\VMServerBaseCore.vhdx"
        Convert-WindowsImage -SourcePath "$($DVDDriveLetter):\sources\install.wim" -VHDPath "$($BaseVHDs)\VMServerBaseCore.vhdx" `
                     -SizeBytes 40GB -VHDFormat VHDX -UnattendPath "$($TempPath)\unattend.xml" `
                     -Edition "ServerDataCenterCore" -DiskLayout UEFI 
        Logger "BaseImages" "VMServerBaseCore.vhdx"
    } else {Logger "BaseImages" "VMServerBaseCore.vhdx already exists" "OK"}

   if (!(Test-Path "$($BaseVHDs)\VMServerBase.vhdx")) 
   {
       Convert-WindowsImage -SourcePath "$($DVDDriveLetter):\sources\install.wim" -VHDPath "$($BaseVHDs)\VMServerBase.vhdx" `
                    -SizeBytes 40GB -VHDFormat VHDX -UnattendPath "$($TempPath)\unattend.xml" `
                    -Edition "ServerDataCenter" -DiskLayout UEFI
       Logger "BaseImages" "VMServerBase.vhdx" 
   } else {Logger "BaseImages" "VMServerBase.vhdx already exists" "OK"}

    DeleteFile "$($TempPath)\unattend.xml"
 #   DeleteFile "$workingPath\Convert-WindowsImage.ps1"
    Dismount-DiskImage $ISO 
}

function CreateFolder {

    param
    (
        [string] $Folder
    ); 

    
    if (!(Test-Path "$Folder")) 
    { Logger "Folder" "Create: $Folder"
      MD $Folder
    }

}

function CreateVM {

    param
    (
        [string] $VMName, 
        [string] $GuestOSName, 
        [switch] $CoreServer,
        [switch] $FullServer,
        [switch] $NanoServerHV
    ); 

   logger $VMName "Removing old VM"
   get-vm $VMName -ErrorAction SilentlyContinue | stop-vm -TurnOff -Force -Passthru | remove-vm -Force
   deleteFile "$($VMPath)\$($GuestOSName).vhdx"
#   pause
   $selecttyp = 0
   if ($CoreServer) {$selecttyp = 0}
   if ($FullServer) {$selecttyp = 1}
   if ($NanoServerHV) {$selecttyp = 2}

   switch ($selecttyp) 
   {
     0 { logger $VMName "Creating new differencing disk from VMServerBaseCore.vhdx"
         New-VHD -Path "$($VMPath)\$($GuestOSName).vhdx" -ParentPath "$($BaseVHDs)\VMServerBaseCore.vhdx" -Differencing | Out-Null
         
         logger $VMName "Creating virtual machine"
         new-vm -Name $VMName -MemoryStartupBytes 1GB -SwitchName $VirtualSwitchName -VHDPath "$($VMPath)\$($GuestOSName).vhdx" -Generation 2
         Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $True -MaximumBytes $VMRAM -MinimumBytes 756MB -StartupBytes 1GB
         Set-VMProcessor -VMName $VMName -Count 4
       }
    1 { logger $VMName "Creating new differencing disk from VMServerBase.vhdx"
        New-VHD -Path "$($VMPath)\$($GuestOSName).vhdx" -ParentPath "$($BaseVHDs)\VMServerBase.vhdx" -Differencing | Out-Null
        
        logger $VMName "Creating virtual machine"
        new-vm -Name $VMName -MemoryStartupBytes 1GB -SwitchName $VirtualSwitchName -VHDPath "$($VMPath)\$($GuestOSName).vhdx" -Generation 2
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $True -MaximumBytes $VMRAM -MinimumBytes 756MB -StartupBytes 1GB
        Set-VMProcessor -VMName $VMName -Count 4
       }
    2 { logger $VMName "New disk from NanoBaseHV.vhdx"
        copy "$($BaseVHDs)\NanoBaseHV.vhdx" "$($VMPath)\$($GuestOSName).vhdx"
        
        logger $VMName "Creating virtual machine"
        new-vm -Name $VMName -MemoryStartupBytes 4096MB -SwitchName $VirtualSwitchName -VHDPath "$($VMPath)\$($GuestOSName).vhdx" -Generation 2  #4GB to run VMs inside a nested HyperV VM
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
        Set-VMProcessor -VMName $VMName -Count 4 -ExposeVirtualizationExtensions $true   # enable nested
        Add-VMNetworkAdapter -VMName $VMName -SwitchName $VirtualSwitchName
        Get-VMNetworkAdapter -VMName $VMName | Set-VMNetworkAdapter -MacAddressSpoofing on
       }

     }
      
   logger $VMName "Starting virtual machine"
    get-vm -VMName $VMName | Set-VM -AutomaticCheckpointsEnabled $false 
   start-vm $VMName
   }

function ConfigureVM {
    param
    (   [string] $VMName, 
        [string] $GuestOSName, 
        [string] $IPNumber = "0"
    ); 

   waitForPSDirect $VMName -cred $localCred
  logger $VMName "Set IP address & name, WSMAN Trusted hosts"
   # Set IP address & name
   Invoke-Command -VMName $VMName -Credential $localCred {
      param($IPNumber, $GuestOSName,  $VMName, $ADName, $subnet)
      if ($IPNumber -ne "0") {
         Write-Output "[$($VMName)]:: Setting IP Address to $($subnet)$($IPNumber)"
         New-NetIPAddress -IPAddress "$($subnet)$($IPNumber)" -InterfaceAlias "Ethernet" -PrefixLength 24 -DefaultGateway "$($subnet)254" | Out-Null
         Write-Output "[$($VMName)]:: Setting DNS Address"
         Get-DnsClientServerAddress | %{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses "$($subnet)1"}}
      Write-Output "[$($VMName)]:: Renaming OS to `"$($GuestOSName)`""
      Rename-Computer $GuestOSName
      Write-Output "[$($VMName)]:: Configuring WSMAN Trusted hosts"
      Set-Item WSMan:\localhost\Client\TrustedHosts "*.$($ADName)" -Force
      Set-Item WSMan:\localhost\client\trustedhosts "$($subnet)*" -force -concatenate
      Enable-WSManCredSSP -Role Client -DelegateComputer "*.$($ADName)" -Force
      del c:\unattend.xml
      } -ArgumentList $IPNumber, $GuestOSName, $VMName, $ADName, $subnet

      # Reboot
      rebootVM $VMName; waitForPSDirect $VMName -cred $localCred
}

function ADJoinVM {
    param
    (    $VMName, 
         $domainName, 
         $domainCred,
         $localCred
    ); 


logger $vmName "AD Join $ADname"
 waitForPSDirect $VMName -cred $localCred
  
      Invoke-Command -VMName $VMName -Credential $localCred {
       param($VMName, $domainCred, $domainName)
         Write-Output "[$($VMName)]:: Joining domain as `"$($env:computername)`""
         while (!(Test-Connection -Computername $domainName -BufferSize 16 -Count 1 -Quiet -ea SilentlyContinue)) {sleep -seconds 1}
         do {Add-Computer -DomainName $domainName -Credential $domainCred -ea SilentlyContinue} until ($?)
          } -ArgumentList $VMName, $domainCred, $ADName
rebootVM $VMName
    }


###########
### MAIN
###########


logger "RUN" "start over?" "ERROR"
pause
Logger "BaseImages" "Start script"
CreateFolder $BaseVHDs
CreateFolder $VMPath
CreateFolder $TempPath
# Buil images
if(Test-Path $ISO) {
Logger "BaseImages" "End script"
BuildBaseImages
     }
else {
Logger "ISO" "ISO not found"
exit
}


#Build Switch
Logger "$($virtualSwitchName)" "Check Switch"
CheckSwitch $($virtualSwitchName) $virtualSwitchNAT

# Build VMs
Logger "CreateVM" "Create all VMs"
CreateVM "Domain Controller 1" "DC1" -CoreServer
if($buildsecad) {
CreateVM "Domain Controller 2" "DC2" -CoreServer
}
CreateVM "Management Console" "Management" -FullServer
if($builds2dcluster) {
CreateVM "Cluster Node 1" "cn1" -CoreServer
CreateVM "Cluster Node 2" "cn2" -CoreServer
CreateVM "Cluster Node 3" "cn3" -CoreServer
}
if($buildnano) {
CreateVM "Hyper-V Node 1" "HVNode1" -NanoServerHV
CreateVM "Hyper-V Node 2" "HVNode2" -NanoServerHV
}
if($builddocker) {
CreateVM "Container 1" "Con1" -NanoServerHV
}


#### Configure DC1
$vmName = "Domain Controller 1"
$GuestOSName = "DC1"
$IPNumber = "1"
    
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName $IPNumber

logger $vmName "Installing AD and promoting to domain controller"
      Invoke-Command -VMName $VMName -Credential $localCred {
         param($VMName, $ADName, $ADAdminPassword)
         Write-Output "[$($VMName)]:: Installing DHCP"
         Install-WindowsFeature DHCP -IncludeManagementTools | out-null
         Write-Output "[$($VMName)]:: Installing AD"
         Install-WindowsFeature AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools # | out-null  #-IncludeAllSubFeature 
         Write-Output "[$($VMName)]:: Enabling Active Directory and promoting to domain controller"
         Install-ADDSForest -DomainName $ADName -InstallDNS -NoDNSonNetwork -NoRebootOnCompletion -SafeModeAdministratorPassword (ConvertTo-SecureString $ADAdminPassword -AsPlainText -Force) -confirm:$false
                                 } -ArgumentList $VMName, $ADName, $ADAdminPassword
      # Reboot
      rebootVM $VMName; 
 waitForPSDirect $VMName -cred $domainCred
# Add User admin
logger $vmName "Add User HarWee & User"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $password)

         Write-Output "[$($VMName)]:: Creating user account for HarWee"
         do {start-sleep 5; New-ADUser `
            -Name "HarWee" `
            -SamAccountName  "HarWee" `
            -DisplayName "HarWee" `
            -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
            -ChangePasswordAtLogon $false  `
            -Enabled $true -ea 0} until ($?)   # this takes a while!
            Add-ADGroupMember "Domain Admins" "HarWee"
            
            do {start-sleep 5; New-ADUser `
            -Name "User" `
            -SamAccountName  "User" `
            -DisplayName "User" `
            -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
            -ChangePasswordAtLogon $false  `
            -Enabled $true -ea 0} until ($?)   # this takes a while!
            
            } -ArgumentList $VMName, $ADAdminPassword
            
# Install Certification Authority
logger $vmName "Install Certification Authority"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName)

         Write-Output "[$($VMName)]:: Install Certification Authority"
          Install-WindowsFeature  "ADCS-Cert-Authority" -IncludeManagementTools
          Write-Output "[$($VMName)]:: Configure Certification Authority"
          Install-AdcsCertificationAuthority -CAType EnterpriseRootCa -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -KeyLength 2048 -HashAlgorithmName SHA1 -ValidityPeriod Years -ValidityPeriodUnits 3 -confirm:$false

          } -ArgumentList $VMName
          
# Set GPOs
logger $vmName "Set GPOs"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName)
                  Write-Output "[$($VMName)]:: Set GPOs"
         new-gpo -name TestGPO | new-gplink -target "dc=test,dc=lab"
         Set-GPRegistryValue -Name "TestGPO" -key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" -ValueName ScreenSaveTimeOut -Type String -value 900
              } -ArgumentList $VMName

if($redirectedfolder) {
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName)
                  Write-Output "[$($VMName)]:: Set GPOs"
         new-gpo -name TestGPO | new-gplink -target "dc=test,dc=lab"
         Set-GPRegistryValue -Name "TestGPO" -key "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ValueName "Personal" -Type ExpandString -value "\\sofileserver\RedirectedFolders\administrator\My Documents"
         Set-GPRegistryValue -Name "TestGPO" -key "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ValueName "My Music" -Type ExpandString -value "\\sofileserver\RedirectedFolders\administrator\My Documents\My Music"
         Set-GPRegistryValue -Name "TestGPO" -key "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ValueName "My Video" -Type ExpandString -value "\\sofileserver\RedirectedFolders\administrator\My Documents\My Video"
         Set-GPRegistryValue -Name "TestGPO" -key "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ValueName "My Pictures" -Type ExpandString -value "\\sofileserver\RedirectedFolders\administrator\My Documents\My Pictures"
                  } -ArgumentList $VMName
     }

logger $vmName "Set DNS forwarder"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $IP)
         Write-Output "[$($VMName)]:: Set DNS forwarder $IP"
         Add-DnsServerForwarder -IPAddress $IP -PassThru
                  } -ArgumentList $VMName, $virtualSwitchDNS


logger $vmName "Configure DHCP server and create scope"
      Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $domainName, $subnet, $IPNumber)

         Write-Output "[$($VMName)]:: Waiting for name resolution"

         while ((Test-NetConnection -ComputerName $domainName).PingSucceeded -eq $false) {Start-Sleep 1}

         Write-Output "[$($VMName)]:: Configuring DHCP Server"    
         Set-DhcpServerv4Binding -BindingState $true -InterfaceAlias Ethernet
         Add-DhcpServerv4Scope -Name "IPv4 Network" -StartRange "$($subnet)10" -EndRange "$($subnet)200" -SubnetMask 255.255.255.0
         Set-DhcpServerv4OptionValue -OptionId 6 -value "$($subnet)1"
         Set-DhcpServerV4OptionValue -Router "$($subnet)254"
         Add-DhcpServerInDC -DnsName "$($env:computername).$($domainName)"
         } -ArgumentList $VMName, $ADName, $subnet, $IPNumber

      # Reboot  
    #  rebootVM $VMName

if($buildsecad) {
      
##### Add DC02
$vmName = "Domain Controller 2"
$GuestOSName = "DC2"
$IPNumber = "2"
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName $IPNumber

      icm -VMName $VMName -Credential $localCred {
         param($VMName, $domainCred, $domainName)
          Write-Output "[$($VMName)]:: Installing DHCP"
         Install-WindowsFeature DHCP -IncludeManagementTools | out-null
         Write-Output "[$($VMName)]:: Installing AD"
         Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature | out-null
         Write-Output "[$($VMName)]:: Joining domain as `"$($env:computername)`""
         while (!(Test-Connection -Computername $domainName -BufferSize 16 -Count 1 -Quiet -ea SilentlyContinue)) {sleep -seconds 1}
         do {Add-Computer -DomainName $domainName -Credential $domainCred -ea SilentlyContinue} until ($?)
         } -ArgumentList $VMName, $domainCred, $ADName

               # Reboot
      rebootVM $VMName; waitForPSDirect $VMName -cred $domainCred

      icm -VMName $VMName -Credential $domainCred {
         param($VMName, $domainName, $domainAdminPassword)

         Write-Output "[$($VMName)]:: Waiting for name resolution"

         while ((Test-NetConnection -ComputerName $domainName).PingSucceeded -eq $false) {Start-Sleep 1}

         Write-Output "[$($VMName)]:: Enabling Active Directory and promoting to domain controller"
    
         Install-ADDSDomainController -DomainName $domainName -InstallDNS -NoRebootOnCompletion `
                                     -SafeModeAdministratorPassword (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force) -confirm:$false 
 
                            } -ArgumentList $VMName, $ADName, $ADAdminPassword

logger $vmName "Set DNS forwarder"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $IP)
         Write-Output "[$($VMName)]:: Set DNS forwarder $IP"
         Add-DnsServerForwarder -IPAddress $IP -PassThru
                  } -ArgumentList $VMName, $virtualSwitchDNS


logger $vmName "Set DHCP fail over"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $domainName, $subnet)
         Write-Output "[$($VMName)]:: Set DHCP fail over"
         Add-DhcpServerInDC -DnsName "$($env:computername).$($domainName)"
         Add-DhcpServerv4Failover -ComputerName dc1 -Name SFO-SIN-Failover -PartnerServer dc2 -ScopeId "$($subnet)0" -SharedSecret "sEcReT" -confirm:$false -ServerRole Active -AutoStateTransition $True -Force 
                  } -ArgumentList $VMName, $ADname, $subnet


logger $vmName "Add second DNS to DHCP"
Invoke-Command -VMName $VMName -Credential $domainCred {
         param($VMName, $domainName, $subnet)
         Write-Output "[$($VMName)]:: Set DNS in DHCP"
         
         Set-DhcpServerv4OptionValue -ScopeId "$($subnet)0" -OptionID 6 -Value 10.10.10.1, 10.10.10.2
                  } -ArgumentList $VMName, $ADname, $subnet
}

##### Configure Mangement Host    
$vmName = "Management Console"
$GuestOSName = "Management"

logger $vmName "start configuration"

ConfigureVM $vmName $GuestOSName

logger $vmName "Install Roles and Join"
      Invoke-Command -VMName $VMName -Credential $localCred {
         param($VMName, $domainCred, $ADName)
         Write-Output "[$($VMName)]:: Installing RSAT"
         Install-WindowsFeature RSAT-Clustering, RSAT-Hyper-V-Tools, RSAT-ADDS-Tools, RSAT-DNS-Server, RSAT-DHCP, RSAT-ADCS, GPMC  | out-null
        } -ArgumentList $VMName, $domainCred, $ADName
      # Reboot
ADJoinVM $vmName $ADName $domainCred $localCred

if ((Get-VMSwitch | ? name -eq "Intern") -eq $null)
{
New-VMSwitch -Name "Intern" -SwitchType Internal
}

# -------------------------------------- S2D Cluster
if ($builds2dcluster)
{
for($i=1; $i -le 3; $i++){
$vmName = "Cluster Node $i"
$GuestOSName = "cn$i"
logger $vmName "change VM configuration"
Stop-vm $vmName
sleep -seconds 20
  Add-VMNetworkAdapter -VMName $VMName -SwitchName $VirtualSwitchName
  Add-VMNetworkAdapter -VMName $VMName -SwitchName $VirtualSwitchName
  Add-VMNetworkAdapter -VMName $VMName -SwitchName $VirtualSwitchName
if ($s2dclusterhyperv) {
  Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $ClsuterVMRAM
  Set-VMProcessor -VMName $VMName -Count 4 -ExposeVirtualizationExtensions $true   # enable nested
  Get-VMNetworkAdapter -VMName $VMName | Set-VMNetworkAdapter -MacAddressSpoofing on
  }
logger $vmName "create VHDs for S2D"
deleteFile "$($VMPath)\$($GuestOSName) - Data 1.vhdx"
   deleteFile "$($VMPath)\$($GuestOSName) - Data 2.vhdx"
   deleteFile "$($VMPath)\$($GuestOSName) - Data 3.vhdx"
      deleteFile "$($VMPath)\$($GuestOSName) - Data 4.vhdx"
   new-vhd -Path "$($VMPath)\$($GuestOSName) - Data 1.vhdx" -Dynamic -SizeBytes 500GB
   Add-VMHardDiskDrive -VMName $VMName -Path "$($VMPath)\$($GuestOSName) - Data 1.vhdx"
   new-vhd -Path "$($VMPath)\$($GuestOSName) - Data 2.vhdx" -Dynamic -SizeBytes 500GB
   Add-VMHardDiskDrive -VMName $VMName -Path "$($VMPath)\$($GuestOSName) - Data 2.vhdx"
   new-vhd -Path "$($VMPath)\$($GuestOSName) - Data 3.vhdx" -Dynamic -SizeBytes 500GB
   Add-VMHardDiskDrive -VMName $VMName -Path "$($VMPath)\$($GuestOSName) - Data 3.vhdx"
   new-vhd -Path "$($VMPath)\$($GuestOSName) - Data 4.vhdx" -Dynamic -SizeBytes 500GB
   Add-VMHardDiskDrive -VMName $VMName -Path "$($VMPath)\$($GuestOSName) - Data 4.vhdx"
          start-vm $vmName

logger $vmName "start OS configuration + HV,FS and cluster role"
ConfigureVM $vmName $GuestOSName
if ($s2dclusterhyperv) {
 Invoke-Command -VMName $VMName -Credential $localCred {
         param($VMName, $domainCred, $ADName)
         Write-Output "[$($VMName)]:: Installing Roles"
         Install-WindowsFeature -Name File-Services, Failover-Clustering,Hyper-V, FS-SMBBW -IncludeManagementTools
        } -ArgumentList $VMName, $domainCred, $ADName
        }
else {
 Invoke-Command -VMName $VMName -Credential $localCred {
         param($VMName, $domainCred, $ADName)
         Write-Output "[$($VMName)]:: Installing Roles"
         Install-WindowsFeature -Name File-Services, Failover-Clustering, FS-SMBBW -IncludeManagementTools
        } -ArgumentList $VMName, $domainCred, $ADName
        }
rebootVM $VMName
}

if ($s2dclusterhyperv) {
for($i=1; $i -le 3; $i++){
$vmName = "Cluster Node $i"
$GuestOSName = "cn$i"
logger $vmName "add vNIC"
Invoke-Command -VMName $VMName -Credential $localCred {
param ($ADName)
 #  -NetAdapterName "Ethernet","Ethernet 2","Ethernet 3" 
 New-VMSwitch "vSwitch" -NetAdapterName "Ethernet","Ethernet 2","Ethernet 3" -AllowManagementOS $false -EnableEmbeddedTeaming $true
 #New-VMSwitch "vSwitch" -NetAdapterName "Ethernet","Ethernet 2","Ethernet 3" -AllowManagementOS 0
 Add-VMNetworkAdapter -ManagementOS -SwitchName "vSwitch" -Name "NIC 1"
 Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName 'NIC 1'  ManagementOS  PhysicalNetAdapterName 'Ethernet'
 #Get-VMNetworkAdapter -name "NIC 1" -All | Set-VMNetworkAdapterVlan -VlanId 831 -Access -ManagementOS
 Add-VMNetworkAdapter -ManagementOS -SwitchName "vSwitch" -Name "NIC 2"
  Add-VMNetworkAdapter -ManagementOS -SwitchName "vSwitch" -Name "NIC 3"
 
 #Enable-NetAdapterRDMA 'NIC 1','NIC 2','NIC 3'
 #Get-NetAdapterRdma | fl * 
 
 #New-VMSwitch "EastWest" -NetAdapterName "Ethernet 4" -AllowManagementOS 0
 #Add-VMNetworkAdapter -ManagementOS -SwitchName "EastWest" -Name "EW 1"
 #Add-VMNetworkAdapter -ManagementOS -SwitchName "EastWest" -Name "EW 2"
 #Add-VMNetworkAdapter -ManagementOS -SwitchName "EastWest" -Name "EW 3" 
 
 Set-SmbBandwidthLimit -Category LiveMigration -BytesPerSecond 90MB  

} -ArgumentList $ADName
}
}

sleep -seconds 20

for($i=1; $i -le 3; $i++){
$vmName = "Cluster Node $i"
$GuestOSName = "cn$i"
logger $vmName "AD join"
ADJoinVM $vmName $ADName $domainCred $localCred
}

logger "cluster" "cretae cluster"
Invoke-Command -VMName "Management Console" -Credential $domainCred {
param ($ADName)
ipconfig /flushdns; sleep -seconds 1
do {New-Cluster -Name cluster -Node cn1,cn2,cn3 -NoStorage} until ($?)
while (!(Test-Connection -Computername "cluster.$($ADName)" -BufferSize 16 -Count 1 -Quiet -ea SilentlyContinue)) 
      {ipconfig /flushdns; sleep -seconds 1}
      (Get-Cluster).BlockCacheSize = 1024
} -ArgumentList $ADName
sleep -seconds 30

logger "cluster" "Enable S2D"
Invoke-Command -VMName "Cluster Node 1" -Credential $domainCred {
param ($ADName)
Enable-ClusterS2D -AutoConfig:0 -SkipEligibilityChecks -Confirm:$false
Add-ClusterScaleoutFileServerRole -name SOFileServer -cluster "cluster.$($ADName)"
} -ArgumentList $ADName

# Create Cluster Disks / Foloder
logger "Cluster" "Create Cluster Disks / Folder"
Invoke-Command -VMName "Cluster Node 1" -Credential $domainCred {
param ($ADName)
New-StoragePool -StorageSubSystemName "cluster.$($ADName)" -FriendlyName SOFSPool -WriteCacheSizeDefault 0 -ProvisioningTypeDefault Fixed -ResiliencySettingNameDefault Mirror -PhysicalDisk (Get-StorageSubSystem  -Name "cluster.$($ADName)" | Get-PhysicalDisk)
New-Volume -StoragePoolFriendlyName "SOFSPool" -FriendlyName SOFSDisk -PhysicalDiskRedundancy 2 -FileSystem CSVFS_REFS -Size 1024GB
Set-FileIntegrity "C:\ClusterStorage\Volume1" -Enable $false
sleep -seconds 5
         MD C:\ClusterStorage\Volume1\VHDX
         MD C:\ClusterStorage\Volume1\VHDX\BaseVHD
         MD C:\ClusterStorage\Volume1\VHDX\Cluster
         New-SmbShare -Name VHDX -Path C:\ClusterStorage\Volume1\VHDX -FullAccess "$($ADName)\administrator", "$($ADName)\Management$", "$($ADName)\HarWee"
         Set-SmbPathAcl -ShareName VHDX

         MD C:\ClusterStorage\Volume1\ClusQuorum
         New-SmbShare -Name ClusQuorum -Path C:\ClusterStorage\Volume1\ClusQuorum -FullAccess "$($ADName)\administrator", "$($ADName)\Management$", "$($ADName)\HarWee"
         Set-SmbPathAcl -ShareName ClusQuorum

         MD C:\ClusterStorage\Volume1\ClusData
         New-SmbShare -Name ClusData -Path C:\ClusterStorage\Volume1\ClusData -FullAccess "$($ADName)\administrator", "$($ADName)\Management$", "$($ADName)\HarWee"
         Set-SmbPathAcl -ShareName ClusData

          MD C:\ClusterStorage\Volume1\Install
         New-SmbShare -Name Install -Path C:\ClusterStorage\Volume1\Install -FullAccess "$($ADName)\administrator", "$($ADName)\Management$", "$($ADName)\HarWee"
         Set-SmbPathAcl -ShareName Install

         MD C:\ClusterStorage\Volume1\RedirectedFolders
         New-SmbShare -Name RedirectedFolders -Path C:\ClusterStorage\Volume1\RedirectedFolders -FullAccess "$($ADName)\administrator", "Everyone"
    #     $acl = Get-Acl C:\ClusterStorage\Volume1\RedirectedFolders
    #     $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "CreateDirectories", "ContainerInherit, ObjectInherit", "None", "Allow")
    #     $acl.AddAccessRule($rule)
     #    Set-Acl C:\ClusterStorage\Volume1\RedirectedFolders $acl
} -ArgumentList $ADName

logger "Cluster" "create quorum share"
Invoke-Command -VMName "Domain Controller 1" -Credential $domainCred {
param ($ADName)
         MD C:\ClusQuorum
         New-SmbShare -Name ClusQuorum -Path C:\ClusQuorum -FullAccess "$($ADName)\administrator", "$($ADName)\harwee", "$($ADName)\cn1$", "$($ADName)\cn2$", "$($ADName)\cn3$", "$($ADName)\cluster$"
         Set-SmbPathAcl -ShareName ClusQuorum
} -ArgumentList $ADName
if($buildnano) {
logger "Cluster" "Create Cluster Disks / Folder"
Invoke-Command -VMName "Cluster Node 1" -Credential $domainCred {
param ($ADName)
     $acl = Get-Acl C:\ClusterStorage\Volume1\RedirectedFolders
     $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "CreateDirectories", "ContainerInherit, ObjectInherit", "None", "Allow")
     $acl.AddAccessRule($rule)
    Set-Acl C:\ClusterStorage\Volume1\RedirectedFolders $acl
} -ArgumentList $ADName
}

logger "Cluster" "create quorum share"
Invoke-Command -VMName "Domain Controller 1" -Credential $domainCred {
param ($ADName)
         MD C:\ClusQuorum
         New-SmbShare -Name ClusQuorum -Path C:\ClusQuorum -FullAccess "$($ADName)\administrator", "$($ADName)\harwee", "$($ADName)\cn1$", "$($ADName)\cn2$", "$($ADName)\cn3$", "$($ADName)\cluster$"
         Set-SmbPathAcl -ShareName ClusQuorum
} -ArgumentList $ADName

# Set quorum
logger "Cluster" "Set Quorum"
Invoke-Command -VMName "Management Console" -Credential $domainCred {
param ($ADName)
Set-ClusterQuorum -Cluster cluster.$($ADName) -NodeAndFileShareMajority "\\dc1.$($ADName)\ClusQuorum"
} -ArgumentList $ADName


if ($s2dclusterhyperv) {
for($i=1; $i -le 3; $i++){
$vmName = "Cluster Node $i"
$GuestOSName = "cn$i"
logger $vmName "Hyper-V Set default location"

Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
   Set-VMHost -VirtualHardDiskPath "C:\ClusterStorage\Volume1\VHDX\Cluster" `
           -VirtualMachinePath "C:\ClusterStorage\Volume1\VHDX\Cluster" 
} -ArgumentList $ADName
}
}
}

if($buildVMs) {
# Build import VHD

    if (!(Test-Path "$($BaseVHDs)\Import.vhdx")) 
    {
     Logger "Import VHD" "$($BaseVHDs)\Import.vhdx"
     $drive = (New-VHD -path "$($BaseVHDs)\Import.vhdx" -SizeBytes 20GB -Dynamic   | `
              Mount-VHD -Passthru |  `
              get-disk -number {$_.DiskNumber} | `
              Initialize-Disk -PartitionStyle MBR -PassThru | `
              New-Partition -UseMaximumSize -AssignDriveLetter:$False -MbrType IFS | `
              Format-Volume -Confirm:$false -FileSystem NTFS -force | `
              get-partition | `
              Add-PartitionAccessPath -AssignDriveLetter -PassThru | `
              get-volume).DriveLetter 
      Copy-Item -Path "$($BaseVHDs)\VMServerBase.vhdx" -Destination $drive":\"
      Dismount-VHD "$($BaseVHDs)\Import.vhdx"
         } else {Logger "Import VHD" "VHD exist" "OK"}


$vmName = "Management Console"
$GuestOSName = "Management"

logger $vmName "Import VHD file"
 Add-VMHardDiskDrive -VMName $VMName -Path "$($BaseVHDs)\Import.vhdx"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
Get-Disk | where OperationalStatus -eq Offline | Set-Disk -IsOffline:$false
Copy-Item -Path d:\VMServerBase.vhdx \\sofileserver\VHDX\BaseVHD
} -ArgumentList $ADName

# Create Hyper-V VMs


for($i=1; $i -le 3; $i++){

$vmName = "Cluster Node $i"
$GuestOSName = "cn$i"
$HVVM = "VM$i"
logger $vmName "create $HVVM"

Invoke-Command -VMName $vmName -Credential $domainCred {
                    param($ADName, $HVVM) 
   do {Copy-Item -Path "C:\ClusterStorage\Volume1\VHDX\BaseVHD\VMServerBase.vhdx" "C:\ClusterStorage\Volume1\vhdx\$HVVM.VHDX" | Out-Null} until ($?)
   do {new-vm -Name $HVVM -MemoryStartupBytes 800MB -SwitchName "vSwitch" -VHDPath "C:\ClusterStorage\Volume1\vhdx\$HVVM.VHDX" -Generation 2} until ($?)
          Set-VM -name $HVVM -ProcessorCount 2
          Get-VMNetworkAdapter -VMName $HVVM | Set-VMNetworkAdapter -MacAddressSpoofing on
          start-vm $HVVM
                    } -ArgumentList $ADName,$HVVM
 }
 
#  Enable HA
$vmName = "Management Console"
$GuestOSName = "Management"

logger $vmName "Enable HA"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
Add-ClusterVirtualMachineRole -Cluster cluster -VirtualMachine VM1
Add-ClusterVirtualMachineRole -Cluster cluster -VirtualMachine VM2
Add-ClusterVirtualMachineRole -Cluster cluster -VirtualMachine VM3
} -ArgumentList $ADName

}

    
if($buildnano)
{

#### Create Hyper-V Cluster
##  Check $($subnet) is working????
function BuildComputeNode {
param($VMName, $GuestOSName)
logger $VMName "configure Hyper-V cluster node \\10.10.10.1\c$\$($GuestOSName).txt"
   waitForPSDirect $VMName $localCred

   logger $VMName "Creating standard virtual switch and AD join"
   Invoke-Command -VMName $VMName -Credential $localCred {
      param($GuestOSName)
      enable-wsmancredssp -role server -force    #enables CredSSP authentication
      New-VMSwitch -Name "Virtual Switch" -NetAdapterName "Ethernet" -AllowManagementOS $true   # create default VM Switch
      djoin /requestodj /loadfile "\\10.10.10.1\c$\$($GuestOSName).txt" /windowspath c:\windows /localos    # load blob from DC1 and AD join
      del "\\10.10.10.1\c$\$($GuestOSName).txt"} -ArgumentList $GuestOSName

      # Reboot
      rebootVM $VMName; 
}
# Prepare offline AD join -> data blob stored on DC1
logger "HVCluster" "Prepair AD Join"
Invoke-Command -VMName "Management Console" -Credential $domainCred {
                    param($ADName)
                    djoin.exe /provision /domain $ADName /machine "HVNode1" /savefile \\10.10.10.1\c$\HVNode1.txt /reuse
                    djoin.exe /provision /domain $ADName /machine "HVNode2" /savefile \\10.10.10.1\c$\HVNode2.txt /reuse
                    } -ArgumentList $ADName
 
    
BuildComputeNode "Hyper-V Node 1" "HVNode1"
BuildComputeNode "Hyper-V Node 2" "HVNode2"

waitForPSDirect "Hyper-V Node 2" -cred $domainCred   # AD domain admin, when OK than AD join OK...

# create cluster
logger "HVCluster" "Create Cluster"
Invoke-Command -VMName "Management Console" -Credential $domainCred {
param ($ADName)
do {New-Cluster -Name HVCluster -Node HVNode1,HVNode2 -NoStorage} until ($?)
while (!(Test-Connection -Computername "HVCluster.$($ADName)" -BufferSize 16 -Count 1 -Quiet -ea SilentlyContinue)) 
      {ipconfig /flushdns; sleep -seconds 1}
} -ArgumentList $ADName

# Add computer rights on Storage
logger "HVCluster" "Add access rights on SOFS for Hyper-V nodes"
Invoke-Command -VMName "Cluster Node 1" -Credential $domainCred {
param ($ADName)
get-SmbShareAccess VHDX | Grant-SmbShareAccess -AccountName "$($ADName)\HVNode1$","$($ADName)\HVNode2$","$($ADName)\HVCluster$","$($ADName)\harwee" -AccessRight full -Confirm:$false
get-SmbShareAccess ClusQuorum | Grant-SmbShareAccess -AccountName "$($ADName)\HVNode1$","$($ADName)\HVNode2$","$($ADName)\HVCluster$" -AccessRight full -Confirm:$false
get-SmbShareAccess ClusData | Grant-SmbShareAccess -AccountName "$($ADName)\HVNode1$","$($ADName)\HVNode2$","$($ADName)\HVCluster$" -AccessRight full -Confirm:$false

Set-SmbPathAcl -ShareName VHDX       #sets the access control list (ACL) for the file system folder to match the ACL for the server message block (SMB) share
Set-SmbPathAcl -ShareName ClusQuorum
Set-SmbPathAcl -ShareName ClusData
} -ArgumentList $ADName


# Set quorum
logger "HVCluster" "Set Quorum"
Invoke-Command -VMName "Management Console" -Credential $domainCred {
param ($ADName)
Set-ClusterQuorum -Cluster HVCluster.$($ADName) -NodeAndFileShareMajority "\\SOFileServer.$($ADName)\ClusQuorum"
} -ArgumentList $ADName

# Default path
for($i=1; $i -le 2; $i++){

$vmName = "Hyper-V Node $i"
$GuestOSName = "HVNode$i"
logger $vmName "default path Hyper-V Node $i"
Invoke-Command -VMName $vmName -Credential $domainCred {
                    param($ADName)
 Set-VMHost -VirtualHardDiskPath "\\SOFileServer.$($ADName)\VHDX\Virtual Machines" `
           -VirtualMachinePath "\\SOFileServer.$($ADName)\VHDX\Virtual Machines"             
       } -ArgumentList $ADName
}

}

if($buildNanoVMs) {
# Build import VHD

    if (!(Test-Path "$($BaseVHDs)\Import.vhdx")) 
    {
     Logger "Import VHD" "$($BaseVHDs)\Import.vhdx"
     $drive = (New-VHD -path "$($BaseVHDs)\Import.vhdx" -SizeBytes 20GB -Dynamic   | `
              Mount-VHD -Passthru |  `
              get-disk -number {$_.DiskNumber} | `
              Initialize-Disk -PartitionStyle MBR -PassThru | `
              New-Partition -UseMaximumSize -AssignDriveLetter:$False -MbrType IFS | `
              Format-Volume -Confirm:$false -FileSystem NTFS -force | `
              get-partition | `
              Add-PartitionAccessPath -AssignDriveLetter -PassThru | `
              get-volume).DriveLetter 
      Copy-Item -Path "$($BaseVHDs)\VMServerBase.vhdx" -Destination $drive":\"
      Dismount-VHD "$($BaseVHDs)\Import.vhdx"
         } else {Logger "Import VHD" "VHD exist" "OK"}


$vmName = "Management Console"
$GuestOSName = "Management"

logger $vmName "Import VHD file"
 Add-VMHardDiskDrive -VMName $VMName -Path "$($BaseVHDs)\Import.vhdx"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
Get-Disk | where OperationalStatus -eq Offline | Set-Disk -IsOffline:$false
Copy-Item -Path d:\VMServerBase.vhdx \\sofileserver\VHDX\BaseVHD
} -ArgumentList $ADName

# Create Hyper-V VMs


for($i=1; $i -le 2; $i++){

$vmName = "Hyper-V Node $i"
$GuestOSName = "HVNode$i"
$HVVM = "VM$i"
logger $vmName "create $HVVM"

Invoke-Command -VMName $vmName -Credential $domainCred {
                    param($ADName, $HVVM) 
   do {Copy-Item -Path "\\sofileserver\VHDX\BaseVHD\VMServerBase.vhdx" "\\sofileserver\vhdx\Virtual Machines\$HVVM.VHDX" | Out-Null} until ($?)
   do {new-vm -Name $HVVM -MemoryStartupBytes 800MB -SwitchName "Virtual Switch" -VHDPath "\\sofileserver\vhdx\Virtual Machines\$HVVM.VHDX" -Generation 2} until ($?)
          Set-VM -name $HVVM -ProcessorCount 2
          Get-VMNetworkAdapter -VMName $HVVM | Set-VMNetworkAdapter -MacAddressSpoofing on
          start-vm $HVVM
                    } -ArgumentList $ADName,$HVVM
 }
 
#  Enable HA
$vmName = "Management Console"
$GuestOSName = "Management"

logger $vmName "Enable HA"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
Add-ClusterVirtualMachineRole -Cluster HVCluster -VirtualMachine VM1
Add-ClusterVirtualMachineRole -Cluster HVCluster -VirtualMachine VM2
} -ArgumentList $ADName

}

if($builddocker) {
# Setup Container Host and docker template
$vmName = "Container 1"
$GuestOSName = "Con1"

    
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName
ADJoinVM $vmName $ADName $domainCred $localCred
 waitForPSDirect $VMName -cred $domainCred
 logger $vmName "Enable Container"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
Install-WindowsFeature containers
} -ArgumentList $ADName
rebootVM $VMName

logger $vmName "Install Docker"
 Invoke-Command -VMName $VMName -Credential $domainCred {
param ($ADName)
 
# Download, install and configure Docker Engine
Invoke-WebRequest "https://download.docker.com/components/engine/windows-server/cs-1.12/docker.zip" -OutFile "$env:TEMP\docker.zip" -UseBasicParsing
Expand-Archive -Path "$env:TEMP\docker.zip" -DestinationPath $env:ProgramFiles

# For quick use, does not require shell to be restarted.
$env:path += ";c:\program files\docker"
# For persistent use, will apply even after a reboot. 
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\Docker", [EnvironmentVariableTarget]::Machine)

# Start a new PowerShell prompt before proceeding
#dockerd --register-service

# Open firewall port 2375
netsh advfirewall firewall add rule name="docker engine" dir=in action=allow protocol=TCP localport=2375

# Configure Docker daemon to listen on both pipe and TCP (replaces docker --register-service invocation above)
dockerd.exe -H npipe:////./pipe/docker_engine -H 0.0.0.0:2375 --register-service
Start-Service docker
} -ArgumentList $ADName

}
#>


if($buildtestvm1) {
$vmName = "Test 1"
$GuestOSName = "Test1"
CreateVM $vmName $GuestOSName -FullServer
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName
ADJoinVM $vmName $ADName $domainCred $localCred
 waitForPSDirect $VMName -cred $domainCred

}


if($buildtestvm2) {
$vmName = "Test 2"
$GuestOSName = "Test2"
CreateVM $vmName $GuestOSName -FullServer
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName
ADJoinVM $vmName $ADName $domainCred $localCred
 waitForPSDirect $VMName -cred $domainCred

}


if($buildtestvm3) {
$vmName = "Test 3"
$GuestOSName = "Test3"
CreateVM $vmName $GuestOSName -FullServer
logger $vmName "start configuration"
ConfigureVM $vmName $GuestOSName
ADJoinVM $vmName $ADName $domainCred $localCred
 waitForPSDirect $VMName -cred $domainCred

}