Param(
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $network = "jasper-reports-network",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $appImage = "jasper-reports-img",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $jasperReportsService = "jasper-reports-service",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $mariaDbImage = "mariadb",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $mariadDbVolume = "D:/docker_jasper:/bitnami",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $jasperReportsDbVolume = "D:/docker_jasper:/bitnami",
    [parameter(Mandatory=$false)]            
    [ValidateNotNullOrEmpty()]             
    [String] $jasperReportsIP = "0.0.0.0:81"
)   

$ErrorActionPreference = "Stop"

try {

# Remove left-over containers from the last test -> by their name

#Write-Host -BackgroundColor Black "Removing left over volumes..."
#docker volume rm $(docker volume ls -q -filter "dangling=true")
# docker rm $(docker stop $(docker ps -a -q -f "ancestor=$appImage"))

Write-Host -BackgroundColor Black "Removing containers..."
docker ps -a -q | % { docker stop $_ }
docker ps -a -q | % { docker rm $_ }

if(!(docker ps --filter name=$appImage -q))
{
    Write-Host -BackgroundColor Black "I did not find the images you need locally..."
    # docker images -q | % { docker rmi $_ }
    docker pull bitnami/mariadb:latest
    docker pull bitnami/jasperreports:latest
}


# Remove left-over image
# Write-Host -BackgroundColor Black "Removing images..."


# Docker volumes
Write-Host -BackgroundColor Black "Creating Volumes..."
docker volume create --name mariadb_data
docker volume create --name jasperreports_data



# Setup the overlay network if it hasnt already been set
if(!(docker network ls --filter name=$network -q))
{
    Write-Host -BackgroundColor Black "Setting up the new network..."
    docker network create $network
}
else
{
    Write-Host -BackgroundColor Black "Removing the old network..."
    docker network rm $network
    Write-Host -BackgroundColor Black "Setting up the new network..."
    docker network create $network
}

    Write-Host -BackgroundColor Black "Running containers..."
    docker run -d --name $mariaDbImage -e MARIADB_DATABASE=bitnami_jasperreports -e ALLOW_EMPTY_PASSWORD=yes -e MARIADB_USER=bn_jasperreports -e MARIADB_ROOT_USER=root -e USER=root --net $network --volume D:/docker_jasper:/bitnami bitnami/mariadb:latest
   
    docker run -d --name $appImage -p 0.0.0.0:81:8080 --net $network -e ALLOW_EMPTY_PASSWORD=yes -e JASPERREPORTS_DATABASE_USER=bn_jasperreports -e JASPERREPORTS_DATABASE_NAME=bitnami_jasperreports -e JASPERREPORTS_PASSWORD=bitnami -e MARIADB_HOST=mariadb -e MARIADB_PORT=3306 -e MARIADB_ROOT_USER=root -e MYSQL_CLIENT_CREATE_DATABASE_PRIVILEGES=ALL --volume D:/docker_jasper:/bitnami bitnami/jasperreports:latest
   

    # Test connection
    # Write-Host -BackgroundColor Black "Testing connections..."
    # Invoke-RestMethod -Method Get -Headers @{'accept'='application/json'} -Uri http://localhost:81/jasperserver

}
catch [exception]
{
       Write-Host $_.Exception.Message
}

Write-Host -BackgroundColor Black "All tasks completed, please wait for the jasper server to compile and start up, allow for 5-10 min"
