$drives = (Get-PSDrive | Where-Object {$_.Provider -like '*FileSystem*'} | select -expa root).trim(':\');
if (($drives).count -gt 0) {
    foreach ($d in $drives) {
        $curFree = Get-PSDrive -Name $d | select -ExpandProperty free;
        $curUsed = Get-PSDrive -Name $d | select -ExpandProperty used;
        $curTotal = (($curFree + $curUsed));
        if ($curUsed -gt 0) {
        $curCalculated = ((($curFree / 1GB) / ($curTotal / 1GB))*100);
            if ($curTotal -gt 0) {
                $curFreeMB = [math]::floor($curFree / 1GB);
                $curUsedMB = [math]::Floor($curUsed / 1GB);
                if ($curCalculated -lt 2) {
                    $message = ('Warning; Disk '+$d+' currently has '+$curFreeMB+'GB free of '+$curUsedMB+'GB ('+$curCalculated+' percent)');
                    Write-EventLog -LogName Application -Source 'DiskSpaceMonitoring' -EventId 11902 -Message $message -EntryType Error; 
                    tempCleanup;
                } elseif ($curCalculated -lt 5) {
                    $message = ('Warning; Disk '+$d+' currently has '+$curFreeMB+'GB free of '+$curUsedMB+'GB ('+$curCalculated+' percent)');
                    Write-EventLog -LogName Application -Source 'DiskSpaceMonitoring' -EventId 11905 -Message $message -EntryType Error; 
                    tempCleanup
                } elseif ($curCalculated -lt 10) {
                    $message = ('Warning; Disk '+$d+' currently has '+$curFreeMB+'GB free of '+$curUsedMB+'GB ('+$curCalculated+' percent)');
                    Write-EventLog -LogName Application -Source 'DiskSpaceMonitoring' -EventId 11910 -Message $message -EntryType Warning; 
                    tempCleanup
                } else { 
                    Write-Host 'Clear; no drives trigger allotted thresholds.';
                }
            }
        }
    }
} 