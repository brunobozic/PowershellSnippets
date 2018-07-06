[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")

#Enable Debug Messages
$DebugPreference = "Continue"

#Disable Debug Messages
#$DebugPreference = "SilentlyContinue"

#Terminate Code on All Errors
#$ErrorActionPreference = "Stop"

#Clear screen
CLEAR

#Clear errors
$Error.Clear()

$sourceDatabaseName = "VS2008DEVELOP\MSSQLSERVERR2,1434"
$backupPath_FileShare = "\\NINO\DatabaseBackups\"
$databaseName = "EuMobil.Develop"

# Set destination SQL Server instance name
$destinationSqlName = "NINO\EXPRESS2017"

# Set new or existing database name to restore backup
$destinationDbname = "EuMobil.Develop"
$destinationBackedUpFileExtenstion = ".bak"

# Set the existing backup file path
$backupPath = $backupPath_FileShare + $destinationDbname + $destinationBackedUpFileExtenstion

function CheckForErrors {

    $errorsReported = $False

    if ($Error.Count -ne 0) {

        Write-Host
        Write-Host "******************************"
        Write-Host "Errors:" $Error.Count
        Write-Host "******************************"

        foreach ($err in $Error) {
            $errorsReported = $True
            if ( $err.Exception.InnerException -ne $null) {
                Write-Host $err.Exception.InnerException.ToString()
            }
            else {
                try { Write-Host $err.Exception.ToString()}catch {}  
            }

            Write-Host
        }

        throw;
    }
}

function GetServer {
    Param([string]$serverInstance)

    $server = New-Object ("Microsoft.SqlServer.Management.Smo.Server")($serverInstance)
    $server.ConnectionContext.ApplicationName = "AutoDatabaseRefresh"
    $server.ConnectionContext.ConnectTimeout = 1

    $server;
}

function KillServer {
    Param([string]$serverInstance, [string]$dbToKill)

    $server = New-Object ("Microsoft.SqlServer.Management.Smo.Server")($serverInstance)
    $server.KillDatabase($dbToKill)
    $server.Refresh()

    $server;
}


# "=========================================================================================="
# "=========================================================================================="
# "=========================================================================================="

Write-Host "=========================================================================================="
Write-Host "Now backing up source database: " $sourceDatabaseName "to: " $backupPath_FileShare $databaseName

$sqlobjectSource = new-object ("Microsoft.SqlServer.Management.Smo.Server") $sourceDatabaseName
$Databases = $sqlobjectSource.Databases
$sentinel = "$($backupPath_FileShare)$($databaseName).bak"

write-host "Deleting old backups..."

if (Test-Path $sentinel) {
    Remove-Item $sentinel
}

foreach ($Database in $Databases) {
    if ($Database.Name -eq $databaseName) {

        write-host "........... Backup in progress for" $Database.Name " database in " $sqlobjectSource.Name

        $dbname = $Database.Name
        $dbBackup = new-object ("Microsoft.SqlServer.Management.Smo.Backup")
        $dbBackup.Action = "Database" # For full database backup, can also use "Log" or "File"
        $dbBackup.Database = $dbname
        $dbBackup.CopyOnly = "true"

        Write-Host "Now adding a backup device: " $backupPath_FileShare $databaseName ".bak"

        $dbBackup.Devices.AddDevice($backupPath_FileShare + "\" + $databaseName + ".bak", "File")
        $dbBackup.SqlBackup($sqlobjectSource)
    }
}

write-host "........... Backup Finished for " $Database.Name " database in " $sqlobjectSource.Name

# Connect to the destination SQL Server.
# $sqlServer = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $destinationSqlName



Write-Host "...SQL Database"$dbname" Restored Successfully..."