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

$sqlServer = GetServer($destinationSqlName)
$sqlServer.ConnectionContext.StatementTimeout = 0
$db = $server.Databases["$destinationDbName"]

if (-not $db) {

    Write-Host "Database does not exist on: $destinationSqlName"

    # Create SMO Restore object instance
    $dbRestore = new-object ("Microsoft.SqlServer.Management.Smo.Restore")

    # Set database and backup file path
    $dbRestore.ReplaceDatabase = $True
    $dbRestore.Database = $destinationDbname
    $dbRestore.NoRecovery = $false
    $dbRestore.PercentCompleteNotification = 10
    $dbRestore.Devices.AddDevice($backupPath, "File")

    # Set the databse file location
    Write-Host "=========================================================================================="
    Write-Host "Now setting destination database file locations: "

    $dbRestoreFile = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
    $dbRestoreLog = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
    $dbRestoreFile.LogicalFileName = "EuMobil.Prod"

    Write-Host "Physical path to mdf : " $sqlServer.Information.MasterDBPath $dbRestore.Database ".mdf"

    $dbRestoreFile.PhysicalFileName = $sqlServer.Information.MasterDBPath + "\" + $dbRestore.Database + "_Data.mdf"
    $dbRestoreLog.LogicalFileName = "EuMobil.Prod" + "_Log"

    Write-Host "Physical path to ldf: " $sqlServer.Information.MasterDBLogPath $dbRestore.Database "_Log.ldf"

    $dbRestoreLog.PhysicalFileName = $sqlServer.Information.MasterDBLogPath + "\" + $dbRestore.Database + "_log.LDF"

    Write-Host "=========================================================================================="
    Write-Host "Now adding db file and db log file to relocation list..."

    $dbRestore.RelocateFiles.Add($dbRestoreFile)
    $dbRestore.RelocateFiles.Add($dbRestoreLog)

    try {

        Write-Host "=========================================================================================="
        Write-Host "Now restoring..."

        $dbRestore.SqlRestore($sqlServer)
    }
    catch {
        CheckForErrors
    }
}
else {

    Write-Host "Found $destinationSqlName\$destinationDbName"

    if ($db.RecoveryModel -ne [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {

        Write-Host "Changing recovery model to SIMPLE"

        $db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple

        try { 
            $db.Alter()
        }
        catch {
            CheckForErrors
        }
    }

    # Set destination database to single user mode to kill any active connections
    Write-Host "Current user access mode" $db.UserAccess

    if ($db.UserAccess -ne "Single") {
        try {

            Write-Host "Changing current user access mode"
            #Write-Host "Killing existing db connections..."
            #KillServer($destinationSqlName, $destinationDbName)

            $db.UserAccess = "Single"
            $db.Alter([Microsoft.SqlServer.Management.Smo.TerminationClause]"RollbackTransactionsImmediately")
        }
        catch {
            CheckForErrors
        }
    }


    # Do the restore
    try {

        Write-Host "=========================================================================================="
        Write-Host "Now restoring over an existing database..."

        # Create SMO Restore object instance
        $dbRestore = new-object ("Microsoft.SqlServer.Management.Smo.Restore")

        # Set database and backup file path
        $dbRestore.ReplaceDatabase = $True
        $dbRestore.Database = $destinationDbname
        $dbRestore.NoRecovery = $false
       $dbRestore.PercentCompleteNotification = 10
        $dbRestore.Devices.AddDevice($backupPath, "File")

        # Set the databse file location
        Write-Host "=========================================================================================="
        Write-Host "Now setting destination database file locations: "

        $dbRestoreFile = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
        $dbRestoreLog = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
        $dbRestoreFile.LogicalFileName = "EuMobil.Prod"

        Write-Host "Physical path to mdf : " $sqlServer.Information.MasterDBPath $dbRestore.Database ".mdf"

        $dbRestoreFile.PhysicalFileName = $sqlServer.Information.MasterDBPath + "\" + $dbRestore.Database + "_Data.mdf"
        $dbRestoreLog.LogicalFileName = "EuMobil.Prod" + "_Log"

        Write-Host "Physical path to ldf: " $sqlServer.Information.MasterDBLogPath $dbRestore.Database "_Log.ldf"

        $dbRestoreLog.PhysicalFileName = $sqlServer.Information.MasterDBLogPath + "\" + $dbRestore.Database + "_log.LDF"

        Write-Host "=========================================================================================="
        Write-Host "Now adding db file and db log file to relocation list..."

        $dbRestore.RelocateFiles.Add($dbRestoreFile)
        $dbRestore.RelocateFiles.Add($dbRestoreLog)
        $dbRestore.SqlRestore($sqlServer)
    }
    catch {
        Write-Host "SqlRestore failed"
        CheckForErrors
    }

    # Reload the restored database object
    $server = GetServer($destinationSqlName)
    $db = $server.Databases["$destinationDbName"]

    Write-Host "Database recovery mode at the end of restore: $db.RecoveryMode"

    # Set recovery model to simple on destination database after restore
    if ($db.RecoveryModel -ne [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {

        Write-Debug "Changing recovery model to SIMPLE"

        $db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple
        try {
            $db.Alter()
        }
        catch {
            Write-Host "RecoveryModel2"
            CheckForErrors
        }
    }
}

Write-Host "...SQL Database"$dbname" Restored Successfully..."