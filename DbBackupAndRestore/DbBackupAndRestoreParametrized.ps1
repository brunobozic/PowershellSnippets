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

# .\DbBackupAndRestoreParametrized.ps1 "VS2008DEVELOP\MSSQLSERVERR2,1434" "EuMobil.Develop" "NINO\EXPRESS2017" "EuMobil.Develop" "\\NINO\DatabaseBackups\"

$sourceInstanceName = "VS2008DEVELOP\MSSQLSERVERR2,1434"
$backupPath_FileShare = "\\NINO\DatabaseBackups\"
$sourceDatabaseName = "EuMobil.Develop"

# Set destination SQL Server instance name
$destinationInstanceName = "NINO\EXPRESS2017"
$destinationDatabaseName = "EuMobil.Develop"
# Set new or existing database name to restore backup
$destinationInstanceName = "EuMobil.Develop"
$destinationBackedUpFileExtenstion = ".bak"

# Set the existing backup file path
$backupPath = $backupPath_FileShare + $destinationDbname + $destinationBackedUpFileExtenstion

function Main{
 
 Param([string]$sourceInstanceName, [string]$sourceDatabaseName, [string]$destinationInstanceName, [string]$destinationDatabaseName, [string]$backupPath_FileShare)
 
 #Clear screen
 #CLEAR

 #Clear errors
 $Error.Clear()

    Write-Host
    Write-Host "========================================================================"
    Write-Host " 1: Perform Initial Checks & Validate Input Parameters"
    Write-Host "========================================================================"
 
 ValidateAndMakePreflightChecks $sourceInstanceName $sourceDatabaseName $destinationInstanceName $destinationDatabaseName $backupPath_FileShare
 
    Write-Host
    Write-Host "========================================================================"
    Write-Host " 2: Backup the source Db to a network share"
    Write-Host "========================================================================"

 DoBackup $sourceInstanceName $sourceDatabaseName $destinationDatabaseName $backupPath_FileShare
  
    Write-Host
    Write-Host "========================================================================"
    Write-Host " 3: Restore Backup File (from a network share) to the Destination Server"
    Write-Host "========================================================================"

 DoRestore $destinationInstanceName $destinationDatabaseName $backupPath_FileShare

    Write-Host
    Write-Host "========================================================================"
    Write-Host "    Database refresh completed successfully"
    Write-Host "========================================================================"
}

function ValidateAndMakePreflightChecks {

    Param($sourceInstanceName, $sourceDatabaseName, $destinationInstanceName, $destinationDatabaseName, $backupPath_FileShare)
 
    Write-Host "Validating parameters..." -NoNewline
 
    if([String]::IsNullOrEmpty($sourceInstanceName))
    {
        Write-Host "ERROR"
        $errorMessage = "Source server name is not valid." + $sourceInstanceName
        throw $errorMessage
    }

    if([String]::IsNullOrEmpty($sourceDatabaseName))
    {
        Write-Host "ERROR"
        $errorMessage = "Source database name is not valid." + $sourceDatabaseName
        throw $errorMessage
    }

    if([String]::IsNullOrEmpty($destinationInstanceName))
    {
        Write-Host "ERROR"
        $errorMessage = "Destination server name is not valid."
        throw $errorMessage
    }

    if([String]::IsNullOrEmpty($destinationDatabaseName))
    {
        Write-Host "ERROR"
        $errorMessage = "Destination database name is not valid."
        throw $errorMessage
    }

    if([String]::IsNullOrEmpty($backupPath_FileShare))
    {
        Write-Host "ERROR"
        $errorMessage = "Network share path name is not valid."
        throw $errorMessage
    }
    else
    {
        if(-not $backupPath_FileShare.StartsWith("\\"))
        {
            Write-Host "ERROR"
            $errorMessage = "Destination path is not valid: " + $backupPath_FileShare
            throw $errorMessage
        }
    }
    
    Write-Host "OK"
    Write-Host "Verifying source SQL Server connectivity..." -NoNewline

    $conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($sourceInstanceName)
    $conn.ApplicationName = "AutoDatabaseRefresh"
    $conn.NonPooledConnection = $true
    $conn.ConnectTimeout = 5

    try
    {
        $conn.Connect()
        $conn.Disconnect()
    }
    catch
    {
        CheckForErrors
    }

    Write-Host "OK"
    Write-Host "Verifying source database exists..." -NoNewline

    $sourceServer = GetServer($sourceInstanceName)
    $sourcedb = $sourceServer.Databases[$sourceDatabaseName]

    if(-not $sourcedb)
    {
        Write-Host "ERROR"
        $errorMessage = "Source database does not exist on $sourceInstanceName"
        throw $errorMessage
    }

    Write-Host "OK"
    Write-Host "Verifying destination SQL Server connectivity..." -NoNewline

    $conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($destinationInstanceName)
    $conn.ApplicationName = "AutoDatabaseRefresh"
    $conn.NonPooledConnection = $true
    $conn.ConnectTimeout = 5

    try
    {
        $conn.Connect()
        $conn.Disconnect()
    }
    catch
    {
        CheckForErrors
    }

    Write-Host "OK"
 
    Write-Host "Verifying file share exists..." -NoNewline
    
    if((Test-Path -Path $backupPath_FileShare) -ne $True)
    {
        Write-Host "ERROR"
        $errorMessage = "File share:" + $backupPath_FileShare + " does not exists"
        throw $errorMessage
    }

    Write-Host "OK"
}

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

function DoRestore {
    Param([string]$destinationInstance, [string]$destinationDatabaseName, [string]$networkSharePath)
     
    Write-Host "  [O] Getting handle on destinationInstance: [ "$destinationInstance" ]"
    $sqlServer = GetServer($destinationInstance)
    $sqlServer.ConnectionContext.StatementTimeout = 0
    $db = $sqlServer.Databases["$destinationDatabaseName"]

    if (-not $db) {

        Write-Host "  [O] Database $destinationDatabaseName does not exist on: $destinationInstance"

        # Create SMO Restore object instance
        $dbRestore = new-object ("Microsoft.SqlServer.Management.Smo.Restore")

        # Set database and backup file path
        $dbRestore.ReplaceDatabase = $True
        $dbRestore.Database = $destinationDatabaseName
        $dbRestore.NoRecovery = $false
        $dbRestore.PercentCompleteNotification = 10
        $fullPath = $networkSharePath + $destinationDatabaseName + ".bak"
        $dbRestore.Devices.AddDevice($fullPath, "File")

        # Set the databse file location
        Write-Host "3.a. Setting destination database file locations: "

        $dbRestoreFile = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
        $dbRestoreLog = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
        $dbRestoreFile.LogicalFileName = "EuMobil.Prod"

        Write-Host "  [O] Physical path to mdf: " $sqlServer.Information.MasterDBPath $dbRestore.Database".mdf"

        $dbRestoreFile.PhysicalFileName = $sqlServer.Information.MasterDBPath + "\" + $dbRestore.Database + "_Data.mdf"
        $dbRestoreLog.LogicalFileName = "EuMobil.Prod" + "_Log"

        Write-Host "  [O] Physical path to ldf: " $sqlServer.Information.MasterDBLogPath $dbRestore.Database"_Log.ldf"

        $dbRestoreLog.PhysicalFileName = $sqlServer.Information.MasterDBLogPath + "\" + $dbRestore.Database + "_log.LDF"

        Write-Host "3.b. Adding db file and db log file to relocation list..."

        $dbRestore.RelocateFiles.Add($dbRestoreFile)
        $dbRestore.RelocateFiles.Add($dbRestoreLog)

        try {

            Write-Host "3.c. Restoring..."

            $dbRestore.SqlRestore($sqlServer)
        }
        catch {
            CheckForErrors
        }
    }
    else {

        Write-Host "  [O] Found [ $destinationInstance\$destinationDatabaseName ]"

        if ($db.RecoveryModel -ne [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {

            Write-Host "3.a. Changing recovery model to SIMPLE"

            $db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple

            try { 
                $db.Alter()
            }
            catch {
                CheckForErrors
            }
        }

        # Set destination database to single user mode to kill any active connections
        Write-Host "  [O] Current user access mode [" $db.UserAccess " ]"

        if ($db.UserAccess -ne "Single") {
            try {

                Write-Debug "Changing current user access mode"
             
                $db.UserAccess = "Single"
                $db.Alter([Microsoft.SqlServer.Management.Smo.TerminationClause]"RollbackTransactionsImmediately")
            }
            catch {
                CheckForErrors
            }
        }


        # Do the restore
        try {

           
            Write-Host "3.b. Restoring over an existing database..."

            # Create SMO Restore object instance
            $dbRestore = new-object ("Microsoft.SqlServer.Management.Smo.Restore")

            # Set database and backup file path
            $dbRestore.ReplaceDatabase = $True
            $dbRestore.Database = $destinationDatabaseName
            $dbRestore.NoRecovery = $false
            $dbRestore.PercentCompleteNotification = 10
            $fullPath = $networkSharePath + $destinationDatabaseName + ".bak"
            $dbRestore.Devices.AddDevice($fullPath, "File")

            # Set the databse file location

            Write-Host "3.c. Setting destination database file locations: "

            $dbRestoreFile = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
            $dbRestoreLog = new-object("Microsoft.SqlServer.Management.Smo.RelocateFile")
            $dbRestoreFile.LogicalFileName = "EuMobil.Prod"

            Write-Host "  [O] Physical path to mdf : " $sqlServer.Information.MasterDBPath"\"$dbRestore.Database".mdf"

            $dbRestoreFile.PhysicalFileName = $sqlServer.Information.MasterDBPath + "\" + $dbRestore.Database + "_Data.mdf"
            $dbRestoreLog.LogicalFileName = "EuMobil.Prod" + "_Log"

            Write-Host "  [O] Physical path to ldf: " $sqlServer.Information.MasterDBLogPath"\"$dbRestore.Database"_Log.ldf"

            $dbRestoreLog.PhysicalFileName = $sqlServer.Information.MasterDBLogPath + "\" + $dbRestore.Database + "_log.LDF"

            Write-Host "3.d. Adding db file and db log file to relocation list..."

            $dbRestore.RelocateFiles.Add($dbRestoreFile)
            $dbRestore.RelocateFiles.Add($dbRestoreLog)
            $dbRestore.SqlRestore($sqlServer)
        }
        catch {
            Write-Host "SqlRestore failed"
            CheckForErrors
        }

        # Reload the restored database object
        $server = GetServer($destinationInstance)
        $db = $server.Databases["$destinationDatabaseName"]

        Write-Host "3.e. Database recovery mode at the end of restore: ["$db.RecoveryMode" ]"

        # Set recovery model to simple on destination database after restore
        if ($db.RecoveryModel -ne [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {

            Write-Debug " Changing recovery model to SIMPLE"

            $db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple
            try {
                $db.Alter()
            }
            catch {
                Write-Host "RecoveryModel change problem."
                CheckForErrors
            }
        }
    }
}

function DoBackup {
    Param([string]$sourceInstance, [string]$sourceDatabaseName, [string]$destinationDatabaseName, [string]$networkSharePath)

    $sqlobjectSource = new-object ("Microsoft.SqlServer.Management.Smo.Server") $sourceInstance
    $Databases = $sqlobjectSource.Databases
    $sentinel = "$($backupPath_FileShare)$($destinationDatabaseName).bak"
    
     write-host "  [O] Source Instance: $sourceInstance"
     write-host "  [O] Source Name: $sourceDatabaseName"
     write-host "  [O] Network path: $networkSharePath"
     write-host "2.a. Deleting old backups"

    if (Test-Path $sentinel) {
        Remove-Item $sentinel
    }

    foreach ($Database in $Databases) {
        if ($Database.Name -eq $sourceDatabaseName) {

            write-host "2.b. Backup in progress for [" $Database.Name "] database on ["$sqlobjectSource.Name" ]"

            $dbname = $Database.Name
            $dbBackup = new-object ("Microsoft.SqlServer.Management.Smo.Backup")
            $dbBackup.Action = "Database" # For full database backup, can also use "Log" or "File"
            $dbBackup.Database = $sourceDatabaseName
            $dbBackup.CopyOnly = "true"

            Write-Host "2.c. Adding a backup device: [ $backupPath_FileShare$sourceDatabaseName.bak ]"

            $dbBackup.Devices.AddDevice($backupPath_FileShare + "\" + $sourceDatabaseName + ".bak", "File")
            $dbBackup.SqlBackup($sqlobjectSource)

        }
    }

    if (Test-Path $sentinel) {
         write-host "Backup created."
    }
}


#Capture inputs from the command line.
$sourceInstanceName = $args[0]
$sourceDatabaseName = $args[1]
$destinationInstanceName = $args[2]
$destinationDatabaseName = $args[3]
$backupPath_FileShare = $args[4]


$debug = "Source Instance Parameter: " + $sourceInstanceName
Write-Debug $debug
$debug = "Source Database Parameter: " + $sourceDatabaseName
Write-Debug $debug
$debug = "Destination Db Instance Parameter: " + $destinationInstanceName
Write-Debug $debug
$debug = "Destination Database Name Parameter: " + $destinationDatabaseName
Write-Debug $debug
$debug = "Network share: " + $backupPath_FileShare
Write-Debug $debug

Main $sourceInstanceName $sourceDatabaseName $destinationInstanceName $destinationDatabaseName $backupPath_FileShare

Exit 5

