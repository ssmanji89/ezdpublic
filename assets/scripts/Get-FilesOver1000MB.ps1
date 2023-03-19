$path = "c:\"
$size = 1MB
$limit = 1000
$Extension = "*.*"
get-ChildItem -Recurse -path $path -ErrorAction "SilentlyContinue" `
    -include $Extension `
    | ? { $_.GetType().Name -eq "FileInfo" } `
    | where-Object {$_.Length -gt $size} `
    | sort-Object -property length -Descending `
    | Select-Object Name, @{Name="SizeInMB";Expression={$_.Length / 1MB}},@{Name="Path";Expression={$_.directory}} -first $limit `
    | Export-Csv ($env:SystemDrive+'\Temp\'+$env:COMPUTERNAME+'_Top-1000-Files.csv')
