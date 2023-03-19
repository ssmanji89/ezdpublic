$ErrorActionPreference = 'SilentlyContinue'; 

New-Item HKLM:\SOFTWARE\ -Name 'IT' -ErrorAction SilentlyContinue;
New-EventLog -LogName Application -Source 'IT' -ErrorAction SilentlyContinue;

function Test-ItemProperty() {
    param ( 
        [string]$path = $(throw "Need a path"),
        [string]$name = $(throw "Need a name") 
    )

    $temp = $null
    $temp = Get-ItemProperty -path $path -name $name -errorAction SilentlyContinue
    return $temp -ne $null
}

$RegKey ="HKLM:\Software\Policies\Adobe\Acrobat Reader"
$version = Get-ChildItem $RegKey -Name
$Path = ($RegKey + "/" + $version + "\FeatureLockDown")

if(Test-ItemProperty -path $Path -name bUpdater = $null ) {
    Set-ItemProperty -path $Path -name bUpdater -value 0
} else {
    New-ItemProperty -path $Path -name bUpdater -value 0
}

if (-not (Get-ComputerRestorePoint)){
    Enable-ComputerRestore -drive $env:SystemDrive;
    Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Windows System Restore has been enabled.' -EntryType Information;
    'Windows System Restore has been enabled.' | Out-File $centralfile -Append;
}

$test = (get-service -name ('AdobeARM*') | Where-Object {$_.status -eq 'Disabled'}); 
if ($test) {  
    Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'AdobeARM Service Disabled.' -EntryType Information;
    $test2 = (get-service -name AdobeARM* | Where-Object {$_.StartType -ne 'Disabled'} | Stop-Service -PassThru | Set-Service -StartupType disabled); 
}

if (((gci ($ENV:ProgramFiles+'\Java') -recurse).length -gt 0) -or ((gci ('C:\Program Files (x86)\Java') -recurse).length -gt 0)){
    if ((get-itemproperty -path 'REGISTRY::HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy' -Name EnableJavaUpdate | select -expa EnableJavaUpdate) -ne '0') {
        Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Java Configuration implemented for 64-bit installations.' -EntryType Information;
        'Java Configuration implemented.' | Out-File $centralfile -Append;
        reg add 'HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy' /v NotifyDownload /t REG_DWORD /d 0 /f;
        reg add 'HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy' /v EnableJavaUpdate /t REG_DWORD /d 0 /f; 
        reg add 'HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy' /v EnableAutoUpdateCheck /t REG_DWORD /d 0 /f;
    }elseif ((get-itemproperty -path 'REGISTRY::HKLM\SOFTWARE\JavaSoft\Java Update\Policy' -Name EnableJavaUpdate | select -expa EnableJavaUpdate) -ne '0') {
        Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Java Configuration implemented for 32-bit installations.' -EntryType Information;
        'Java Configuration implemented.' | Out-File $centralfile -Append;
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v NotifyDownload /t REG_DWORD /d 0 /f;
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v EnableJavaUpdate /t REG_DWORD /d 0 /f; 
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v EnableAutoUpdateCheck /t REG_DWORD /d 0 /f;
    } else {
        'Java Configuration already implemented.' | Out-File $centralfile -Append;
    }
}

if ((gci ($ENV:ProgramFiles+'\Java') -recurse).length -gt 0){ 
    if ((get-itemproperty -path 'REGISTRY::HKLM\SOFTWARE\JavaSoft\Java Update\Policy' -Name EnableJavaUpdate | select -expa EnableJavaUpdate) -ne '0') {
        Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Java Configuration implemented.' -EntryType Information;
        'Java Configuration implemented.' | Out-File $centralfile -Append;
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v NotifyDownload /t REG_DWORD /d 0 /f;
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v EnableJavaUpdate /t REG_DWORD /d 0 /f; 
        reg add 'HKLM\SOFTWARE\JavaSoft\Java Update\Policy' /v EnableAutoUpdateCheck /t REG_DWORD /d 0 /f;
    }
}

if (-not ((get-content ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') | where-object {$_ -like '*SilentAutoUpdateVerboseLogging=1*'}) -or (get-content ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') | where-object {$_ -like '*SilentAutoUpdateVerboseLogging=1*'}))) {
    Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Adobe Flash Configuration implemented.' -EntryType Information;
    
    Remove-Item ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') -force; 
    
    write-output 'SilentAutoUpdateEnable=1' | out-file ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') -append; 
    write-output 'AutoUpdateDisable=0' | out-file ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') -append; 
    write-output 'AutoUpdateInterval=7' | out-file ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') -append; 
    write-output 'SilentAutoUpdateVerboseLogging=1' | out-file ($env:systemroot+'\SysWOW64\Macromed\Flash\mms.cfg') -append;
} elseif (-not (get-content ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') | where-object {$_ -like '*SilentAutoUpdateVerboseLogging=1*'})) {
    Write-EventLog -LogName Application -Source 'IT' -EventId 10102 -Message 'Adobe Flash Configuration implemented.' -EntryType Information;
    
    remove-item ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') -force -ErrorAction SilentlyContinue; 
    write-output 'SilentAutoUpdateEnable=1' | out-file ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') -append; 
    write-output 'AutoUpdateDisable=0' | out-file ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') -append; 
    write-output 'AutoUpdateInterval=7' | out-file ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') -append; 
    write-output 'SilentAutoUpdateVerboseLogging=1' | out-file ($env:systemroot+'\System32\Macromed\Flash\mms.cfg') -append;
}