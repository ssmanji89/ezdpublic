iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/ssmanji89/public/main/assets.botstuff.org/powershell/PSDWinget-Static.ps1')) -Verbose
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/ssmanji89/public/main/assets.botstuff.org/powershell/_WINGET.ps1')) -Verbose


iex ((New-Object System.Net.WebClient).DownloadString('https://gist.githubusercontent.com/ssmanji89/e8a917e6f7b418ee68bb8f1c6f3bb693/raw')) -Verbose
Invoke-WebRequest -Uri https://raw.githubusercontent.com/ssmanji89/public/main/assets.botstuff.org/powershell/_WINGET.ps1 -OutFile ("c:\Install-Winget1.ps1")
Set-RunOnce -KeyName 'WinGETInstallation' -Command '%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file c:\Install-Winget1.ps1'