$chassis = (Get-WmiObject -Class Win32_SystemEnclosure | select -ExpandProperty chassistypes);

$chassisType = switch ($chassis) 
    { 
        1 {"OTH"} 
        2 {"UNKN"} 
        3 {"DSKTP"} 
        4 {"LPDSKTP"} 
        5 {"PB"} 
        6 {"MTWR"} 
        7 {"TWR"} 
        8 {"MB"} 
        9 {"LPT"} 
        10 {"LPT"} 
        11 {"MB"} 
        12 {"DS"} 
        13 {"AIO"} 
        14 {"SubLPT"} 
        15 {"SS"} 
        16 {"LB"} 
        17 {"MS"} 
        18 {"EXP"} 
        19 {"Sub"} 
        20 {"BUS"} 
        21 {"PERPH"} 
        22 {"STOR"} 
        23 {"RM"} 
        24 {"S-C"} 
            default {"ChassisType could not be determined."}
    }
 
$serial = (Get-WmiObject -Class Win32_SystemEnclosure | select -ExpandProperty serialnumber); 
$newComputerName = ('SLP-'+$chassisType+'-'+$serial);
$NewName=$newComputerName
$newComputerName
#$ComputerInfo = Get-WmiObject -Class Win32_SystemEnclosure
#$ComputerInfo.Rename($newComputerName)

Rename-Computer -NewName $newComputerName -Force