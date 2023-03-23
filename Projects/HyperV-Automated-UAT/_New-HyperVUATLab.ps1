# 
function Set-RunOnce {
    [CmdletBinding()]
    param
    (
        #The Name of the Registry Key in the Autorun-Key.
        [string]
        $KeyName = 'Run',

        #Command to run
        [string]
        $Command = '%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file c:\Scripts\run1.ps1'
  
    ) 

    
    if (-not ((Get-Item -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce).$KeyName ))
    {
        New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString
    }
    else
    {
        Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString
    }
}

#Set-RunOnce -KeyName 'WinGETInstallation' -Command '%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file c:\Install-Winget1.ps1'

function ISOAndStartWebstartMSI {
    Get-VM | Where-Object { $_.State -ne 'Off'} | ForEach-Object {
        $curVM = $_.VMName
        #Stop-VM -Name $CurVMName -Verbose; 
        #Get-VMSnapshot -VMName $CurVMName | select -First 1 | Restore-VMCheckpoint -Verbose -Confirm:$False
        #Start-VM -Name $CurVM
        Add-VMDvdDrive -VMName $curVM -Path $WebstartDeployersISOPath;
        Invoke-Command -VMName $curVM -Credential $passdw -ScriptBlock {
            ((Get-Volume | Where-Object {$_.FileSystemLabel -like '*Deploy*'}) | ForEach-Object {gci -Path ($_.DriveLetter+":")} | select -expa FullName) | `
                ForEach-Object {
                    Start-Process msiexec.exe -ArgumentList ('/i '+($_)+' /qn /norestart /l*v c:\windows\temp\_Stack_SullyRun.txt')
                }
        } -ArgumentList $curVM
    }    
}
$passdw = Get-Credential -Message 'Enter the Password!' -UserName 'StackAdmin'

# iex ((New-Object System.Net.WebClient).DownloadString('https://www.powershellgallery.com/packages/Cloud.Ready.Software.Windows/1.0.0.8/Content/New-ISOFileFromFolder.ps1')) -Verbose

if (!(Import-Module Cloud.Ready.Software.Windows)) {
    Install-Module -Name Cloud.Ready.Software.Windows
    Import-Module Cloud.Ready.Software.Windows
}

$VMSwitch = "Default"
$Switch = Get-VMSwitch -Name $VMSwitch -ErrorAction SilentlyContinue
if (!$Switch) {
    Write-Host "Creating virtual switch $VMSwitch"
    New-VMSwitch -Name $VMSwitch -NetAdapterName "Ethernet"
} else {
    Write-Host "Using existing virtual switch $VMSwitch"
}

$MasterVHDX = ".\Win10_22H2_EnglishInternational_x64.vhdx"
$labRoot = "E:\"
$VHDXPath = "E:\VHDXs"
$cnt = 0
$maxCount = 5 # INTEGER for the Number of VM's to Create from the Master/Gold VHDX

$SourceFolder = (( pwd | select -expa Path)+"\deployers\OneTouch")
# Set the destination path for the ISO file
$OneTouchDeployersISOPath = (( pwd | select -expa Path)+"\deployers\OneTouch-"+(Get-Date).Day+"-"+(Get-Date).Month+".iso")
# Create a new ISO file using the New-IsoFile cmdlet
Remove-Item -Path $OneTouchDeployersISOPath -Force -Verbose -ErrorAction SilentlyContinue
New-ISOFileFromFolder -Name 'OneTouchDeployers' -FilePath $SourceFolder -ResultFullFileName $OneTouchDeployersISOPath -Verbose 
# Set the source folder containing the PPKG and MSI files
$SourceFolder = (( pwd | select -expa Path)+"\deployers\WebStart")
# Set the destination path for the ISO file
$WebstartDeployersISOPath = (( pwd | select -expa Path)+"\deployers\WebStart-"+(Get-Date).Day+"-"+(Get-Date).Month+".iso")
# Create a new ISO file using the New-IsoFile cmdlet
Remove-Item -Path $WebstartDeployersISOPath -Force -Verbose -ErrorAction SilentlyContinue
New-ISOFileFromFolder -Name 'WebstartDeployers' -FilePath $SourceFolder -ResultFullFileName $WebstartDeployersISOPath -Verbose 
while ($cnt -lt $maxCount) {
    $cnt = $cnt + 1
    $CurVMName = ('SULLY-W10-LAB'+(Get-Date).Millisecond)
    Write-Verbose ("Copying Master VHDX and Deploying new VM with name "+$curVMName+"") -Verbose 
    Copy-Item $MasterVHDX "$VHDXPath\$CurVMName.vhdx"
    Write-Verbose "VHDX Copied, Building VM...." -Verbose
    New-VM -Name $CurVMName -MemoryStartupBytes 3GB -VHDPath ($VHDXPath+"\"+$CurVMName+".vhdx") -Generation 2 -SwitchName $VMSwitch
    # Enable-VMIntegrationService -Name $CurVMName -VMName $CurVMName
    Write-Verbose "VM Creation Completed. Starting VM "+$curVMName+"" -Verbose
    Start-VM $curVMName -AsJob
}

Get-VM | Where-Object { $_.State -ne 'Off'} | ForEach-Object {
    $curVM = $_.VMName
    Stop-VM -Name $curVM -Verbose; 
    Start-Sleep -Seconds 3;
    Start-VM $curVM -AsJob;
}

Start-Sleep -Seconds 300;
ISOAndStartWebstartMSI;