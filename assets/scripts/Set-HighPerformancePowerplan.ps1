function Write-POWERCFGEvent { write-eventlog -eventID $eventid -logName 'Application' -source 'Configuration' -entryType $entrytype -message $message; }

New-EventLog -Source 'Configuration' -LogName 'Application' -Verbose

# Backup the default Windows High Performance Powerplan
$activeSchemeGUID = ((((powercfg -GETACTIVESCHEME).split(':')[1]).trim()).split(' ')[0]).trim(); 
powercfg -query $activeSchemeGUID | Out-File ($env:TEMP+'\Output-of-CurrentScheme.txt'); powercfg -export ($env:TEMP+'\'+$env:COMPUTERNAME+'_Backup-PowerScheme_'+$activeSchemeGUID+'.pow') $activeSchemeGUID;

if (!($env:TEMP+'\Backup-PowerScheme_'+$activeSchemeGUID+'.pow')){$message = ('Power Plan backup not detected after backup attempt; please review. High Performance Powerplan will be overwritten.'); $eventid='1416'; $entrytype='ERROR'; Write-POWERCFGEvent} 
elseif (($env:TEMP+'\Backup-PowerScheme_'+$activeSchemeGUID+'.pow')){$message = ('High Performance Powerplan backup completed; reference '+($env:TEMP+'\Backup-PowerScheme_'+$activeSchemeGUID+'.pow')+'. High Performance Powerplan was overwritten.'); $eventid='1212'; $entrytype='ERROR'; Write-POWERCFGEvent} 
else {$message = ('High Performance Powerplan backup completed; reference '+($env:TEMP+'\Backup-PowerScheme_'+$activeSchemeGUID+'.pow')+'.'); $eventid='1212'; $entrytype='ERROR'; Write-POWERCFGEvent}

POWERCFG -CHANGE -disk-timeout-ac 0; POWERCFG -CHANGE -standby-timeout-ac 0; POWERCFG -CHANGE -hibernate-timeout-ac 0; POWERCFG -CHANGE -hibernate-timeout-dc 0;
$subGUIDTEST = (powercfg /query $activeSchemeGUID SUB_SLEEP | Where-Object {$_ -like '*Sleep After*'}).split(' ')[7];
$finalTest = (powercfg /query $activeSchemeGUID SUB_SLEEP $subGUIDTEST | Where-Object {$_ -like '*AC Power Setting*'}).split(' ')[9];
if ($finalTest -notlike '0x00000000'){ $message = ('Attempted overwriting High Performance Powerplan and Expected Preferences not Set.'); $eventid='1416'; $entrytype='ERROR'; Write-POWERCFGEvent; }
