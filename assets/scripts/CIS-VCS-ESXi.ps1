
function Test-Port {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, HelpMessage = 'Could be suffixed by :Port')]
        [String[]]$ComputerName,

        [Parameter(HelpMessage = 'Will be ignored if the port is given in the param ComputerName')]
        [Int]$Port = 5985,

        [Parameter(HelpMessage = 'Timeout in millisecond. Increase the value if you want to test Internet resources.')]
        [Int]$Timeout = 1000
    )

    begin {
        $result = [System.Collections.ArrayList]::new()
    }

    process {
        foreach ($originalComputerName in $ComputerName) {
            $remoteInfo = $originalComputerName.Split(":")
            if ($remoteInfo.count -eq 1) {
                # In case $ComputerName in the form of 'host'
                $remoteHostname = $originalComputerName
                $remotePort = $Port
            } elseif ($remoteInfo.count -eq 2) {
                # In case $ComputerName in the form of 'host:port',
                # we often get host and port to check in this form.
                $remoteHostname = $remoteInfo[0]
                $remotePort = $remoteInfo[1]
            } else {
                $msg = "Got unknown format for the parameter ComputerName: " `
                    + "[$originalComputerName]. " `
                    + "The allowed formats is [hostname] or [hostname:port]."
                Write-Error $msg
                return
            }

            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $portOpened = $tcpClient.ConnectAsync($remoteHostname, $remotePort).Wait($Timeout)

            $null = $result.Add([PSCustomObject]@{
                RemoteHostname       = $remoteHostname
                RemotePort           = $remotePort
                PortOpened           = $portOpened
                TimeoutInMillisecond = $Timeout
                SourceHostname       = $env:COMPUTERNAME
                OriginalComputerName = $originalComputerName
                })
        }
    }

    end {
        return $result
    }
}

function Add-vCLIfunction {
    <#
    .SYNOPSIS
      Adds the VMware vSphere Command-Line Interface perl scripts as PowerCLI functions.
  
    .DESCRIPTION
      Adds all the VMware vSphere Command-Line Interface perl scripts as PowerCLI functions.
      VMware vSphere Command-Line Interface has to be installed on the system where you run this function.
      You can download the VMware vSphere Command-Line Interface from:
      http://communities.vmware.com/community/vmtn/server/vsphere/automationtools/vsphere_cli?view=overview
  
    .EXAMPLE
      Add-vCLIfunction
      Adds all the VMware vSphere Command-Line Interface perl scripts as PowerCLI functions to your PowerCLI session.
  
    .COMPONENT
      VMware vSphere PowerCLI
  
    .NOTES
      Author:  Robert van den Nieuwendijk
      Date:    21-07-2011
      Version: 1.0
    #>
  
    process {
      # Test if VMware vSphere Command-Line Interface is installed
      If (-not (Test-Path -Path "$env:ProgramFiles\VMware\VMware vSphere CLI\Bin\")) {
        Write-Error "VMware vSphere CLI should be installed before running this function."
      } else {
        # Add all the VMware vSphere CLI perl scripts as PowerCLI functions
        Get-ChildItem -Path "$env:ProgramFiles\VMware\VMware vSphere CLI\Bin\*.pl" | ForEach-Object {
          $Function = "function global:$($_.Name.Split('.')[0]) { perl '$env:ProgramFiles\VMware\VMware vSphere CLI\bin\$($_.Name)'"
          $Function += ' $args }'
          Invoke-Expression $Function
        }
      }
    }
}

function Send-STSplunkMessage {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)] $InputObject,
        #[String] $Severity = "Information",
        [String] $Source = 'powershell.splunkmessage',
        [String] $SourceType = 'powershell.splunkmessage.testing',
        [String] $Index = 'test',
        [String] $SplunkHECToken = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
        [String[]] $SplunkUri = @(),
        [Switch] $VerboseJSONCreation = $false,
        [Switch] $CoerceNumberStrings = $false,
        [Switch] $Proxy = $false
    )
    Begin {
        if (($PSVersionTable.PSVersion.Major -eq 2) -or $CoerceNumberStrings) {
            # PSv2-compatible "$PSScriptRoot".
            $MyHome = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
            try {
                $ErrorActionPreference = 'Stop'
                # ConvertTo-STJson, https://github.com/EliteLoser/ConvertTo-Json
                # Svendsen Tech. MIT License. Copyright Joakim Borger Svendsen / Svendsen Tech. 2016-present.
                . "$MyHome\ConvertTo-STJson.ps1"
            }
            catch {
                Write-Error -ErrorAction Stop -Message "This script depends on 'ConvertTo-STJson.ps1' in the same folder as the calling script on PowerShell version 2 - and also if you specify the parameter -CoerceNumberStrings. See https://github.com/EliteLoser/ConvertTo-Json"
            }
            $ErrorActionPreference = 'Continue'
        }
        
        if ($SplunkUri.Count -eq 0) {
            # Using default list.
            Write-Verbose -Message "No Splunk forwarder URI specified. Using default list if one has been hardcoded in the source code."
            $SplunkUri = @() # list of strings with URLs to Splunk forwarders... I know this is esoteric, but kind of "real world"?
        }
        if ($SplunkUri.Count -eq 0) {
            # Fail and halt if no Splunk forwarders are specified (or hardcoded above).
            Write-Error -ErrorAction  Stop -Message "No Splunk forwarder URI specified. No default list hardcoded in source code. Exiting. Please specify splunk forwarder(s) using the parameter -SplunkUri."
        }
        Write-Verbose -Message "Choosing from the following Splunk URI(s):`n$($SplunkUri -join ""`n"")"
        $Domain = GetDomain
        [Bool] $GotGoodForwarder = $False
    }

    Process {
        Write-Verbose -Message "Trying to log to splunk. Source: '$Source'. SourceType: '$SourceType'. Index: '$Index'."
        # Code for PSv2 and up ...
        # http://www.powershelladmin.com/wiki/Convert_between_Windows_and_Unix_epoch_with_Python_and_Perl # using diff logic
        :FORWARD while ($True) {
            try {
                $ErrorActionPreference = "Stop"
                if ($GotGoodForwarder -eq $False) {
                    if ($SplunkUri.Count -eq 0) {
                        Write-Warning -Message "None of the Splunk forwarders worked. Last recorded error message in system buffer is: $(
                            $Error[0].Exception.Message)"
                        break FORWARD
                    }
                    $CurrentSplunkUri = $SplunkUri | Get-Random -Count 1
                    $SplunkUri = $SplunkUri | Where-Object { $_ -ne $CurrentSplunkUri } # pop...
                    Write-Verbose -Message "Splunk URIs left:`n$($SplunkUri -join ""`n"")"
                }
                if (($PSVersionTable.PSVersion.Major -eq 2) -or $CoerceNumberStrings) {
                    $Json = ConvertTo-STJson -InputObject $InputObject -Verbose:$VerboseJSONCreation -CoerceNumberStrings:$CoerceNumberStrings
                }
                else {
                    $Json = ConvertTo-Json -InputObject $InputObject -Verbose:$VerboseJSONCreation
                }
                if (-not (Get-Variable -Name STSplunkWebClient -ErrorAction SilentlyContinue)) {
                    $STSplunkWebClient = New-Object -TypeName System.Net.WebClient -ErrorAction Stop
                    $STSplunkWebClient.Headers.Add([System.Net.HttpRequestHeader]::Authorization, "Splunk $SplunkHECToken")
                    $STSplunkWebClient.Headers.Add("Content-Type", "application/json")
                    $STSplunkWebClient.Encoding = [System.Text.Encoding]::UTF8
                    if (-not $Proxy) {
                        # Do not use the proxy specified in browser/registry settings.
                        $STSplunkWebClient.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
                    }
                }
                $Result = $STSplunkWebClient.UploadString($CurrentSplunkUri, "POST", @"
{
    "time": $([Math]::Floor(([DateTime]::Now - (Get-Date -Year 1970 -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0)).TotalSeconds)),
    "host": "$env:ComputerName.$Domain",
    "source": "$Source",
    "sourcetype": "$SourceType",
    "index": "$Index",
    "event": $Json
}
"@.Trim()
                )
                if ($Result -match ':\s*"Success"') {
                    "Successfully sent event JSON to '$CurrentSplunkUri'."
                    $GotGoodForwarder = $True
                    break FORWARD
                }
                else {
                    Write-Warning -Message "It might not have gone well sending to '$CurrentSplunkUri'. Result looks like this: $Result. Last error in system buffer is: $($Error[0].Exception.Message -replace '[\r\n]+', ' ')"
                    Write-Verbose -Message "This is the 'event JSON' we tried:`n$Json"
                    #$GotGoodForwarder = $False # infinite loop with malformed data, etc., so we can't do that. -Joakim
                    #break FORWARD
                }
            }
            catch {
                Write-Warning -Message "[$([DateTime]::Now.ToString('yyyy\-MM\-dd HH\:mm\:ss'))]. Send-SplunkMessage failed to connect to '$CurrentSplunkUri' with the following error: '$($_ -replace '[\r\n]+', '; ')'"
                Write-Verbose -Message "This is the 'event' JSON we tried:`n$Json"
                # This makes it try another forwarder if a good one suddenly goes bad. Won't retry the formerly good one.
                # For that functionality I need a "once good forwarder cache" and it seems overkill for an obscure scenario?
                $GotGoodForwarder = $False
            }
        }
        Write-Verbose -Message "This is the 'event JSON' we tried:`n$Json"
        $ErrorActionPreference = "Continue"
    }

    End {
        # Do some house-keeping.
        if (Get-Variable -Name STSplunkWebClient -ErrorAction SilentlyContinue) {
            $STSplunkWebClient.Dispose()
            $STSplunkWebClient = $null
        }
        [System.GC]::Collect()
    }
}
function EscapeJson {
    param(
        [String] $String)
    # removed: #-replace '/', '\/' `
    # This is returned 
    $String -replace '\\', '\\' -replace '\n', '\n' `
        -replace '\u0008', '\b' -replace '\u000C', '\f' -replace '\r', '\r' `
        -replace '\t', '\t' -replace '"', '\"'
}

# Meant to be used as the "end value". Adding coercion of strings that match numerical formats
# supported by JSON as an optional, non-default feature (could actually be useful and save a lot of
# calculated properties with casts before passing..).
# If it's a number (or the parameter -CoerceNumberStrings is passed and it 
# can be "coerced" into one), it'll be returned as a string containing the number.
# If it's not a number, it'll be surrounded by double quotes as is the JSON requirement.
function GetNumberOrString {
    param(
        $InputObject)
    if ($InputObject -is [System.Byte] -or $InputObject -is [System.Int32] -or `
        ($env:PROCESSOR_ARCHITECTURE -imatch '^(?:amd64|ia64)$' -and $InputObject -is [System.Int64]) -or `
        $InputObject -is [System.Decimal] -or `
        ($InputObject -is [System.Double] -and -not [System.Double]::IsNaN($InputObject) -and -not [System.Double]::IsInfinity($InputObject)) -or `
        $InputObject -is [System.Single] -or $InputObject -is [long] -or `
        ($Script:CoerceNumberStrings -and $InputObject -match $Script:NumberRegex)) {
        Write-Verbose -Message "Got a number as end value."
        "$InputObject"
    }
    else {
        Write-Verbose -Message "Got a string (or 'NaN') as end value."
        """$(EscapeJson -String $InputObject)"""
    }
}

function ConvertToJsonInternal {
    param(
        $InputObject, # no type for a reason
        [Int32] $WhiteSpacePad = 0)
    
    [String] $Json = ""
    
    $Keys = @()
    
    Write-Verbose -Message "WhiteSpacePad: $WhiteSpacePad."
    
    if ($null -eq $InputObject) {
        Write-Verbose -Message "Got 'null' in `$InputObject in inner function"
        $null
    }
    
    elseif ($InputObject -is [Bool] -and $InputObject -eq $true) {
        Write-Verbose -Message "Got 'true' in `$InputObject in inner function"
        $true
    }
    
    elseif ($InputObject -is [Bool] -and $InputObject -eq $false) {
        Write-Verbose -Message "Got 'false' in `$InputObject in inner function"
        $false
    }
    
    elseif ($InputObject -is [DateTime] -and $Script:DateTimeAsISO8601) {
        Write-Verbose -Message "Got a DateTime and will format it as ISO 8601."
        """$($InputObject.ToString('yyyy\-MM\-ddTHH\:mm\:ss'))"""
    }
    
    elseif ($InputObject -is [HashTable]) {
        $Keys = @($InputObject.Keys)
        Write-Verbose -Message "Input object is a hash table (keys: $($Keys -join ', '))."
    }
    
    elseif ($InputObject.GetType().FullName -eq "System.Management.Automation.PSCustomObject") {
        $Keys = @(Get-Member -InputObject $InputObject -MemberType NoteProperty |
            Select-Object -ExpandProperty Name)

        Write-Verbose -Message "Input object is a custom PowerShell object (properties: $($Keys -join ', '))."
    }
    
    elseif ($InputObject.GetType().Name -match '\[\]|Array') {
        
        Write-Verbose -Message "Input object appears to be of a collection/array type. Building JSON for array input object."
        
        $Json += "[`n" + (($InputObject | ForEach-Object {
            
            if ($null -eq $_) {
                Write-Verbose -Message "Got null inside array."

                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + "null"
            }
            
            elseif ($_ -is [Bool] -and $_ -eq $true) {
                Write-Verbose -Message "Got 'true' inside array."

                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + "true"
            }
            
            elseif ($_ -is [Bool] -and $_ -eq $false) {
                Write-Verbose -Message "Got 'false' inside array."

                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + "false"
            }
            
            elseif ($_ -is [DateTime] -and $Script:DateTimeAsISO8601) {
                Write-Verbose -Message "Got a DateTime and will format it as ISO 8601."

                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$($_.ToString('yyyy\-MM\-ddTHH\:mm\:ss'))"""
            }
            
            elseif ($_ -is [HashTable] -or $_.GetType().FullName -eq "System.Management.Automation.PSCustomObject" -or $_.GetType().Name -match '\[\]|Array') {
                Write-Verbose -Message "Found array, hash table or custom PowerShell object inside array."

                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + (ConvertToJsonInternal -InputObject $_ -WhiteSpacePad ($WhiteSpacePad + 4)) -replace '\s*,\s*$'
            }
            
            else {
                Write-Verbose -Message "Got a number or string inside array."

                $TempJsonString = GetNumberOrString -InputObject $_
                " " * ((4 * ($WhiteSpacePad / 4)) + 4) + $TempJsonString
            }

        }) -join ",`n") + "`n$(" " * (4 * ($WhiteSpacePad / 4)))],`n"

    }
    else {
        Write-Verbose -Message "Input object is a single element (treated as string/number)."

        GetNumberOrString -InputObject $InputObject
    }
    if ($Keys.Count) {

        Write-Verbose -Message "Building JSON for hash table or custom PowerShell object."

        $Json += "{`n"

        foreach ($Key in $Keys) {

            # -is [PSCustomObject]) { # this was buggy with calculated properties, the value was thought to be PSCustomObject

            if ($null -eq $InputObject.$Key) {
                Write-Verbose -Message "Got null as `$InputObject.`$Key in inner hash or PS object."
                $Json += " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$Key"": null,`n"
            }

            elseif ($InputObject.$Key -is [Bool] -and $InputObject.$Key -eq $true) {
                Write-Verbose -Message "Got 'true' in `$InputObject.`$Key in inner hash or PS object."
                $Json += " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$Key"": true,`n"            }

            elseif ($InputObject.$Key -is [Bool] -and $InputObject.$Key -eq $false) {
                Write-Verbose -Message "Got 'false' in `$InputObject.`$Key in inner hash or PS object."
                $Json += " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$Key"": false,`n"
            }

            elseif ($InputObject.$Key -is [DateTime] -and $Script:DateTimeAsISO8601) {
                Write-Verbose -Message "Got a DateTime and will format it as ISO 8601."
                $Json += " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$Key"": ""$($InputObject.$Key.ToString('yyyy\-MM\-ddTHH\:mm\:ss'))"",`n"
                
            }

            elseif ($InputObject.$Key -is [HashTable] -or $InputObject.$Key.GetType().FullName -eq "System.Management.Automation.PSCustomObject") {
                Write-Verbose -Message "Input object's value for key '$Key' is a hash table or custom PowerShell object."
                $Json += " " * ($WhiteSpacePad + 4) + """$Key"":`n$(" " * ($WhiteSpacePad + 4))"
                $Json += ConvertToJsonInternal -InputObject $InputObject.$Key -WhiteSpacePad ($WhiteSpacePad + 4)
            }

            elseif ($InputObject.$Key.GetType().Name -match '\[\]|Array') {

                Write-Verbose -Message "Input object's value for key '$Key' has a type that appears to be a collection/array."
                Write-Verbose -Message "Building JSON for ${Key}'s array value."

                $Json += " " * ($WhiteSpacePad + 4) + """$Key"":`n$(" " * ((4 * ($WhiteSpacePad / 4)) + 4))[`n" + (($InputObject.$Key | ForEach-Object {

                    if ($null -eq $_) {
                        Write-Verbose -Message "Got null inside array inside inside array."
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + "null"
                    }

                    elseif ($_ -is [Bool] -and $_ -eq $true) {
                        Write-Verbose -Message "Got 'true' inside array inside inside array."
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + "true"
                    }

                    elseif ($_ -is [Bool] -and $_ -eq $false) {
                        Write-Verbose -Message "Got 'false' inside array inside inside array."
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + "false"
                    }

                    elseif ($_ -is [DateTime] -and $Script:DateTimeAsISO8601) {
                        Write-Verbose -Message "Got a DateTime and will format it as ISO 8601."
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + """$($_.ToString('yyyy\-MM\-ddTHH\:mm\:ss'))"""
                    }

                    elseif ($_ -is [HashTable] -or $_.GetType().FullName -eq "System.Management.Automation.PSCustomObject" `
                        -or $_.GetType().Name -match '\[\]|Array') {
                        Write-Verbose -Message "Found array, hash table or custom PowerShell object inside inside array."
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + (ConvertToJsonInternal -InputObject $_ -WhiteSpacePad ($WhiteSpacePad + 8)) -replace '\s*,\s*$'
                    }

                    else {
                        Write-Verbose -Message "Got a string or number inside inside array."
                        $TempJsonString = GetNumberOrString -InputObject $_
                        " " * ((4 * ($WhiteSpacePad / 4)) + 8) + $TempJsonString
                    }

                }) -join ",`n") + "`n$(" " * (4 * ($WhiteSpacePad / 4) + 4 ))],`n"

            }
            else {

                Write-Verbose -Message "Got a string inside inside hashtable or PSObject."
                # '\\(?!["/bfnrt]|u[0-9a-f]{4})'

                $TempJsonString = GetNumberOrString -InputObject $InputObject.$Key
                $Json += " " * ((4 * ($WhiteSpacePad / 4)) + 4) + """$Key"": $TempJsonString,`n"

            }

        }

        $Json = $Json -replace '\s*,$' # remove trailing comma that'll break syntax
        $Json += "`n" + " " * $WhiteSpacePad + "},`n"

    }

    $Json

}

function ConvertTo-STJson {
    [CmdletBinding()]
    #[OutputType([Void], [Bool], [String])]
    Param(
        [AllowNull()]
        [Parameter(Mandatory=$True,
                   ValueFromPipeline=$True,
                   ValueFromPipelineByPropertyName=$True)]
        $InputObject,
        [Switch] $Compress,
        [Switch] $CoerceNumberStrings = $False,
        [Switch] $DateTimeAsISO8601 = $False)
    Begin{

        $JsonOutput = ""
        $Collection = @()
        # Not optimal, but the easiest now.
        [Bool] $Script:CoerceNumberStrings = $CoerceNumberStrings
        [Bool] $Script:DateTimeAsISO8601 = $DateTimeAsISO8601
        [String] $Script:NumberRegex = '^-?\d+(?:(?:\.\d+)?(?:e[+\-]?\d+)?)?$'
        #$Script:NumberAndValueRegex = '^-?\d+(?:(?:\.\d+)?(?:e[+\-]?\d+)?)?$|^(?:true|false|null)$'

    }

    Process {

        # Hacking on pipeline support ...
        if ($_) {
            Write-Verbose -Message "Adding object to `$Collection. Type of object: $($_.GetType().FullName)."
            $Collection += $_
        }

    }

    End {
        
        if ($Collection.Count) {
            Write-Verbose -Message "Collection count: $($Collection.Count), type of first object: $($Collection[0].GetType().FullName)."
            $JsonOutput = ConvertToJsonInternal -InputObject ($Collection | ForEach-Object { $_ })
        }
        
        else {
            $JsonOutput = ConvertToJsonInternal -InputObject $InputObject
        }
        
        if ($null -eq $JsonOutput) {
            Write-Verbose -Message "Returning `$null."
            return $null # becomes an empty string :/
        }
        
        elseif ($JsonOutput -is [Bool] -and $JsonOutput -eq $true) {
            Write-Verbose -Message "Returning `$true."
            [Bool] $true # doesn't preserve bool type :/ but works for comparisons against $true
        }
        
        elseif ($JsonOutput-is [Bool] -and $JsonOutput -eq $false) {
            Write-Verbose -Message "Returning `$false."
            [Bool] $false # doesn't preserve bool type :/ but works for comparisons against $false
        }
        
        elseif ($Compress) {
            Write-Verbose -Message "Compress specified."
            (
                ($JsonOutput -split "\n" | Where-Object { $_ -match '\S' }) -join "`n" `
                    -replace '^\s*|\s*,\s*$' -replace '\ *\]\ *$', ']'
            ) -replace ( # these next lines compress ...
                '(?m)^\s*("(?:\\"|[^"])+"): ((?:"(?:\\"|[^"])+")|(?:null|true|false|(?:' + `
                    $Script:NumberRegex.Trim('^$') + `
                    ')))\s*(?<Comma>,)?\s*$'), "`${1}:`${2}`${Comma}`n" `
              -replace '(?m)^\s*|\s*\z|[\r\n]+'
        }
        
        else {
            ($JsonOutput -split "\n" | Where-Object { $_ -match '\S' }) -join "`n" `
                -replace '^\s*|\s*,\s*$' -replace '\ *\]\ *$', ']'
        }
    
    }

}

function Test-WebServerSSL {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $URL
	)
	
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    $req = [Net.HttpWebRequest]::Create($URL)
    $req.AllowAutoRedirect = $false
    try {$req.GetResponse() |Out-Null} catch {Write-Host Exception while checking URL $url`: $_ -f Red}
    $certName = $req.ServicePoint.Certificate.Subject.Split(', ',[System.StringSplitOptions]::RemoveEmptyEntries)[0].Split('=')[1]
    $certThumbprint = $req.ServicePoint.Certificate.GetCertHashString()
    Write-Host "CN is $certName"
    return $certName, $certThumbprint
}
Function Get-SerialPort {
    Param (
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
        $VM
    )
    Process {
        Foreach ($VMachine in $VM) {
            Foreach ($Device in $VMachine.ExtensionData.Config.Hardware.Device) {
                If ($Device.gettype().Name -eq "VirtualSerialPort"){
                    $Details = New-Object PsObject
                    $Details | Add-Member Noteproperty VM -Value $VMachine
                    $Details | Add-Member Noteproperty Name -Value $Device.DeviceInfo.Label
                    If ($Device.Backing.FileName) { $Details | Add-Member Noteproperty Filename -Value $Device.Backing.FileName }
                    If ($Device.Backing.Datastore) { $Details | Add-Member Noteproperty Datastore -Value $Device.Backing.Datastore }
                    If ($Device.Backing.DeviceName) { $Details | Add-Member Noteproperty DeviceName -Value $Device.Backing.DeviceName }
                    $Details | Add-Member Noteproperty Connected -Value $Device.Connectable.Connected
                    $Details | Add-Member Noteproperty StartConnected -Value $Device.Connectable.StartConnected
                    $Details
                }
            }
        }
    }
}
Function Get-ParallelPort {
    Param (
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
        $VM
    )
    Process {
        Foreach ($VMachine in $VM) {
            Foreach ($Device in $VMachine.ExtensionData.Config.Hardware.Device) {
                If ($Device.gettype().Name -eq "VirtualParallelPort"){
                    $Details = New-Object PsObject
                    $Details | Add-Member Noteproperty VM -Value $VMachine
                    $Details | Add-Member Noteproperty Name -Value $Device.DeviceInfo.Label
                    If ($Device.Backing.FileName) { $Details | Add-Member Noteproperty Filename -Value $Device.Backing.FileName }
                    If ($Device.Backing.Datastore) { $Details | Add-Member Noteproperty Datastore -Value $Device.Backing.Datastore }
                    If ($Device.Backing.DeviceName) { $Details | Add-Member Noteproperty DeviceName -Value $Device.Backing.DeviceName }
                    $Details | Add-Member Noteproperty Connected -Value $Device.Connectable.Connected
                    $Details | Add-Member Noteproperty StartConnected -Value $Device.Connectable.StartConnected
                    $Details
                }
            }
        }
    }
}


function writeToSplunk {
    [Switch] $splunkVerboseJSONCreation = $true
    [Switch] $splunkCoerceNumberStrings = $true
    [Switch] $splunkProxy = $false
    $settedTrue = $False
    $splunkInput = @{
        host = $hstName
        sourcetype = $splunkSourceType
        source = $splunkSource
        event = {
            date = $((Get-Date -Format 'MM-dd-yyyy HH:mm:ss'))
            message = ($hstName+'_'+$nam+','+$cisOut+","+$hstName)
        }
    }
    try {
        if (-not ($settedTrue)) {
            #Send-STSplunkMessage `
            #    -VerboseJSONCreation $splunkVerboseJSONCreation `
            #    -CoerceNumberStrings $splunkCoerceNumberStrings `
            #    -Proxy $splunkProxy `
            #    -SplunkUri ($splunkUri) `
            #    -SplunkHECToken $splunkHECToken `
            #    -SplunkIndex $splunkIndex `
            #    -SplunkSourceType $splunkSourceType `
            #    -SplunkSource $splunkSource `
            #    -InputObject $splunkInput
            #Write-Host ("-InputObject:"++" -SplunkUri:"+($splunkUri+":"+$curPort)+" -SplunkHECToken:"+$splunkHECToken+" -SplunkIndex:"+$splunkIndex+" -SplunkSourceType:"+$splunkSourceType+" -SplunkSource:"+$splunkSource+" -InputObject:"+$splunkInput+" -CoerceNumberStrings:"+$splunkCoerceNumberStrings+" -CoerceNumberStrings:"+$splunkCoerceNumberStrings)
            try {
                if ($hstParent.length -gt 0) {$target = ($hstName+"_"+$hstParent)}
            } catch {
                $target = ($hstName)
            }
            Write-Host -ForegroundColor Green ('Sent message to '+$splunkUri+'; '+($hstName+'_'+$nam+','+$cisOut+","+$hstName))
            #$splunkInput
            $settedTrue = $true; 
        } else {
            Write-Host -ForegroundColor Red ('Did NOT attempt to send '+$splunkUri+'; '+($hstName+'_'+$nam+','+$cisOut+","+$hstName))
            $settedTrue = $true;
        }
    } catch {
        Write-Host -ForegroundColor Yellow ('Escaped - '+$splunkUri+'; '+($hstName+'_'+$nam+','+$cisOut+","+$hstName))
    }
}
function getFunctions($_MyInvocation){
    $OutputParameter = @();
    foreach($BlockName in @("BeginBlock", "ProcessBlock", "EndBlock"))
    {
        $CurrentBlock = $_MyInvocation.MyCommand.ScriptBlock.Ast.$BlockName;
        foreach($Statement in $CurrentBlock.Statements)
        {
            $Extent = $Statement.Extent.ToString();
            if(::IsNullOrWhiteSpace($Statement.Name) -Or $Extent -inotmatch ('function\W+(?<name>{0})' -f $Statement.Name))
            {
                continue;
            }
            $OutputParameter += $Statement.Name;
        }
    }
    return $OutputParameter;
}

function evLogEnv($logName,$sourceName) {
    $ErrorActionPreference = 'SilentlyContinue';
    if (-not (get-eventLog -LogName $logName | Where-Object {$_.name -like ('*'+$sourceName+'*')})) {
        $params = @{
            LogName = $logName 
            Source = $sourceName
        }
        New-EventLog @params -Verbose
    }
}

function write-ToEventLog($logName,$sourceName,$entryType,$evID,$curMessage) {
    $ErrorActionPreference = 'SilentlyContinue';
    $params = @{
        LogName = $logName
        Source = $sourceName
        EntryType = $entryType
        EventId = $evID
        Message = $curMessage
    }
    Write-EventLog @params
}
function checkPAM() {
    $cisID = '1.0'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "1.0 Ensure Privileged Access Management Agent is Installed and Active";
    $curMessage = ($hstName+"_"+$hstParent+" # CIS - "+$cisID+" : "+$cisOut+" - ESXi Hosts do not have Internet Accesses.")
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}

function cis11() {
    $cisID = '1.1'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "1.1 (L1) Ensure ESXi is properly patched (Scored)";
    $curMessage = ($hstName+"_"+$hstParent+" # CIS - "+$cisID+" : "+$cisOut+" - Manual Review/Reconciliation / Employ a process to keep ESXi hosts up to date with patches in accordance with industry standards and internal guidelines. Leverage the VMware Update Manager to test and apply patches as they become available.")
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    (Get-VMHost -Name $VMHost.Name | Get-EsxCli).software.vib.list() | Group-Object InstallDate | Sort-Object InstallDate -Descending
}
function cis12() {
    Write-Host "1.2 (L1) Ensure the Image Profile VIB acceptance level is configured properly (Scored)"; 
    # List only the vibs which are not at "VMwareCertified" or "VMwareAccepted" or "PartnerSupported" acceptance level
    try {
        $software = (Get-EsxCli -VMHost $VMHost.Name).software.vib.list() | Where { ($_.AcceptanceLevel -ne "VMwareCertified") -and ($_.AcceptanceLevel -ne "VMwareAccepted") -and ($_.AcceptanceLevel -ne "PartnerSupported") }
    } catch {
        $software = '000'
    } 

    if ($software -ne $null -and $software -ne '000') {
        $cisID = '1.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '1.2'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis13() {
    Write-Host "1.3 (L1) Ensure no unauthorized kernel modules are loaded on the host (Scored)";  
    (Get-EsxCli -VMHost $VMHost.Name).system.module.list() | ForEach-Object {
        if ($_.SignedStatus -notlike '*nsig*') {
            $cisID = '1.3'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = (($VMHost.Name)+"_Module: "+$_.name+"("+$_.isenabled+"/"+$_.isloaded+") # CIS "+$cisID+" : "+$cisOut)
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '1.3'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = (($VMHost.Name)+"_Module: "+$_.name+"("+$_.isenabled+"/"+$_.isloaded+") # CIS "+$cisID+" : "+$cisOut)
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    } 
}
function cis14() {
    Write-Host "1.4 (L2) Ensure the default value of individual salt per vm is configured (Automated) ";  
    if ((Get-VMHost -Name $VMHost | Get-AdvancedSetting -Name Mem.ShareForceSalting | select -ExpandProperty value) -ne 2) {
        $cisID = '1.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '1.4'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis21() {
    Write-Host "2.1 (L1) Ensure NTP time synchronization is configured properly (Scored)";  
    $cisID = '2.1'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
    Get-VMHost -Name $VMHost.Name | Get-VMHostService | Where-Object {$_.key -eq "ntpd"} | Select-Object VMHost, Label, Key, Policy, Running, Required
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis22() {
    Write-Host "2.2 (L1) Ensure the ESXi host firewall is configured to restrict access to services running on the host (Scored)"; 
    # List the services which are enabled and do not have rules defined for specific IP ranges to access the service
    $fwrules = Get-VMHostFirewallException -VMHost $VMHost.Name | Where-Object {$_.Enabled -and ($_.ExtensionData.AllowedHosts.AllIP)}
    if (($fwrules).count -gt 0) {
        $cisID = '2.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            $fwrules
    } else {
        $cisID = '2.2'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis23() {
    Write-Host "2.3 (L1) Ensure Managed Object Browser (MOB) is disabled (Scored)";  
    # Check for MOB on hosts 
    if (-not ((Get-AdvancedSetting -Entity $VMHost.Name -Name Config.HostAgent.plugins.solo.enableMob | select -ExpandProperty value) -eq $false)) {
        Get-AdvancedSetting -Entity $VMHost.Name -Name Config.HostAgent.plugins.solo.enableMob
        $cisID = '2.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '2.3'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis24() {
    Write-Host "2.4 (L1) Ensure default self-signed certificate for ESXi communication is not used (Scored)"; 
    $certmgr = Get-View -Id $VMHOST.ExtensionData.ConfigManager.CertificateManager
    $certObject = New-Object -TypeName PSObject -Property ([ordered]@{
        VMHost = $esx.Name
        CertIssuer = $certMgr.CertificateInfo.Issuer
        CertSubject = $certMgr.CertificateInfo.Subject
        CertExpiration = $certMgr.CertificateInfo.NotAfter
        CertStatus = $certMgr.CertificateInfo.Status
    })
    if ($certObject.CertIssuer -like '*=VMware*' -or $certObject.Issuer -like '*DC=vsphere*') {
        $cisID = '2.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '2.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis25() {
    Write-Host "2.5 (L1) Ensure SNMP is configured properly (Not Scored)";  
    if ((Get-VMHostSnmp).legnth -lt 1) {
        $cisID = '2.5'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '2.5'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis26() {
    Write-Host "2.6 (L1) Ensure dvfilter API is not configured if not used (Scored)";  
    if (($VMHost | Get-AdvancedSetting Net.DVFilterBindIpAddress).value -ne '') {
        $cisID = '2.6'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '2.6'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis27() {
    Write-Host "2.7 (L1) Ensure expired and revoked SSL certificates are removed from the ESXi server (Not Scored)"; 
    $cisID = '2.7'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    $certData = Get-View -Id $VMHOST.ExtensionData.ConfigManager.CertificateManager | fl 
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    $certData
}
function cis28() {
    Write-Host "2.8 (L1) Ensure vSphere Authentication Proxy is used when adding hosts to Active Directory (Scored)";  
    (Get-VMHostAuthentication | Where-Object {$_.VMHost -like ('*'+$hstName+'*')} | fl ) | ForEach-Object {
            $hostDomain = $_.Domain; 
            $hstName = $_.VMHost; 
            if (-not ($hostDomain -like '')) {
                $cisID = '2.8'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($hstName+" # CIS "+$cisID+" : "+$cisOut)
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            } else {
                $cisID = '2.8'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($hstName+" # CIS "+$cisID+" : "+$cisOut)
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            }
    }
}
function cis29() {
    Write-Host "2.9 (L1) Ensure VDS health check is disabled (Scored)";  
    if ($null -ne (Get-VDSwitch -VMHost $VMHost.Name).ExtensionData.Config.HealthCheckConfig) { 
        $cisID = '2.9'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '2.9'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis31() {
    Write-Host "3.1 (L1) Ensure a centralized location is configured to collect ESXi host core dumps (Scored)";  
    if (((Get-EsxCli -VMHost $VMHost).system.coredump.network.get() | select -ExpandProperty Enabled) -eq 'false') {
        $cisID = '3.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '3.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis32() {
    Write-Host "3.2 (L1) Ensure persistent logging is configured for all ESXi hosts (Scored)"; 
    if ((Get-AdvancedSetting -Entity $VMHost.Name -name Syslog.global.logDir).value -like '*scratch*') {
        $cisID = '3.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '3.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }   
}
function cis33() {
    Write-Host "3.3 (L1) Ensure remote logging is configured for ESXi hosts (Scored)";
    # List Syslog.global.logHost for each host
    if ($null -eq (Get-AdvancedSetting -Entity $VMHost.Name Syslog.global.logHost)) {
        $cisID = '3.3'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '3.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis41() {
    Write-Host "4.1 (L1) Ensure a non-root user account exists for local admin access (Scored)";  
    if ((Get-VIAccount $VMHost.Name | Where-Object {$_.Domain -eq $null -and $_.Name -ne 'root'}).count -eq 0) {
        $cisID = '4.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '4.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis42() {
    Write-Host "4.2 (L1) Ensure passwords are required to be complex (Scored)";  
    $base = (Get-VMHost -Name $VMHost.Name | Get-AdvancedSetting -Name 'Security.PasswordQualityControl' | select -expa value).Split("=")
    $n = [float]($base[1]).Split(" ")[0] # -le 5
    $n0 = ($base[2]).Split(",")[0]
    $n1 = ($base[2]).Split(",")[1]
    $n2 = ($base[2]).Split(",")[2]
    $n3 = ($base[2]).Split(",")[3]
    $n4 = ($base[2]).Split(",")[4]
    if ( $n -gt 5 -or $n0 -ne 'disabled' -or $n1 -ne 'disabled' -or $n2 -ne 'disabled' -or $n3 -ne 'disabled' -or $n4 -lt 14) {
        $cisID = '4.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+"/ Audit:
        To confirm password complexity requirements are set, perform the following:
            1. Login to the ESXi shell as a user with administrator privileges.
            2. Open /etc/pam.d/passwd.
            3. Locate the following line:
            4. Confirm N is less than or equal to 5.
            5. Confirm N0 is set to disabled.
            6. Confirm N1 is set to disabled.
            7. Confirm N2 is set to disabled.
            8. Confirm N3 is set to disabled.
            9. Confirm N4 is set to 14 or greater.")
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        $base
    } else {
        $cisID = '4.2'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }

}

function cis45() {
    Write-Host "4.5 (L1) Ensure previous 5 passwords are prohibited (Manual)";    
    $lockOuts = Get-VMHost -Name $VMHost.Name | Get-AdvancedSetting Security.PasswordHistory | select -expa Value
    if ($lockOuts -gt 5) {
        $cisID = '4.5'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '4.5'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
    $curMessage = ($hstName+"_"+$hstParent+" To verify the password history is set to 5, perform the following:
    1. From the vSphere Web Client, select the host.
    2. Click Configure then expand System.
    3. Select Advanced System Settings then click Edit.
    4. Enter Security.PasswordHistory in the filter.
    5. Verify that the value for this parameter is set to 5.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis43() {
    Write-Host "4.3 (L1) Ensure the maximum failed login attempts is set to 5 (Automated)";  
    # List Syslog.global.logHost for each host
    $lockOuts = Get-AdvancedSetting -Entity $VMHost.Name -Name Security.AccountLockFailures | select -expa Value
    if ($lockOuts -gt 5) {
        $cisID = '4.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '4.3'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis44() {
    Write-Host "4.4 (L1) Ensure account lockout is set to 15 minutes (Automated)";  
    $UnlockTime = "900"
    # List Syslog.global.logHost for each host
    $hostValue = Get-AdvancedSetting -Entity $VMHost.Name -Name Security.AccountUnlockTime | select Entity, Value #Format-List -property * # 
    if ($UnlockTime -lt $hostValue.Value) {
        $cisID = '4.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '4.4'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis51() {
    Write-Host "5.1 (L1) Ensure the DCUI timeout is set to 600 seconds or less (Scored)";  
    $DcuiTimeOut = "600"
    $hostValue = '9099999999'
    # List Syslog.global.logHost for each host
    $hostValue = Get-AdvancedSetting -Entity $VMHost.Name -Name UserVars.DcuiTimeOut | select Entity, Value #Format-List -property * # 
    if ($DcuiTimeOut -lt $hostValue.Value) {
        $cisID = '5.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '5.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis52() {
    Write-Host "5.2 (L2) Ensure DCUI is disabled (Scored)";  
    $hostValue = Get-VMHostService -VMHost $VMHost.Name | Where-Object { $_.key -eq "DCUI" } | select -ExpandProperty Running
    if ($hostValue -eq $true) {
        $cisID = '5.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '5.2'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis53() {
    Write-Host "5.3 (L1) Ensure the ESXi shell is disabled (Scored)";  
    # Check if the ESXi shell is running and set to start
    $hostValue = Get-VMHostService -VMHost $VMHost.Name | Where { $_.key -eq "TSM" } | select -expa Running  #| Select VMHost, Key, Label, Policy, Running, Required
    if ($hostValue -eq $true) {
        $cisID = '5.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '5.3'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis54() {
    Write-Host "5.4 (L1) Ensure SSH is disabled (Scored)";  
    # Check if the ESXi shell is running and set to start
    if (Get-VMHost -Name $VMHost.Name | Get-VMHostService | Where { $_.key -eq "TSM-SSH" } | Select -expa Running) {
        $cisID = '5.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    } else {
        $cisID = '5.4'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis55() {
    $cisID = '5.5'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "5.5 (L1) Ensure CIM access is limited (Not Scored)";
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" Cannot Verify / Cannot perform via vCenter / Get-VMHostAccount")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');;
}
function cis56() {
    Write-Host "5.6 (L1) Ensure Lockdown mode is enabled (Scored)";  
    # To check if Lockdown mode is enabled
    $hostValue = Get-VMHost -Name $VMHost.Name | Select Name,@{N="Lockdown";E={$_.Extensiondata.Config.adminDisabled}}
    if ($hostValue.Lockdown -eq $false) {
        $cisID = '5.6'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '5.6'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis57() {
    Write-Host "5.7 (L2) Ensure the SSH authorized_keys file is empty (Scored)";  
    $cisID = '5.7'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    $pLinkCommand = 'cat /etc/ssh/keys-root/authorized_keys'
    #$pLink $VMHOST.name -l $env:VI_USERNAME $env:VI_PASSWORD $pLinkCommand
###
    $curMessage = ($hstName+"_"+$hstParent+" # CIS - 5.7 : Cannot Verify / Audit:
        To verify the authorized_keys file does not contain any keys, perform the following:
        1. Logon to the ESXi shell as root or another admin user.
        2. Verify the /etc/ssh/keys-root/authorized_keys file is empty.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis58() {
    Write-Host "5.8 (L1) Ensure idle ESXi shell and SSH sessions time out after 300 seconds or less (Scored)"; 
    Get-VMHost -Name $VMHost.Name | ForEach-Object { 
        $hostValue = Get-AdvancedSetting -Entity $VMHost.Name -name UserVars.ESXiShellInteractiveTimeOut | select -expa Value #Format-List -property * # 
        if ($hostValue -eq 0 -or $hostValue -gt 300) {
            $cisID = '5.8'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '5.8'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    }
}
function cis59() {
    Write-Host "5.9 (L1) Ensure the shell services timeout is set to 1 hour or less (Scored)";  
    $VAR = 3600
    $Setting = 'UserVars.ESXiShellTimeOut'
    Get-VMHost -name $VMHOST.name | ForEach-Object { 
        $hostValue = Get-AdvancedSetting -Entity $_ -name:$Setting  | select -expa Value #Format-List -property * # 
        if ($hostValue -eq 0 -or $hostValue -gt 3600) {
            $cisID = '5.9'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '5.9'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    }
}
function cis510() {
    Write-Host "5.10 (L1) Ensure DCUI has a trusted users list for lockdown mode (Not Scored)";  
    $Value = 'root'
    $Setting = 'DCUI.Access'
    # List UserVars.ESXiShellInteractiveTimeOut for each host
    #Get-VMHost | Select Name, @{N="Syslog.global.logHost";E={$_ | Get-AdvancedSetting Syslog.global.logHost}} | Out-Host
    Get-VMHost -Name $VMHost.Name | ForEach-Object { 
        $hostValue = Get-AdvancedSetting -Entity $_ -name:$Setting  | select -ExpandProperty Value #Format-List -property * # 
        if ($hostValue -ne $Value) {
            $cisID = '5.10'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '5.10'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    }
}
function cis511() {
    $cisID = '5.11'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "5.11 (L2) Ensure contents of exposed configuration files have not been modified (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+"/ Cannot Verify / Audit:
        To verify the exposed configuration files have not been modified, perform the following:
        1. Open a web browser.
        2. Find the ESXi configuration files by browsing to https:///host (not available if MOB
        is disabled).
        3. Review the contents of those files to confirm no unauthorized modifications have
        been made.
        NOTE: Not all the files listed are modifiable.
        Alternately, the configuration files can also be retrieved using the vCLI or PowerCLI.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis61() {
    Write-Host "6.1 (L1) Ensure bidirectional CHAP authentication for iSCSI traffic is enabled (Scored)";  
    # List Iscsi Initiator and CHAP Name if defined
    $data = Get-VMHost -Name $VMHost.Name | Get-VMHostHba | Where {$_.Type -eq "Iscsi"} | Select VMHost, Device, ChapType, @{N="CHAPName";E={$_.AuthenticationProperties.ChapName}} 
    if ($data.ChapName -eq $null) {
        $cisID = '6.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '6.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis62() {
    #$data = Get-VMHost | Get-VMHostHba | Where {$_.Type -eq "Iscsi"} | Select VMHost, Device, ChapType, @{N="CHAPName";E={$_.AuthenticationProperties.ChapName}}
    Write-Host "6.2 (L1) Ensure the uniqueness of CHAP authentication secrets for iSCSI traffic (Not Scored)";
    $setIfExternallyManaged = 0; 
    if ($setIfExternallyManaged -ne 1) {   
        $cisID = '6.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / Please review/reconcile manually per VMware Documentation.")
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    } else {
        $cisID = '6.2'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / Per Internal Process Designation; please review/reconcile appropriately.")
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis63() {
    $cisID = '6.3'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "6.3 (L1) Ensure storage area network (SAN) resources are segregated properly (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / Cannot Verify Audit:
        The audit procedures to verify SAN activity is properly segregated are SAN vendor or product-specific.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis64() {
    $cisID = '6.4'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "6.4 (L2) Ensure VMDK files are zeroed out prior to deletion (Not Scored)"; 
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / Cannot Verify / Below Process should be part of VM Destroy Procedure  
        When deleting a VMDK file with sensitive data:
        1. Shut down or stop the virtual machine.
        2. Issue the CLI command 'vmkfstools --writezeroes' on that file prior to deleting it
        from the datastore.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis71() {
    # CIS 7.1-3
    $Value = 'root'
    $Setting = 'DCUI.Access'
    $Expected = "Checking for CIS_7.1 - 7.3
    Expected: 
    ForgedTransmits : Reject (7.1)
    MacChanges      : Reject (7.2)
    PromiscuousMode : Reject (7.3)
    "
    
    # List all vSwitches and their Security Settings 
    Get-VirtualSwitch -VMHost $VMHOST.name | Select VMHost, Name, `
    @{N="ForgedTransmits";E={if ($_.ExtensionData.Spec.Policy.Security.ForgedTransmits) { "Accept" } Else { "Reject"} }}, `
    @{N="MacChanges";E={if ($_.ExtensionData.Spec.Policy.Security.MacChanges) { "Accept" } Else { "Reject"} }}, `
    @{N="PromiscuousMode";E={if ($_.ExtensionData.Spec.Policy.Security.PromiscuousMode) { "Accept" } Else { "Reject"} }} | ForEach-Object {
        if ($_.ForgedTransmits -notlike '*Reject*') {
            $cisID = '7.1'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.1 (L1) Ensure the vSwitch Forged Transmits policy is set to reject (Scored)";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '7.1'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.1 (L1) Ensure the vSwitch Forged Transmits policy is set to reject (Scored)";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }

        if ($_.MacChanges -notlike '*Reject*') {
            $cisID = '7.2'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.2 (L1) Ensure the vSwitch MAC Address Change policy is set to reject (Scored) ";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '7.2'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.2 (L1) Ensure the vSwitch MAC Address Change policy is set to reject (Scored) ";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }

        if ($_.PromiscuousMode -notlike '*Reject*') {
            $cisID = '7.3'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.3 (L1) Ensure the vSwitch Promiscuous Mode policy is set to reject (Scored)";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '7.3'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            Write-Host "7.3 (L1) Ensure the vSwitch Promiscuous Mode policy is set to reject (Scored)";  
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    }
}
function cis76() {
    $Expected = "Checking for CIS_7.4 - 7.6
    Expected: 
    VLanID != 1              (7.4)
    VLanID != 1001-1024,4094 (7.5)
    VLanID != 3968-4047,4094 (7.5)
    VLanID != 4095           (7.6)
    "
    # List all vSwitches, their Portgroups and VLAN IDs 
    Get-VirtualPortGroup -Standard -VMHost $VMHost.Name | ForEach-Object {
        Write-Host "7.4 (L1) Ensure port groups are not configured to the value of the native VLAN (Scored)";  
        if ($_.VLanID -like '*1*') {
            $cisID = '7.4'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+"/ VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        } else {
            $cisID = '7.4'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
            if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            
        }
        Write-Host "7.5 (L1) Ensure port groups are not configured to VLAN values reserved by upstream physical switches (Not Scored)";  
        if ($_.VLanID -eq '1001-1024,4094') {
            $cisID = '7.5'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
            if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            
        } elseif ($_.VLanID -eq '3968-4047,4094') {
            $cisID = '7.5'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
            if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            
        } else {
            $cisID = '7.5'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
            if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            
        }
        Write-Host "7.6 (L1) Ensure port groups are not configured to VLAN 4095 except for Virtual Guest Tagging (VGT) (Scored)";  
        if ($_.VLanID -eq '4095') {
            $cisID = '7.6'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
            if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
            
        } else {
            $cisID = '7.6'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+"  / VLAN: "+$_.VLanID)
            
            write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
        }
    }
}
function cis77() {
    Write-Host "7.7 (L1) Ensure Virtual Disributed Switch Netflow traffic is sent to an authorized collector (Scored)";  
    $VAR = 3600
    $Setting = 'UserVars.ESXiShellTimeOut'
    #Get-VDPortgroup | Select Name, VirtualSwitch, @{Name="NetflowEnabled";Expression={$_.Extensiondata.Config.defaultPortConfig.ipfixEnabled.Value}} | Where-Object {$_.NetflowEnabled -eq "True"} | Out-Host
    Get-VM -Name $VMHost.Name | ForEach-Object { 
        $cisID = '7.7'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        Get-VDPortgroup | Select Name, VDSwitch, @{Name="NetflowEnabled";Expression={$_.Extensiondata.Config.defaultPortConfig.ipfixEnabled.Value}} | Where-Object {$_.NetflowEnabled -eq "True"} | Out-Host
        $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis78() {
    Write-Host "7.8 (L1) Ensure port-level configuration overrides are disabled. (Scored)";
    $Expected = "Checking for CIS_7.4 - 7.6
        Expected: 
        Block           : True
        TrafficShaping  : False
        Security        : False
        Vlan            : False
        UplinkTeaming   : False (Except iSCSI. LACP considerations)
        ResetPortConfig : True
        "
        $portGroups = Get-VDPortgroup | Get-VDPortgroupOverridePolicy 
        foreach ($i in $portGroups) {
            $blockedOverrideAllowed = $i.BlockOverrideAllowed
            $trafficShaping = $i.TrafficShaping 
            $securityDataPoint = $i.Security 
            $vlanOverrideAllowed = $i.VlanOverrideAllowed 
            $resetPortConfig = $i.ResetPortConfig 
            $vdPortGroup = $i.VDPortgroup
            if (
                ($blockedOverrideAllowed -ne $true) -or ($trafficShaping -ne $false) -or ($securityDataPoint -ne $false) -or ($vlanOverrideAllowed -ne $false) -or ($resetPortConfig -ne $true)
            ) {
                $cisID = '7.8'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($VMHOST.name + " / " + $vdPortGroup+"_ # CIS "+$cisID+" : "+$cisOut)
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '7.8'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($VMHOST.name + " / " + $vdPortGroup+"_ # CIS "+$cisID+" : "+$cisOut)
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
}
function cis811() {
    Write-Host "8.1.1 (L1) Ensure informational messages from the VM to the VMX file are limited (Scored)";  
    $Value = 1048576
    $Setting = 'tools.setInfo.sizeLimit'
    $cur = Get-AdvancedSetting -Entity $VMHOST.name -name:$Setting  | select -expa Value #Format-List -property * # 
    if ($cur -ne $Value) {
        $cisID = '8.1.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -EventId '0111' -Message $curMessage           
    } else {
        $cisID = '8.1.1'
        $cisOut = 'PASS'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -EventId '0111' -Message $curMessage           
    } 
}
function cis812() {
    Write-Host "8.1.2 (L2) Ensure only one remote console connection is permitted to a VM at any time (Scored)";
    Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
        try {
            $curDataPoint = Get-AdvancedSetting -Name "RemoteDisplay.maxConnections" $_ | Select -expa Value
            $curDataPoint
            if ($curDataPoint -gt 1) {
                $cisID = '8.1.2'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.1.2'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } catch {
            $cisID = '8.1.2'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        }
    }   
}
function cis821() {
    Write-Host "8.2.1 (L1) Ensure unnecessary floppy devices are disconnected (Scored)";  
    $Expected = "Expected: Floppy drive 1 " 
    try {    
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
                if ((Get-FloppyDrive -VM $_ | Select -expa ConnectionState) -notlike '*NotConnected, GuestControl, NoStartConnected*') {
                    $cisID = '8.2.1'
                    $cisOut = 'REVIEW'
                    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                    $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);    
                    write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
                } else {
                    $cisID = '8.2.1'
                    $cisOut = 'PASS'
                    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                    $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);    
                    write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
                }
        }       
    } catch {
        $cisID = '8.2.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
    }
}
function cis822() {
    Write-Host "8.2.2 (L2) Ensure unnecessary CD/DVD devices are disconnected (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ((Get-CDDrive -VM $_ | select -expa ConnectionState) -notlike '*NotConnected, GuestControl, NoStartConnected*') {
                $cisID = '8.2.2'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.2.2'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.2.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
    }
}
function cis823() {
    Write-Host "8.2.3 (L1) Ensure unnecessary parallel ports are disconnected (Scored) ";
    try {    
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ((Get-ParallelPort -VM $_ | select -expa ConnectionState) -notlike '*NotConnected, GuestControl, NoStartConnected*') {
                $cisID = '8.2.3'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.3'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }
        }
    } catch {
        $cisID = '8.2.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                     
    }
}
function cis824() {
    Write-host "8.2.4 (L1) Ensure unnecessary serial ports are disconnected (Scored)"
    try {    
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ((Get-SerialPort -VM $_ | select -expa ConnectionState) -notlike '*NotConnected, GuestControl, NoStartConnected*') {
                $cisID = '8.2.4'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.4'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }
        }
    } catch {
        $cisID = '8.2.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis825() {
    Write-Host "8.2.5 (L1) Ensure unnecessary USB devices are disconnected (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ((Get-USBDevice -VM $_ | select -expa ConnectionState) -notlike '*NotConnected, GuestControl, NoStartConnected*') {
                $cisID = '8.2.5'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.5'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }
        }
    } catch {
        $cisID = '8.2.5'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis826() {
    Write-Host "8.2.6 (L1) Ensure unauthorized modification and disconnection of devices is disabled (Scored)";
    $Setting = 'isolation.device.edit.disable'
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $true) -or ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $null) ) {
                $cisID = '8.2.6'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.6'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }
        }
    } catch {
        $cisID = '8.2.6'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis827() {
    Write-Host "8.2.7 (L1) Ensure unauthorized connection of devices is disabled (Scored)";
    $Value = $true
    $Setting = 'isolation.device.connectable.disable'
    try {    
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $true) -or ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $null) ) {
                $cisID = '8.2.7'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.7'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }
        }
    } catch {
        $cisID = '8.2.7'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis828() {
    Write-Host "8.2.8 (L1) Ensure PCI and PCIe device passthrough is disabled (Scored)";
    $Value = ""
    $Setting = 'pciPassthru*.present'
    try {       
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $true) -or ((Get-AdvancedSetting -Entity $_ -name:$Setting | select -expa Value) -eq $null) ) {
                $cisID = '8.2.8'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
            } else {
                $cisID = '8.2.8'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                   
            }   
        }
    } catch {
        $cisID = '8.2.8'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis831() {
    $cisID = '8.3.1'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "8.3.1 (L1) Ensure unnecessary or superfluous functions inside VMs are disabled (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS - 8.3.1 : Cannot Verify - Manual Audit
        1. Disable unused services in the operating system.
        2. Disconnect unused physical devices, such as CD/DVD drives, floppy drives, and USB
        adaptors.
        3. Turn off any screen savers.
        4. If using a Linux, BSD, or Solaris guest operating system, do not run the X Windows
        system unless it is necessary.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis832() {
    $cisID = '8.3.2'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    
    Write-Host "8.3.2 (L1) Ensure use of the VM console is limited (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" - Manual Audit:
        To verify use of the VM console is properly limited, perform the following steps:
        1. From the vSphere Client, select an object in the inventory.
        2. Click the Permissions tab to view the user and role pair assignments for that object.
        3. Next, navigate to vCenter --> Administration --> Roles.
        4. Select the role in question and choose Edit to see which effective privileges are
        enabled.
        5. Verify that only authorized users have a role which allows them a privilege under
        the Virtual Machine section of the role editor.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis833() {
    $cisID = '8.3.3'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "8.3.3 (L1) Ensure secure protocols are used for virtual serial port access (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" - Audit:
        To verify that all virtual serial ports use secure protocols, check that all configured protocols are from this list:
         ssl - the equivalent of TCP+SSL
         tcp+ssl - SSL over TCP over IPv4 or IPv6
         tcp4+ssl - SSL over TCP over IPv4
         tcp6+ssl - SSL over TCP over IPv6
         telnets - telnet over SSL over TCP")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
}
function cis834() {
    $cisID = '8.3.4'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "8.3.4 (L1) Ensure templates are used whenever possible to deploy VMs (Not Scored)";  
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" - Audit:
        To verify that templates are used whenever possible to deploy VMs, 
        confirm that such templates exist, the templates are properly configured, 
        and standard procedures and processes use the templates when appropriate.")
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
} 
function cis841() {
    Write-Host "8.4.1 (L1) Ensure access to VMs through the dvfilter network APIs is configured correctly (Not Scored)";
    Get-VMHost $VMHOST.name | ForEach-Object { 
        $cur = Get-AdvancedSetting -Entity $_ -name:'Net.DVFilterBindIpAddress'  | select Entity, Value #Format-List -property * # 
        if ($cur.Value -ne '') {
            $cisID = '8.4.1'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
        } else {
            $cisID = '8.4.1'
            $cisOut = 'PASS'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
        } 
    }
}
function cis842() {
    Write-Host "8.4.2 (L1) Ensure VMsafe Agent Address is configured correctly (Not Scored)";
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:'vmsafe.agentAddress' | select -expa Value) -ne '') {
                $cisID = '8.4.2'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                               
            } else {
                $cisID = '8.4.2'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                 
            }
        }
    } catch {
        $cisID = '8.4.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS - 8.7.4 : "+$message)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis843() {
    Write-Host "8.4.3 (L1) Ensure VMsafe Agent Port is configured correctly (Not Scored)";
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:'vmsafe.agentPort' | select -expa Value) -ne $null) {
                $cisID = '8.4.3'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                               
            } else {
                $cisID = '8.4.3'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                 
            }
        }
    } catch {
        $cisID = '8.4.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    }
}
function cis844() {
    Write-Host "8.4.4 (L1) Ensure VMsafe Agent is configured correctly (Not Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:'vmsafe.enable' | select -expa Value) -ne $null) {
                $cisID = '8.4.4'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                ;                
            } else {
                $cisID = '8.4.4'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                 
            }
        }
    } catch {
        $cisID = '8.4.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                             
    } 
}
function cis845() {
    Write-Host "8.4.5 (L2) Ensure Autologon is disabled (Scored)"; 
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.ghi.autologon.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.5'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.5'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.4.5'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis846() {
    Write-Host "8.4.6 (L2) Ensure BIOS BBS is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.bios.bbs.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.6'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.6'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.4.6'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis847() {
    Write-Host "8.4.7 (L2) Ensure Guest Host Interaction Protocol Handler is set to disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.ghi.protocolhandler.info.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.7'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.7'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.4.7'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis848() {
    Write-Host "8.4.8 (L2) Ensure Unity Taskbar is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unity.taskbar.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.8'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.8'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.4.8'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis849() {
    Write-Host "8.4.9 (L2) Ensure Unity Active is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unityActive.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.9'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.9'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.9'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8410() {
    Write-Host "8.4.10 (L2) Ensure Unity Window Contents is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unity.windowContents.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.10'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.10'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.10'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8411() {
    Write-Host "8.4.11 (L2) Ensure Unity Push Update is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unity.push.update.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.11'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.11'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.11'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8412() {
    Write-Host "8.4.12 (L2) Ensure Drag and Drop Version Get is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.vmxDnDVersionGet.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.12'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.12'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.12'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8413() {
    Write-Host "8.4.13 (L2) Ensure Drag and Drop Version Set is disabled (Scored)";  
    try {   
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.guestDnDVersionSet.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.13'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);$compliance  = $compliance + $curMessage
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.13'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);$compliance  = $compliance + $curMessage
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.13'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        $compliance  = $compliance + $curMessage
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8414() {
    Write-Host "8.4.14 (L2) Ensure Shell Action is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.ghi.host.shellAction.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.14'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.14'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.14'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8415() {
    Write-Host "8.4.15 (L2) Ensure Request Disk Topology is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.dispTopoRequest.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.15'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.15'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.15'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8416() {
    Write-Host "8.4.16 (L2) Ensure Trash Folder State is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.trashFolderState.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.16'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
                #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -Category 'Information' -EventId '0111' -Message $curMessage -Verbose
            } else {
                $cisID = '8.4.16'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
                #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -Category 'Information' -EventId '0111' -Message $curMessage -Verbose
            }
        } 
    } catch {
        $cisID = '8.4.16'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -Category 'Information' -EventId '0111' -Message $curMessage -Verbose
    }
}
function cis8417() {
    Write-Host "8.4.17 (L2) Ensure Guest Host Interaction Tray Icon is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.ghi.trayicon.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.17'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.17'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.17'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8418() {
    Write-Host "8.4.18 (L2) Ensure Unity is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unity.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.18'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.4.18'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        } 
    } catch {
        $cisID = '8.4.18'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
    }
}
function cis8419() {
    Write-Host "8.4.19 (L2) Ensure Unity Interlock is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.unityInterlockOperation.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.19'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.4.19'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        } 
    } catch {
        $cisID = '8.4.19'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8420() {
    Write-Host "8.4.20 (L2) Ensure GetCreds is disabled (Scored)";  
    try {    
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.getCreds.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.20'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.4.20'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        } 
    } catch {
        $cisID = '8.4.20'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8421() {
    Write-Host "8.4.21 (L2) Ensure Host Guest File System Server is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.hgfsServerSet.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.21'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.4.21'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        } 
    } catch {
        $cisID = '8.4.21'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8422() {
    Write-Host "8.4.22 (L2) Ensure Guest Host Interaction Launch Menu is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.ghi.launchmenu.change" | select -expa Value) -eq $true) {
                $cisID = '8.4.22'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.4.22'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        } 
    } catch {
        $cisID = '8.4.22'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8423() {
    Write-Host "8.4.23 (L2) Ensure memSchedFakeSampleStats is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object {
            if ( (Get-AdvancedSetting -Entity $_ -name:"isolation.tools.memSchedFakeSampleStats.disable" | select -expa Value) -eq $true) {
                $cisID = '8.4.23'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.4.23'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        } 
    } catch {
        $cisID = '8.4.23'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8424() {
    Write-Host "8.4.24 (L1) Ensure VM Console Copy operations are disabled (Scored)";  
    $Value = $true
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'isolation.tools.copy.disable'  | select Entity, Value #Format-List -property * #
            if ($cur.Value -ne $true) {
                $cisID = '8.4.24'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.4.24'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } 
        }
    } catch {
        $cisID = '8.4.24'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8425() {
    Write-Host "8.4.25 (L1) Ensure VM Console Drag and Drop operations is disabled (Scored)";
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'isolation.tools.dnd.disable' | select Entity, Value #Format-List -property * # 
            if ($cur.Value -ne $true) {
                $cisID = '8.4.25'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.4.25'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.4.25'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8426() {
    Write-Host "8.4.26 (L1) Ensure VM Console GUI Options is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'isolation.tools.setGUIOptions.enable'  | select Entity, Value #Format-List -property * # 
            if ($cur.Value -ne $false) {
                $cisID = '8.4.26'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.4.26'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8427() {
    Write-Host "8.4.27 (L1) Ensure VM Console Paste operations are disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'isolation.tools.paste.disable'  | select Entity, Value #Format-List -property * # 
            if ($cur.Value -ne $true) {
                $cisID = '8.4.27'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                            
            } else {
                $cisID = '8.4.27'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                            
            }
        }
    } catch {
        $cisID = '8.4.27'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8428() {
    Write-Host "8.4.28 (L1) Ensure access to VM console via VNC protocol is limited (Scored)";
    try { 
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'svga.vgaOnly'  | select Entity, Value
            if ($cur.Value -ne $true) {
                $cisID = '8.4.28'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.4.28'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.4.28'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis8429() {
    Write-Host "8.4.29 (L2) Ensure all but VGA mode on virtual machines is disabled (Not Scored)"; 
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'svga.vgaOnly'  | select Entity, Value 
            if ($cur.Value -ne $true) {
                $cisID = '8.4.29'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.4.29'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.4.29'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$_.Name+"_ # CIS "+$cisID+" : "+$cisOut)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis851() {
    $cisID = '8.5.1'
    $cisOut = 'REVIEW'
    $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
    Write-Host "8.5.1 (L2) Ensure VM limits are configured correctly (Not Scored)";
    $resourceProfileData = Get-VMHost $VMHost.Name | Get-VM | Get-VMResourceConfiguration
    $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
    
    write-host ($curMessage,$cisID,$cisOut); 
    if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');; #Write-EventLog -LogName Security -Source 'secComps' -EntryType Information -EventId '0111' -Message $curMessage
    $resourceProfileData
}
function cis852() {
    Write-Host "8.5.2 (L2) Ensure hardware-based 3D acceleration is disabled (Scored)";  
    try {
        $hostValue = (Get-VMHost $VMHost.Name | Get-VM | Get-AdvancedSetting -Name "mks.enable3d").Value
        if ($hostValue -ne $false) {
            $cisID = '8.5.2'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        } else {
            $cisID = '8.5.2'
            $cisOut = 'REVIEW'
            $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
            $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut)
            
            write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
        }
    } catch {
        $cisID = '8.5.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut);
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
    }
}
function cis861() {
    Write-Host "8.6.1 (L2) Ensure nonpersistent disks are limited (Scored)";  
    try {
        $diskData = (Get-VMHost $VMHost.Name | Get-VM | Get-HardDisk)
        foreach ($j in $diskData) {
            if ($j.persistence -ne 'Persistent') {
                $cisID = '8.6.1'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curMessage = ($hstName+"_"+$hstParent+" # CIS "+$cisID+" : "+$cisOut+" / "+$j.Filename)
                
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            }
        }
    } catch {
        $cisID = '8.6.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut);
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis862() {
    Write-Host "8.6.2 (L1) Ensure virtual disk shrinking is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_.Name -name:'isolation.tools.diskShrink.disable'  | select Entity, Value
            if ($cur.Value -eq '' -or $cur.Value -ne $true) {
                $cisID = '8.6.2'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.6.2'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.6.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS - 8.6.2 : "+$message)
        
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis863() {
    Write-Host "8.6.3 (L1) Ensure virtual disk wiping is disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'isolation.tools.diskWiper.disable'| select -expa value
            if ($cur -ne $tue) {
                $cisID = '8.6.3'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            } else {
                $cisID = '8.6.3'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.6.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut);
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}

function cis871() {
    Write-Host "8.7.1 (L2) Ensure VIX messages from the VM are disabled (Scored)";  
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_.Name -name:"isolation.tools.vixMessage.disable"
            if ($cur -ne $tue -or $cur.length -le 0) {
                $cisID = '8.7.1'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                
            } else {
                $cisID = '8.7.1'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
                if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
                $evID = $cisID.Replace('.',''); 
                         
            }
        }
    } catch {
        $cisID = '8.7.1'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut);
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis872() {
    Write-Host "8.7.2 (L1) Ensure the number of VM log files is configured properly (Scored)";
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:'log.keepOld'| select -expa Value
            if ($cur -ne 10) {
                $cisID = '8.7.2'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            } else {
                $cisID = '8.7.2'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            }
        }
    } catch {
        $cisID = '8.7.2'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut);
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis873() {
    Write-Host "8.7.3 (L2) Ensure host information is not sent to guests (Scored)"; 
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $cur = Get-AdvancedSetting -Entity $_ -name:"tools.guestlib.enableHostInfo" | select -expa value
            if ($cur -eq 'False') {
                $cisID = '8.7.3'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            } else {
                $cisID = '8.7.3'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; 
        $evID = $cisID.Replace('.',''); 
        
            }
        }
    } catch {
        $cisID = '8.7.3'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
}
function cis874() {
    Write-Host "8.7.4 (L1) Ensure VM log file size is limited (Scored)";   
    try {
        Get-VMHost $VMHost.Name | Get-VM | ForEach-Object { 
            $curSize = Get-AdvancedSetting -Entity $_ -name:'log.rotateSize'  | select -expa Value
            if ($curSize -ne 1024000) {
                $cisID = '8.7.4'
                $cisOut = 'REVIEW'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            } else {
                $cisID = '8.7.4'
                $cisOut = 'PASS'
                $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
                $curVM=$_.Name; $curMessage = 
                ($hstName+"_"+$hstParent+"_Guest: "+$curVM+"_ # CIS "+$cisID+" : "+$cisOut);
                write-host ($curMessage,$cisID,$cisOut); if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
                
            }
        }
    } catch {
        $cisID = '8.7.4'
        $cisOut = 'REVIEW'
        $compliance.Add(($cisID+"_"+$_.name).trim('_'),$cisOut);
        $message = "Cannot Verify "
        $curMessage = (($VMHost.Name)+"_ # CIS "+$cisID+" : "+$cisOut)
        write-host ($curMessage,$cisID,$cisOut); 
        if ($cisOut -like 'PASS') {$entryType = 'Information'; } else {$entryType = 'Error'; }; $evID = $cisID.Replace('.','');
    }
   #Get-VMHost | Select Name, @{N="UserVars.ESXiShellInteractiveTimeOut";E={$_ | Get-AdvancedSetting UserVars.ESXiShellInteractiveTimeOut | Out-Host
}

function levelAllChecks() {
    checkPAM;
    Write-Host "> > > > > > 1 ESXi < < < < < < ";
    cis11;
    cis12;
    cis13;
    cis14;
    Write-Host "> > > > > > 2 Communication < < < < < < ";
    cis21;
    cis22;
    cis23;
    cis24;
    cis25;
    cis26;
    cis27;
    cis28;
    cis29;
    Write-Host "> > > > > > 3 Logging < < < < < < ";
    cis31;
    cis32;
    cis33;
    Write-Host "> > > > > > 4 Access < < < < < < ";
    cis41;
    cis42;
    cis43;
    cis44;
    cis45;
    Write-Host "> > > > > > 5 Console < < < < < < ";
    cis51;
    cis52;
    cis53;
    cis54;
    cis55;
    cis56;
    cis57;
    cis58;
    cis59;
    cis510;
    cis511;
    Write-Host "> > > > > > 6 Storage < < < < < < ";
    cis61;
    cis62;
    cis63;
    cis64;
    Write-Host "> > > > > > 7 vNetwork < < < < < < ";
    cis71;
    cis76;
    cis77;
    cis78;
    Write-Host "> > > > > > 8 Virtual Machines < < < < < < ";
    Write-Host "8.1 Communication";
    cis811;
    cis812;
    Write-Host "8.2 Devices";
    cis821;
    cis822;
    cis823;
    cis824;
    cis825;
    cis826;
    cis827;
    cis828;
    Write-Host "8.3 Guest";
    cis831;
    cis832;
    cis833;
    cis834;
    Write-Host "8.4 Monitor";;
    cis841;
    cis842;
    cis843;
    cis844;
    cis845;
    cis846;
    cis847;
    cis848;
    cis849;
    cis8410;
    cis8411;
    cis8412;
    cis8413;
    cis8414;
    cis8415;
    cis8416;
    cis8417;
    cis8418;
    cis8419;
    cis8420;
    cis8421;
    cis8422;
    cis8423;
    cis8424;
    cis8425;
    cis8426;
    cis8427;
    cis8428;
    cis8429;
    Write-Host "8.5 Resources";
    cis851;
    cis852;
    Write-Host "8.6 Storage";
    cis861;
    cis862;
    cis863;
    Write-Host "8.7 Storage";
    cis871;
    cis872;
    cis873;
    cis874;
}
function levelOneChecks() {
    checkPAM;
    Write-Host "> > > > > > 1 ESXi  < < < < < < ";
    cis11;
    cis12;
    cis13;
    cis14;
    Write-Host "> > > > > > 2 Communication < < < < < < ";
    cis21;
    cis22;
    cis23;
    cis24;
    cis25;
    cis26;
    cis27;
    cis28;
    cis29;
    Write-Host "> > > > > > 3 Logging < < < < < < ";
    cis31;
    cis32;
    cis33;
    Write-Host "> > > > > > 4 Access < < < < < < ";
    cis41;
    cis42;
    cis43;
    cis44;
    cis45;
    Write-Host "> > > > > > 5 Console < < < < < < ";
    cis51;
    cis52;
    cis53;
    cis54;
    cis55;
    cis56;
    cis57;
    cis58;
    cis59;
    cis510;
    cis511;
    Write-Host "> > > > > > 6 Storage < < < < < < ";
    cis61;
    cis62;
    cis63;
    cis64;
    Write-Host "> > > > > > 7 vNetwork < < < < < < ";
    cis71;
    cis76;
    cis77;
    cis78;
    Write-Host "> > > > > > 8 Virtual Machines < < < < < < ";
    Write-Host "8.1 Communication";
    cis811;
    cis812;
    Write-Host "8.2 Devices";
    cis821;
    cis822;
    cis823;
    cis824;
    cis825;
    cis826;
    cis827;
    cis828;
    Write-Host "8.3 Guest";
    cis831;
    cis832;
    cis833;
    cis834;
    Write-Host "8.4 Monitor";;
    cis841;
    cis842;
    cis843;
    cis844;
    cis845;
    cis846;
    cis847;
    cis848;
    cis849;
    cis8410;
    cis8411;
    cis8412;
    cis8413;
    cis8414;
    cis8415;
    cis8416;
    cis8417;
    cis8418;
    cis8419;
    cis8420;
    cis8421;
    cis8422;
    cis8423;
    cis8424;
    cis8425;
    cis8426;
    cis8427;
    cis8428;
    cis8429;
    Write-Host "8.5 Resources";
    cis851;
    cis852;
    Write-Host "8.6 Storage";
    cis861;
    cis862;
    cis863;
    Write-Host "8.7 Storage";;
    cis871;
    cis872;
    cis873;
    cis874; 
}

<#
    Variables 
#>
    # Global 
    $sourceName = 'CIS Benchmark ESXi 7 v1.1.0'; # Refers to the Windows Event Log Source created as Optional Output 
    $logName = 'secCompControls'; # Arbitrary; customize at-will
    Stop-Transcript
    Start-Transcript ($env:PWD+"/Logs/_FullTranscript_"+$sourceName+"_"+(Get-Date -Format '%M-%d-%y')+"_"+$logName+".txt") # perExecution Transcript 

    # Powershell Preferences 
    $ErrorActionPreference = 'Continue';
    $origExecutionPolicy = Get-ExecutionPolicy -Verbose
    Set-ExecutionPolicy Bypass -Force -Verbose 

    # CIS Preferences 
    $levelPreference = 'Level All'; # If not Default, only Level One CIS Checks will execute 

    # VMWare Preferences
    Import-Module VMware.PowerCLI -ErrorAction Stop; 
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false;    
    
    $defaultHosts = @('hqpvcent.com'); # No prefixes needed; IE: @('10.0.0.234','vc.fqdn.dom')
    $defaultUsername = 'smanji-admin@.com'; $defaultPWValue = '!!'
    if (($hosts = Read-Host "Press enter to Accept "$defaultHosts) -eq '') {$hosts= $defaultHosts} 
    if (($env:VI_USERNAME = Read-Host "Press enter to Accept "$defaultUsername) -eq '') {$env:VI_USERNAME = $defaultUsername} 
    if (($env:VI_PASSWORD = Read-Host "Press enter to Accept "$defaultPWValue) -eq '') {$env:VI_PASSWORD = $defaultPWValue } 

    [String] $splunkHECToken = 'SPLUNK_HEC_TOKEN_HERE'
    [String] $splunkSource = 'secComps.powershell'
    [String] $splunkSourceType = 'secComps.powershell'
    [String] $splunkIndex = 'secComps'
    $basePorts = @('10514','10515','10516') #Ports; determines most appropriate 
    $baseUri = '10.77.88.201'; # Forwarder Address
    #$splunkUri = '10.100.50.95' 
    $basePorts | ForEach-Object {
        $nowTest = (Test-Port $baseUri $_).PortOpened
        if (-not ($nowTest -eq 'True')) {
            $splunkUri1 = $baseUri+":"+$_
        } else {
            Write-Host -ForegroundColor Black -BackgroundColor Red 'Message not sent using '$splunkUri':'$_;
        }
    }
    if (($splunkURI = Read-Host ("Press enter to Accept "+$splunkUri1)) -eq '') {$splunkURI = $splunkUri1 } 
<#
    MCK secComps
#>
foreach ($k in $hosts) {
    $curHost = $k
    $login = connect-viserver -server $curHost -User $env:VI_USERNAME -Password $env:VI_PASSWORD
    if ($login.name.length -eq 0) {
        write-host ("Login failed to "+$login.name)
        $login | fl
    } else {
        write-host "Login Successful"
        $login | ft
    }
}

Foreach ( $VMHost in (Get-VMHost | Where-Object {$_.connectionState -ne 'Maintenance'} )) {
    $compliance = @{}
    $hstID = $VMHost.id
    $hstParent = $VMHost.Parent
    $hstVer = $VMHost.Version
    $hstBuild = $VMHost.Build
    $hstModel = $VMHost.Model
    $hstName = $VMHost.Name
    Write-Host ("====== Begin "+$hstName+" ====== ");  
    Write-Host ("====== Begin CIS Checks for "+$hstName+" ====== ");  
    if ($levelPreference -like '* All') { levelAllChecks; } else { levelOneChecks; }
    Write-Host ("====== End CIS Checks for "+$hstName+" ====== ");  
    Write-Host ('==== Scoring Section ==== ');
    $fails = $compliance.Values | ForEach-Object {if ($_ -like 'REVIEW') {$_}}
    $pass = ($compliance.Values | ForEach-Object {if ($_ -like 'PASS') {$_}})
    $complCount = ($compliance).Count
    $score = [math]::Round((($fails.count)*100)/($complCount))
    Write-Host ($hstName+" Score: "+$score+'% / Total: '+(($compliance.Values).Count)+" / Fails: "+($fails.count)+" / Pass: "+($pass.count))
    ('cisCheck,Result') | Out-File ($env:PWD+"/Logs/_CIS-Benchmark_7.0-v1.0.0_"+$hstName+"_"+$sourceName+"_"+(Get-Date -Format '%M-%d-%y')+"_"+$logName+".csv") -Force
    foreach ($j in $compliance.Keys) {
        $nam = $j
        $val = $compliance[$j]
        $InputObject = @{message=($nam+" :: "+$val)}
        $splunkInput = @{
            host = $hstName
            sourcetype = $splunkSourceType
            source = $splunkSource
            event = {
                date = $((Get-Date -Format 'MM-dd-yyyy HH:mm:ss'))
                message = ($hstName+'_'+$nam+','+$cisOut+","+$hstName)
            }
        }
        writeToSplunk($curMessage,$cisID,$cisOut,$splunkInput); 
        ($nam+","+$val) | Out-File ($env:PWD+"/Logs/_CIS-Benchmark_7.0-v1.0.0_"+$hstName+"_"+$sourceName+"_"+(Get-Date -Format '%M-%d-%y')+"_"+$logName+".csv") -Append
    }
    (' ') | Out-File ($env:PWD+"/Logs/_CIS-Benchmark_7.0-v1.0.0_"+$hstName+"_"+$sourceName+"_"+(Get-Date -Format '%M-%d-%y')+"_"+$logName+".csv") -Append
    Write-Host ('==== End Scoring Section ==== ');
    
    Write-Host ("====== End Procedure on "+$hstName+" ====== "); 
}


Set-ExecutionPolicy $origExecutionPolicy -Force -Verbose
Stop-Transcript
