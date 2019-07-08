  
$nugget_exe_source = "C:\Users\bruno.bozic\source\repos\NIAS.PoC.MVC5\NugetExecutable\"
$nuspec_source = "C:\Users\bruno.bozic\source\repos\NIAS.PoC.MVC5\Blink.Infrastructure\"
$built_nuget_packages = "C:\Users\bruno.bozic\source\repos\NIAS.PoC.MVC5\BuiltNugetPackages\"
$push_source = "http://devnuget.blink.hr:88/"
$nuget_gallery_api_key = "oy2mfya4liycnbfr54iap5wcgfmmm3futfehrl24khm7jm"
$base_directory = "C:\Users\bruno.bozic\source\repos\NIAS.PoC.MVC5"
  
function CheckForNugetExe()
{
  if (-Not $nuget -eq "")
  {
      $global:nugetExe = $nuget
  }
  else
  {
      # Assumption, nuget.exe is the current folder where this file is.
      $global:nugetExe = Join-Path $nugget_exe_source "nuget.exe" 
  }

  $global:nugetExe

  if (!(Test-Path $global:nugetExe -PathType leaf))
  {  
     ""
     "**** Nuget file was not found. Please provide the -nuget parameter with the nuget.exe path -or- copy the nuget.exe to the current folder, side-by-side to this powershell file."
     ""
     ""
     throw;
  }
}


function CleanUp()
{
    if ($clean -eq $false)
    {
        return;
    }

    $nupkgFiles = @(Get-ChildItem $built_nuget_packages -Filter *.nupkg)

    if ($nupkgFiles.Count -gt 0)
    {
        "Found " + $nupkgFiles.Count + " *.nupkg files. Lets delete these first..."

        foreach($nupkgFile in $nupkgFiles)
        {
            $combined = Join-Path $built_nuget_packages $nupkgFile
            "... Removing $combined."
            Remove-Item $combined
        }
        
        "... Done!"
    }
}

function PackageTheSpecifications()
{
    ""
    "Getting all *.nuspec files to package in directory: $nuspec_source"

    #$files = Get-ChildItem $nuspec_source -Filter *.nuspec

    #if ($files.Count -eq 0)
    #{
    #    ""
    #    "**** No nuspec files found in the directory: $nuspec_source"
    #    "Terminating process."
    #    throw;
    #}

    #"Found: " + $files.Count + " files"

    $testFiles = Get-ChildItem $base_directory -Recurse -Filter *.nuspec
   
    foreach($file in $testFiles)
    {  

        $directory = (Get-Item -Path $file.FullName).Directory
    
        " #######   Location of nuspec file: " + $directory +"\" +$file

        Write-Host "Fetching most recent nuspec version from the feed: "
        $file_name_without_extension = [System.IO.Path]::GetFileNameWithoutExtension($file.fullname)

        $mostRecentNuspec = (Get-MostRecentNugetSpec $file_name_without_extension $push_source)
        " #######   Most recent nuspec version: " + $mostRecentNuspec

        &dotnet pack --configuration=Debug --output $built_nuget_packages $directory /p:NuspecFile=$directory\$file
        # &dotnet pack --include-symbols --configuration=Debug --output $built_nuget_packages $directory /p:NuspecFile=$directory\$file
    }


}

function PushThePackagesToNuGet()
{
    if ($nuget_gallery_api_key -eq "")
    {
        "@@ No NuGet server api key provided - so not pushing anything up."
        return;
    }


    ""
    "Getting all *.nupkg's files to push to : $push_source"

    $files = Get-ChildItem $built_nuget_packages -Filter *.nupkg

    if ($files.Count -eq 0)
    {
        ""
        "**** No nupkg files found in the directory: $built_nuget_packages"
        "Terminating process."
        throw;
    }

    "Found: " + $files.Count + " files :)"

    foreach($file in $files)
    {
        try{
           &$nugetExe push ($file.FullName) -Source $push_source -apiKey $nuget_gallery_api_key
        }
        catch
        {
           CheckForErrors
        }

        ""
    }
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

       
    }
}

# Fetch latest spec from feed to find out the current version (using the nuget package Id)
function Get-MostRecentNugetSpec($nugetPackageId, $feedSource) {
    $feedUrl= $feedSource + "/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nugetPackageId'"
	$webClient = new-object System.Net.WebClient
    $feedResults = [xml]($webClient.DownloadString($feedUrl))
    $version = $feedResults.feed.entry | %{ $_.properties.version } | sort-object | select -last 1	
  
    if(!$version){
		$version = "0.0"
	}

	$version
}

# Fetch latest package version from the nuspec file
function Get-NuGet-Version($spec) {
    $v = $spec.properties.version."#text"
    if(!$v) {
        $v = $spec.properties.version
    }
    return $v
}

# Increment semantic version of a package by 1
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

function Increment-Version($version){
    $parts = $version.split('.')
    for($i = $parts.length-1; $i -ge 0; $i--){
        $x = ([int]$parts[$i]) + 1
        if($i -ne 0) {
            # Don't roll the previous minor or ref past 10
            if($x -eq 10) {
                $parts[$i] = "0"
                continue
            }
        }
        $parts[$i] = $x.ToString()
        break;
    }
    [System.String]::Join(".", $parts)
}

##############################################################################
##############################################################################
## http://devnuget.blink.hr:88/v1/FeedService.svc/Packages()

$global:nugetExe = ""
$clean = $true

cls

""
" ---------------------- start script ----------------------"
""
""
"  Starting NuGet packing/publishing script -  (╯°□°）╯︵ ┻━┻"
""
"  This script will look for -all- *.nuspec files in a source directory,"
"  then paackage them up to *.nupack files. Finally, it can publish"
"  them to a NuGet server, if an api key was provided."
""

#Enable Debug Messages
$DebugPreference = "Continue"

#Disable Debug Messages
#$DebugPreference = "SilentlyContinue"

#Terminate Code on All Errors
$ErrorActionPreference = "Continue"

#DisplayCommandLineArgs

CheckForNugetExe

CleanUp

PackageTheSpecifications

PushThePackagesToNuGet

""
""
" ---------------------- end of script ----------------------"
""