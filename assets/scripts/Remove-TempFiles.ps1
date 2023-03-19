Start-Transcript -Path ($env:TEMP+'\Logs\TempCleanup_Day-'+((get-date).dayofyear)+'_Hour-'+((get-date).Hour)+'.txt') -Append
Import-Module ./_bits/*
New-EventLog -Source 'Disk Cleanup' -LogName Application

<# Cleanup Standard/Common Temp Directories #>
$tempfolders = (
    ($ENV:SystemDrive + '\Perflog\'),
    ($ENV:SystemDrive + '\Recovery\'),
    ($ENV:SystemDrive + '\Windows\Temp\'),
    ($ENV:SystemDrive + '\Windows\Temp\LTCache\'),
    ($ENV:SystemDrive + '\Windows\Prefetch\'),
    ($ENV:Windir + '\SoftwareDistribution\Download\'),
    ($ENV:Windir + '\Logs\dosvc\'),
    ($ENV:Windir + '\Installer\$PatchCache$\Managed\'),
    ($ENV:SystemDrive + '\*regbackup*'),
    ($ENV:SystemDrive + '\Program Files\Windows Small Business Server\Logs\'),
    ($ENV:SystemDrive + '\Program Files\Common Files\Microsoft Shared\Web Server Extensions\14\Logs\'),
    ($ENV:ProgramData + '\Veeam\Backup'),
    ($ENV:Windir + '\system32\logfiles'),
    ($ENV:Windir + '\system32\wbem\Logs')
);
    
foreach ($i in $tempfolders) {
    if (Test-Path $i) {
        $first = (gci $i );
        $first | select -expa fullname;
        $message = ('[' + $stamp + '] Scanning Directory: ' + $i);
        Write-EventLog -LogName Application -source 'Disk Cleanup' -EventId 10994 -message $message -EntryType Information; 	    

        foreach ($f in $first) {
            $cur = $f.name; 
            $curFull = $f.fullname; 
            if (Test-Path $curFull) {                    
                if (($is).lastaccesstime -lt (Get-Date).AddDays(-90.25)) {
                    $message = ('[' + $stamp + '] Removing Item: ' + $is+' ('+$is.LastAccessTime+')');	    
                    $message = ('Attempted overwriting High Performance Powerplan and Expected Preferences not Set.'); $eventid='1416'; $entrytype='Information'; Write-CurEvent;
                    Remove-Item $is.fullname -Verbose -Recurse;
                }
            }
        }
    }
}; 

<# Cleanup by '-like FullnameSearch'
foreach ($user in (gci ($ENV:SystemDrive+'\Users') | Where-Object {$_ -notlike '*ReportServer*' -and $_ -notlike '*svcsqlserver*'})) {
    $u = $user;
    $userPaths = (
        ($ENV:SystemDrive + '\Users\'+$u.name+'\Appdata\Local\Crashdumps\'),
        ($ENV:SystemDrive + '\Users\'+$u.name+'\AppData\Local\Citrix\GoToMeeting')
    );
    foreach ($us in $userPaths) {
        foreach ($is in (gci $us -ErrorAction SilentlyContinue)) {
            if ($is.fullname -like '*Crashdumps*') {
                $message = ('[' + $stamp + '] Removing Item: ' + $is+' ('+$is.LastAccessTime+')');	    
                Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
                Remove-Item $is.fullname -Verbose -Recurse;
            }
            if ($is.fullname -like '*Gotomeeting*') {
                $message = ('[' + $stamp + '] Removing Item: ' + $is+' ('+$is.LastAccessTime+')');	    
                Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
                Remove-Item $is.fullname -Verbose -Recurse;
            }
        }
    }
}
#>

<# Windows User Profile Cleanup 
foreach ($user in (gci ($ENV:SystemDrive+'\Users') | Where-Object {$_ -notlike '*ReportServer*' -and $_ -notlike '*svcsqlserver*'})) {
    $u = $user;
    $userPaths = (
        ($ENV:SystemDrive + '\Users\'+$u.name+'\Downloads')
    );
    foreach ($us in $userPaths) {
        foreach ($is in (gci $us -ErrorAction SilentlyContinue)) {
            if (($is).lastaccesstime -lt (Get-Date).AddDays(-90.25)) {
                $message = ('[' + $stamp + '] Removing Item: ' + $is+' ('+$is.LastAccessTime+')');	    
                Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
                Remove-Item $is.fullname -Verbose -Recurse;
            }
        }
    }
}
#>

<# Google Chrome Cleanup
foreach ($user in (gci ($ENV:SystemDrive+'\Users') | Where-Object {$_ -notlike '*ReportServer*' -and $_ -notlike '*svcsqlserver*'})) {
    $u = $user;
    $userPaths = (
        ($ENV:SystemDrive + '\Users\'+$u.name+'\AppData\Local\Google\Chrome\Cache'),
        ($ENV:SystemDrive + '\Users\'+$u.name+'\AppData\Local\Google\Chrome\Default\Cache'),
        ($ENV:SystemDrive + '\Users\'+$u.name+'\AppData\Local\Google\Chrome\Default\Media Cache\'),
        ($ENV:SystemDrive + '\Users\'+$u.name+'\AppData\Local\Google\Chrome\Media Cache\')
    );
    foreach ($us in $userPaths) {
        foreach ($is in (gci $us -ErrorAction SilentlyContinue)) {
            $message = ('[' + $stamp + '] Removing Item: ' + $is+' ('+$is.LastAccessTime+')');	    
            Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
            Remove-Item $is.fullname -Verbose;
        }
    }
}
#>
    
<# Quickbooks
$quickBooks = (gci ($ENV:ProgramData + '\Intuit') -Recurse);
foreach ($q in $quickBooks) {
    if ($q.FullName -like '*.qbc' -or $q.FullName -like '*_msp.dat') {
        $message = ('[' + $stamp + '] Removing Item: ' + $q.FullName+' ('+$q.LastAccessTime+')');	    
        Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
        Remove-Item $q.FullName -Force -Verbose -Recurse;
    }
} 
#>
$message = ('Temp File Cleanup Procedure complete. Reference '+($ENV:TEMP+'\Logs\TempCleanup_'+$day+'-'+$hour+'.txt')); 
Write-EventLog -eventID 1212 -logName 'Application' -source 'Disk Cleanup' -entryType 'Information' -message $message;
Stop-Transcript