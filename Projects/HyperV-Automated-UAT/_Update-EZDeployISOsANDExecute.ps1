$passdw = Get-Credential -Message 'Enter the Password!' -UserName 'StackAdmin'
# Set the source folder containing the PPKG and MSI files
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
