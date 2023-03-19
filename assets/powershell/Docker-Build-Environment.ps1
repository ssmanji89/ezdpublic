# Define Docker images and versions
$postgresImage = "postgres:13.4"
$windowsserverImage = "microsoft/windowsservercore:ltsc2019"
$ubuntuImage = "ubuntu:latest"
$iactoolImage = "iac:latest"
$powershellImage = "mcr.microsoft.com/powershell:7.1.5-alpine-3.13"
$ansibleImage = "ubuntu:latest"
$cicdImage = "docker:latest"

# Define network names
$externalNetwork = "external"
$internalNetwork = "internal"
$privateNetwork = "private"

# Create Docker networks
docker network create $externalNetwork
docker network create $internalNetwork
docker network create $privateNetwork

# Create PostgreSQL container for AD database
docker run --name addb --network $externalNetwork -d $postgresImage

# Create Ubuntu containers for Group Policy Editor and ADUC
docker run --name gpedit --network $internalNetwork -d $ubuntuImage
docker run --name aduc --network $internalNetwork -d $ubuntuImage

# Create Windows Server 2019 container for WS2019 virtual machine
docker run --name ws2019 --network $externalNetwork -d $windowsserverImage

# Create Windows 10 container for Windows 10 virtual machine
docker run --name win10 --network $internalNetwork -d $windowsserverImage

# Create Ubuntu container for Linux virtual machine
docker run --name ubuntu --network $privateNetwork -d $ubuntuImage

# Create virtual switches
docker network connect $externalNetwork ws2019
docker network connect $internalNetwork win10
docker network connect $privateNetwork ubuntu

# Create PowerShell container for PowerShell Scripting
docker run --name powershell --network $internalNetwork -d $powershellImage

# Create PowerShell container for DSC Pull Server
docker run --name dsc --network $internalNetwork -d $powershellImage

# Create Ubuntu container for Ansible Configuration Management
docker run --name ansible --network $internalNetwork -d $ansibleImage

# Create Docker container for IaC Tool
docker run --name iac --network $internalNetwork -d $iactoolImage

# Create Docker container for CI/CD Pipeline
docker run --name cicd --network $internalNetwork -d $cicdImage
