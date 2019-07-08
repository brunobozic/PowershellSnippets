import-module WebAdministration

# Fetch latest nuget spec from source feed
function Get-MostRecentNugetSpec($nugetPackageId, $feedSource) {
    $feedUrl= $feedSource + "/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nugetPackageId'&`$orderby=Version%20desc&`$top=1"
	$webClient = new-object System.Net.WebClient
    $feedResults = [xml]($webClient.DownloadString($feedUrl))
    return $feedResults.feed.entry
}

# Fetch latest package version from spec file
function Get-NuGet-Version($spec) {
    $v = $spec.properties.version."#text"
    if(!$v) {
        $v = $spec.properties.version
    }
    return $v
}

# increment semver by 1
function Increment-Version($version){

    if(!$version) {
        return "0.0.0.1";
    }

    $parts = $version.split('.')
    for($i = $parts.length-1; $i -ge 0; $i--){
        $x = ([int]$parts[$i]) + 1
        if($i -ne 0) {
            if($x -eq 10) {
                $parts[$i] = "0"
                continue
            }
        }
        $parts[$i] = $x.ToString()
        break;
    }
    $newVersion = [System.String]::Join(".", $parts)
    if($newVersion) {
        return $newVersion
    } else {
        return "0.0.0.1"
    }
}

# change version and update user to current os user
function Change-NuSpec-Version-Author($spec, $newVer) {
    $metadata = $spec.package.metadata
    $metadata.version = [string]"$newVer"
	$metadata.authors = [Environment]::UserDomainName + "\" + [Environment]::UserName
}

# increment assembly info version by 1
function Update-AssemblyInfoVersion($projectFolder, $version)
{
	$aInfo = Get-ChildItem $projectFolder "AssemblyInfo.cs" -Recurse | Select-Object -First 1

	$newVersion = 'AssemblyVersion("' + $version + '")';
	$newFileVersion = 'AssemblyFileVersion("' + $version + '")';

	$tmpFile = $aInfo.FullName + ".tmp"

	get-content $aInfo.FullName | 
		%{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newVersion } |
		%{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newFileVersion }  > $tmpFile

	move-item $tmpFile $aInfo.FullName -force
}

# increment assembly info version by 1
function UpdateSolution-AssemblyInfoVersion($solution, $version)
{
	$aInfos = Get-ChildItem ((Get-Item($solution)).Directory.FullName) "AssemblyInfo.cs"  -Recurse

	Foreach ($aInfo IN $aInfos)
	{

		$newVersion = 'AssemblyVersion("' + $version + '")';
		$newFileVersion = 'AssemblyFileVersion("' + $version + '")';

		$tmpFile = $aInfo.FullName + ".tmp"

		get-content $aInfo.FullName | 
			%{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newVersion } |
			%{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newFileVersion }  > $tmpFile

		move-item $tmpFile $aInfo.FullName -force
	}
}

# build specific project in solution
function BuildProject(){
	Param(
        [parameter(Mandatory=$true)]            
        [ValidateNotNullOrEmpty()]             
        [String] $solution, 
		
		[parameter(Mandatory=$true)]            
        [ValidateNotNullOrEmpty()]             
        [String] $project,
		
		[parameter(Mandatory=$false)]            
        [ValidateNotNullOrEmpty()]             
        [String] $config = "Debug"
    )   

	$vsEnvVars = (dir Env:).Name -match "VS[1-9][0-9]0COMNTOOLS"
	$latestVs = $vsEnvVars | Sort-Object | Select -Last 1
	$vsPath = Get-Content Env:\$latestVs
	$vs = Join-Path $vsPath '..\IDE\devenv.com'
	
	#New-Item -ItemType Directory -Force -Path .\Logs
	
	
	#$logPath = '.\Logs\' + [System.IO.Path]::GetFileNameWithoutExtension((Get-Item $project).FullName) + 'Build.log'
	#if(Test-path $logPath){
	#	Remove-Item $logPath -Force
	#}
	#$vsArgs = "$solution /rebuild $config /project $project /out $logPath"
	$vsArgs = "$solution /rebuild $config /project $project"
	start-process $vs $vsArgs -NoNewWindow -Wait
}

# build  solution
function BuildSolution(){
	Param(
        [parameter(Mandatory=$true)]            
        [ValidateNotNullOrEmpty()]             
        [String] $solution, 
		
		[parameter(Mandatory=$false)]            
        [ValidateNotNullOrEmpty()]             
        [String] $config = "Debug"
    )   
	
	$vsEnvVars = (dir Env:).Name -match "VS[1-9][0-2]0COMNTOOLS"
	$latestVs = $vsEnvVars | Sort-Object | Select -Last 1
	$vsPath = Get-Content Env:\$latestVs
	$vs = Join-Path $vsPath '..\IDE\devenv.com'
	
	New-Item -ItemType Directory -Force -Path .\Logs
	$logPath = '.\Logs\' +  [System.IO.Path]::GetFileNameWithoutExtension((Get-Item $solution).FullName)  + 'Build.log'
	
	if(Test-path $logPath){
		Remove-Item $logPath -Force
	}
	
	$vsArgs = "$solution /rebuild $config /out $logPath"
	start-process $vs $vsArgs -NoNewWindow -Wait
}

function IncrementDllNuGetPackageVersionPackAndPush($apiKey, $source, $nuget, $nuspecTemplate, $nupkgDir, $packageId){
	$ErrorActionPreference = "Stop"
	
	$mostRecentNuspec = (Get-MostRecentNugetSpec $packageId $source)

	Write-Host "Fetching latest version from NuGet server"
	$currentVersion = Get-NuGet-Version($mostRecentNuspec)

	Write-Host "Updating nuspec to latest version"
	$newVersion = Increment-Version($currentVersion)
	$nuspec = [xml](cat $nuspecTemplate)
	Change-NuSpec-Version-Author $nuspec $newVersion
	$nuspec.Save((get-item $nuspecTemplate))

	Write-Host "Packing......"
	$nuspecTemplate = '"' + $nuspecTemplate + '"'
	$packArgs = "pack $nuspecTemplate -NoPackageAnalysis -OutputDirectory $nupkgDir"
	start-process $nuget  $packArgs -NoNewWindow -Wait

	Write-Host "Pushing......."
	$pushArgs = "push $nupkgDir$packageId.$newVersion.nupkg $apiKey -Source $source"
	start-process $nuget  $pushArgs -NoNewWindow -Wait


	Write-Host "Done"
}

# use for "Standard" nuget packages
function IncrementNuGetPackageVersionPackAndPush($apiKey, $source, $nuget, $nuspecTemplate, $nupkgDir, $packageId, $addUserAsPrerelease){
	$ErrorActionPreference = "Stop"
	
	$mostRecentNuspec = (Get-MostRecentNugetSpec $packageId $source)

	Write-Host "Fetching latest version from NuGet server"
	$currentVersion = Get-NuGet-Version($mostRecentNuspec)

	Write-Host "Updating nuspec to latest version"
	$newVersion = Increment-Version($currentVersion)
	
	if($addUserAsPrerelease)
	{
		$newVersion = $newVersion + '-' + [Environment]::UserName
	}
	
	$nuspec = [xml](cat $nuspecTemplate)
	Change-NuSpec-Version-Author $nuspec $newVersion
	$nuspec.Save((get-item $nuspecTemplate))

	Write-Host "Packing......"
	$nuspecTemplate = '"' + $nuspecTemplate + '"'
	$packArgs = "pack $nuspecTemplate -NoPackageAnalysis -OutputDirectory $nupkgDir"
	start-process $nuget  $packArgs -NoNewWindow -Wait

	Write-Host "Pushing......."
	$pushArgs = "push $nupkgDir$packageId.$newVersion.nupkg $apiKey -Source $source"
	start-process $nuget  $pushArgs -NoNewWindow -Wait


	Write-Host "Done"
}

# use for "Siduri" nuget packages
function IncrementSiduriPackageVersionRebuildPackAndPush($apiKey, $source, $nuget, $packageId, $projectDir, $solution){
	$ErrorActionPreference = "Stop"

	$mostRecentNuspec = (Get-MostRecentNugetSpec $packageId $source)

	Write-Host "Fetching latest version from NuGet server"
	$currentVersion = Get-NuGet-Version($mostRecentNuspec)

	Write-Host "Updating assembly info to latest version"
	$newVersion = Increment-Version($currentVersion)
	Update-AssemblyInfoVersion $projectDir $newVersion
	
	Write-Host "Rebuilding..."
	BuildProject $solution $packageId
	
	Write-Host "Pushing......."
	$pushArgs = "push $projectDir\Install\$packageId.$newVersion.nupkg $apiKey -Source $source"
	start-process $nuget  $pushArgs -NoNewWindow -Wait
	##push
	
}

# use for Rhetos nuget packages
function IncrementRhetosNuGetAndPackageInfoVersionPackAndPush($apiKey, $source, $nuget, $nuspecTemplate, $nupkgDir, $packageId){
	$ErrorActionPreference = "Stop"
	
	$mostRecentNuspec = (Get-MostRecentNugetSpec $packageId $source)

	Write-Host "Fetching latest version from NuGet server"
	$currentVersion = Get-NuGet-Version($mostRecentNuspec)

	Write-Host "Updating nuspec to latest version"
	$newVersion = Increment-Version($currentVersion)
	$nuspec = [xml](cat $nuspecTemplate)
	Change-NuSpec-Version-Author $nuspec $newVersion
	$nuspec.Save((get-item $nuspecTemplate))
	
	Write-Host "Updating package info to latest version"
	

	Write-Host "Packing......"
	$nuspecTemplate = '"' + $nuspecTemplate + '"'
	$packArgs = "pack $nuspecTemplate -NoPackageAnalysis -OutputDirectory $nupkgDir"

	start-process $nuget  $packArgs -NoNewWindow -Wait

	Write-Host "Pushing......."
	$pushArgs = "push $nupkgDir$packageId.$newVersion.nupkg $apiKey -Source $source"
	start-process $nuget  $pushArgs -NoNewWindow -Wait


	Write-Host "Done"
}

# use for Rhetos buildable nuget packages
function IncrementRhetosPackageVersionRebuildPackAndPush($apiKey, $source, $nuget, $packageId, $solution, $nuspecTemplate, $nupkgDir){
	$ErrorActionPreference = "Stop"
	
	$mostRecentNuspec = (Get-MostRecentNugetSpec $packageId $source)

	Write-Host "Fetching latest version from NuGet server"
	$currentVersion = Get-NuGet-Version($mostRecentNuspec)

	Write-Host "Updating assembly info to latest version"
	$newVersion = Increment-Version($currentVersion)
	UpdateSolution-AssemblyInfoVersion $solution $newVersion
		
	Write-Host "Rebuilding..."
	BuildProject $solution $packageId
	
	Write-Host "Updating nuspec to latest version"
	$newVersion = Increment-Version($currentVersion)
	$nuspec = [xml](cat $nuspecTemplate)
	Change-NuSpec-Version-Author $nuspec $newVersion
	$nuspec.Save((get-item $nuspecTemplate))
	
	Write-Host "Updating package info to latest version"
	
	$nuspecTemplate = '"' + (get-item $nuspecTemplate).FullName + '"'
	Write-Host "Packing......"
	$packArgs = "pack $nuspecTemplate -NoPackageAnalysis -OutputDirectory $nupkgDir"
	Write-Host $packArgs
	start-process $nuget  $packArgs -NoNewWindow -Wait

	Write-Host "Pushing......."
	$pushArgs = "push $nupkgDir$packageId.$newVersion.nupkg $apiKey -Source $source"
	start-process $nuget  $pushArgs -NoNewWindow -Wait


	Write-Host "Done"

}

Function RecreateCentrix2Database(){
	
	$rhetosServerPath = "Config\RhetosServer.txt"
	$rhetosDatabasePath = "Config\RhetosDatabase.txt"
	$rhetosDatabase = Get-Content $rhetosDatabasePath -First 1
	$rhetosServer = Get-Content $rhetosServerPath -First 1
	
	Write-Host "Recreating database......."	
	$recreateQuery = "USE MASTER; IF EXISTS(select * from sys.databases where name='" + $rhetosDatabase +"')BEGIN alter database [" + $rhetosDatabase +"] set single_user with rollback immediate; Drop database " + $rhetosDatabase + " END; CREATE DATABASE " + $rhetosDatabase + ";"
	Invoke-SqlCmd -ServerInstance $rhetosServer  -Query $recreateQuery

}

Function GetWebAppFullName(){
	Param(
        [parameter(Mandatory=$true)]            
        [ValidateNotNullOrEmpty()]             
        [Microsoft.IIs.PowerShell.Framework.ConfigurationElement] $webApp,
		
		[parameter(Mandatory=$false)]            
        [ValidateNotNullOrEmpty()]             
        [string] $currentPath
    )  


 
    if(!$currentPath){
        $currentPath = $webApp.Attributes[0].Value
    }

	$parent = [Microsoft.IIs.PowerShell.Framework.ConfigurationElement]$webApp.GetParentElement()
    
	if(!$parent){
	    return $currentPath
	}else{
        $currentPath = $parent.Attributes[0].Value + $currentPath
        return GetWebAppFullName $parent $currentPath 
	}
}

Function StopCentrix2AppPools(){
    try{


	$webapps = Get-WebApplication
	$centrix2Path = (Get-Item "..\Install\Centrix2GZ").FullName
    
	foreach ($webApp in $webapps)
	{
		if($webApp.PhysicalPath.StartsWith("$centrix2Path" ,"CurrentCultureIgnoreCase")){
            $appPoolState = Get-WebAppPoolState $webApp.applicationPool
            if($appPoolState.Value -ne 'Stopped'){
				Write-Host 'Stopping app pool ' $webApp.applicationPool
			    Stop-WebAppPool -Name $webApp.applicationPool
            }
		}
	}
	
    }
    catch
    {
	    Write-Host $_.Exception.Message
  
    }

}

Function StartCentrix2AppPools(){
    try{


	$webapps = Get-WebApplication
	$centrix2Path = (Get-Item "..\Install\Centrix2GZ").FullName
    
	foreach ($webApp in $webapps)
	{
		if($webApp.PhysicalPath.StartsWith("$centrix2Path" ,"CurrentCultureIgnoreCase")){
            $appPoolState = Get-WebAppPoolState $webApp.applicationPool
            if($appPoolState.Value -eq 'Stopped'){
				Write-Host 'Starting app pool ' $webApp.applicationPool
			    Start-WebAppPool -Name $webApp.applicationPool
            }
		}
	}
	
    }
    catch
    {
	    Write-Host $_.Exception.Message
  
    }

}