New-EventLog -LogName Application -Source 'IT' -Verbose -ErrorAction SilentlyContinue
Set-ExecutionPolicy RemoteSigned -Force; 

if (-not (Test-Path ($env:SystemDrive+'\IT\Oboarding_'+$env:COMPUTERNAME+'.txt'))){
    New-Item ($env:SystemDrive+'\IT') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\Backups') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\Logs') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\Scripts') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\Tools') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\Reports') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
    New-Item ($env:SystemDrive+'\IT\DR') -ItemType Directory -Verbose -ErrorAction SilentlyContinue;
} 

$dirss = (
    ($env:SystemDrive+'\IT\DR\Logs'),
    ($env:SystemDrive+'\IT\DR\Backup'),
    ($env:SystemDrive+'\IT\DR\Archive'),
    ($env:SystemDrive+'\IT\DR\Temp')
);
foreach ($d in $dirss) {
    New-Item -ItemType Directory -Path $d -Verbose -ErrorAction SilentlyContinue
}       

iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'));