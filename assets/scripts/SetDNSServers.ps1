$NICs = Get-WMIObject Win32_NetworkAdapterConfiguration  |where{$_.IPEnabled -eq “TRUE”}
Foreach($NIC in $NICs) {
$DNSServers = “192.168.0.3",”208.67.220.220"
 $NIC.SetDNSServerSearchOrder($DNSServers)
 $NIC.SetDynamicDNSRegistration(“TRUE”)
}