. "$PSScriptRoot\psutility\mapper.ps1"
. "$PSScriptRoot\psutility\common.ps1"
. "$PSScriptRoot\psutility\dotnetlist.ps1"

$env:MSBUILDTERMINALLOGGER = "off" # Disables the terminal logger to ensure full build output is displayed in the console

Write-Host "===> Before DOTNET TOOL RESTORE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) ========================================================" -ForegroundColor Cyan
Set-Location "$PSScriptRoot\.."
$LASTEXITCODE = 0
$dotnet = "dotnet"
$dotnetCommand = @("tool","restore","--verbosity","diagnostic")
$arguments = @("--tool-manifest", [System.IO.Path]::Combine("$PSScriptRoot","dotnet-tools.json"))
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
& $dotnet @dotnetCommand @arguments
if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
$elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
Set-Location "$PSScriptRoot"
Write-Host "===> After DOTNET TOOL RESTORE  elapsed after: $elapsed =========================================================" -ForegroundColor Green

# Check if the secrets file exists before importing
if (Test-Path "$PSScriptRoot/cicd_secrets.ps1") {
    . "$PSScriptRoot\cicd_secrets.ps1"
    Write-Host "Secrets loaded from file."
} else {
    $NUGET_GITHUB_PUSH = $args[0]
    $NUGET_PAT = $args[1]
    $NUGET_TEST_PAT = $args[2]
    Write-Host "Secrets will be taken from args."
}


$result = DateTimeVersionConverter64Seconds -VersionBuild 0 -VersionMajor 2
$currentBranch = Get-GitCurrentBranch

#Branch too channel mappings
$branchSegments = Split-Segments -InputString "$currentBranch" -ForbiddenSegments @("latest") -MaxSegments 2
#$channelSegments = Translate-FirstSegment -Segments $branchSegments -TranslationTable @{ "feature" = "development"; "develop" = "quality"; "bugfix" = "quality"; "release" = "staging"; "main" = "production"; "master" = "production"; "hotfix" = "production" } -DefaultTranslation "{nodeploy}"
#$channelSegments = Translate-FirstSegment -Segments $branchSegments -TranslationTable @{ "feature" = "{nodeploy}"; "develop" = "quality"; "bugfix" = "quality"; "release" = "{nodeploy}"; "main" = "production"; "master" = "production"; "hotfix" = "production" } -DefaultTranslation "{nodeploy}"
$channelSegments = Translate-FirstSegment -Segments $branchSegments -TranslationTable @{ "feature" = "local"; "develop" = "quality"; "bugfix" = "quality"; "release" = "staging"; "main" = "production"; "master" = "production"; "hotfix" = "production" } -DefaultTranslation "{nodeploy}"

$branchFolder = Join-Segments -Segments $branchSegments
$branchVersionFolder = Join-Segments -Segments $branchSegments -AppendSegments @( $result.VersionFull )

$channelVersionFolder = Join-Segments -Segments $channelSegments -AppendSegments @( $result.VersionFull )
$channelVersionFolderRoot = Join-Segments -Segments $channelSegments -AppendSegments @( "latest" )

if ($channelSegments.Count -eq 2)
{
    $channelVersionFolderRoot = Join-Segments -Segments $channelSegments[0] -AppendSegments @( "latest" )
}

if (-not $channelVersionFolder.StartsWith("{nodeploy}"))
{
    Write-Output "ChannelVersionFolderRoot to $channelVersionFolderRoot"
}
else {
    $channelVersionFolder = ""
    $channelVersionFolderRoot = ""
}

Write-Output "BranchFolder to $branchFolder"
Write-Output "BranchVersionFolder to $branchVersionFolder"
Write-Output "ChannelVersionFolder to $channelVersionFolder"
Write-Output "ChannelVersionFolderRoot to $channelVersionFolderRoot"

$currentBranchRoot = Get-BranchRoot -BranchName "$currentBranch"
$topLevelDirectory = Get-GitTopLevelDirectory

#Guard for variables
Ensure-Variable -Variable { $result } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranch } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranchRoot } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $topLevelDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $nugetSuffix }
Ensure-Variable -Variable { $NUGET_GITHUB_PUSH } -ExitIfNullOrEmpty -HideValue
Ensure-Variable -Variable { $NUGET_PAT } -ExitIfNullOrEmpty -HideValue
Ensure-Variable -Variable { $NUGET_TEST_PAT } -ExitIfNullOrEmpty -HideValue

#Required directorys
$artifactsOutputFolderName = "artifacts"
$reportsOutputFolderName = "reports"

$outputRootArtifactsDirectory = [System.IO.Path]::Combine($topLevelDirectory, $artifactsOutputFolderName)
$outputRootReportResultsDirectory   = [System.IO.Path]::Combine($topLevelDirectory, $reportsOutputFolderName)


$outputRootPackDirectory = [System.IO.Path]::Combine($topLevelDirectory, $artifactsOutputFolderName, "pack")
$outputRootPublishDirectory = [System.IO.Path]::Combine($topLevelDirectory, $artifactsOutputFolderName, "publish")
$targetDirSetup   = [System.IO.Path]::Combine($topLevelDirectory, $artifactsOutputFolderName, "setup")
$targetConfigAllowedLicenses = [System.IO.Path]::Combine($topLevelDirectory, ".config", "allowed-licenses.json")

Ensure-Variable -Variable { $outputRootArtifactsDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPackDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPublishDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirSetup } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootReportResultsDirectory } -ExitIfNullOrEmpty

Ensure-Variable -Variable { $targetConfigAllowedLicenses } -ExitIfNullOrEmpty

[System.IO.Directory]::CreateDirectory($outputRootArtifactsDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootReportResultsDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootPackDirectory) | Out-Null

[System.IO.Directory]::CreateDirectory($outputRootPublishDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirSetup) | Out-Null



# Get current Git user settings once before the loop
$gitUserLocal = git config user.name
$gitMailLocal = git config user.email

$gitTempUser = "Workflow"
$gitTempMail = "carstenriedel@outlook.com"  # Assuming a placeholder email

git config user.name $gitTempUser
git config user.email $gitTempMail


#Delete-FilesByPattern -Path "$outputRootPackDirectory" -Pattern "*.nupkg"
#$csprojFiles = Find-FilesByPattern -Path "C:\dev\github.com\carsten-riedel\STROM.ATOM.TOOL.Common\source" -Pattern "*.csproj"

$solutionFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.sln"

foreach ($solutionFile in $solutionFiles) {

    $commonSolutionParameters = @(
        "--verbosity","minimal",
        "-p:""VersionBuild=$($result.VersionBuild)""",
        "-p:""VersionMajor=$($result.VersionMajor)""",
        "-p:""VersionMinor=$($result.VersionMinor)""",
        "-p:""VersionRevision=$($result.VersionRevision)"""
    )
  
    Write-Host "===> Before DOTNET CLEAN at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "clean"
    $dotnetSolution = """$($solutionFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $arguments = @("-c", "Release")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetSolution @arguments $dotnetStage @commonSolutionParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET CLEAN elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET RESTORE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =====================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "restore"
    $dotnetSolution = """$($solutionFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetSolution $dotnetStage @commonSolutionParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET RESTORE elapsed after: $elapsed =======================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET BUILD at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "build"
    $dotnetSolution = """$($solutionFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $arguments = @("-c", "Release")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetSolution @arguments $dotnetStage @commonSolutionParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET BUILD elapsed after: $elapsed =========================================================" -ForegroundColor Green
}

$projectFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.csproj"

foreach ($projectFile in $projectFiles) {

    $outputReportDirectory = [System.IO.Path]::Combine($outputRootReportResultsDirectory, "$($projectFile.BaseName)" , "$branchVersionFolder")
    $outputArtifactsDirectory = [System.IO.Path]::Combine($outputRootArtifactsDirectory, "$($projectFile.BaseName)" , "$branchVersionFolder")
    Ensure-Variable -Variable { $outputReportDirectory  } -ExitIfNullOrEmpty
    Ensure-Variable -Variable { $outputArtifactsDirectory  } -ExitIfNullOrEmpty
    [System.IO.Directory]::CreateDirectory($outputReportDirectory) | Out-Null
    [System.IO.Directory]::CreateDirectory($outputArtifactsDirectory) | Out-Null

    $commonProjectParameters = @(
        "--verbosity","minimal",
        "-p:""VersionBuild=$($result.VersionBuild)""",
        "-p:""VersionMajor=$($result.VersionMajor)""",
        "-p:""VersionMinor=$($result.VersionMinor)""",
        "-p:""VersionRevision=$($result.VersionRevision)""",
        "-p:""VersionSuffix=-$($channelSegments[0])""",
        "-p:""BranchFolder=$branchFolder""",
        "-p:""BranchVersionFolder=$branchVersionFolder""",
        "-p:""ChannelVersionFolder=$channelVersionFolder""",
        "-p:""ChannelVersionFolderRoot=$channelVersionFolderRoot""",
        "-p:""OutputReportDirectory=$outputReportDirectory""",
        "-p:""OutputRootPackDirectory=$outputArtifactsDirectory""",
        "-p:""OutputRootPublishDirectory=$outputArtifactsDirectory"""
    )

    Write-Host "===> Before DOTNET CLEAN at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "clean"
    $dotnetProject = """$($projectFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $arguments = @("-c", "Release")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetProject @arguments $dotnetStage @commonProjectParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET CLEAN elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET RESTORE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =====================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "restore"
    $dotnetProject = """$($projectFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetProject $dotnetStage @commonProjectParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET RESTORE elapsed after: $elapsed =======================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET BUILD at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "build"
    $dotnetProject = """$($projectFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $arguments = @("-c", "Release")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetProject @arguments $dotnetStage @commonProjectParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET BUILD elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET LIST VULNERABLE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "list"
    $dotnetProject = "$($projectFile.FullName)"
    $arguments = @("package", "--vulnerable", "--format", "json")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonOutputVulnerable = & $dotnet $dotnetCommand $dotnetProject @arguments  2>&1
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    New-DotnetVulnerabilitiesReport -jsonInput $jsonOutputVulnerable -OutputFile "$outputReportDirectory\ReportVulnerabilities.md" -OutputFormat markdown -ExitOnVulnerability $true
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET LIST VULNERABLE elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET LIST PACKAGE DEPRECATED at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "list"
    $dotnetProject = "$($projectFile.FullName)"
    $arguments = @("package", "--deprecated", "--include-transitive", "--format", "json")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonOutputDeprecated = & $dotnet $dotnetCommand $dotnetProject @arguments
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    New-DotnetDeprecatedReport -jsonInput $jsonOutputDeprecated -OutputFile "$outputReportDirectory\ReportDeprecated.md" -OutputFormat markdown -IgnoreTransitivePackages $true -ExitOnDeprecated $true
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET LIST PACKAGE DEPRECATED elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET LIST PACKAGE OUTDATED at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "list"
    $dotnetProject = "$($projectFile.FullName)"
    $arguments = @("package", "--outdated", "--include-transitive", "--format", "json")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonOutputOutdated = & $dotnet $dotnetCommand $dotnetProject @arguments
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    New-DotnetOutdatedReport -jsonInput $jsonOutputOutdated -OutputFile "$outputReportDirectory\ReportOutdated.md" -OutputFormat markdown -IgnoreTransitivePackages $true
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET LIST PACKAGE OUTDATED elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET LIST PACKAGE BOM at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "list"
    $dotnetProject = "$($projectFile.FullName)"
    $arguments = @("package", "--include-transitive", "--format", "json")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonOutputBom = & $dotnet $dotnetCommand $dotnetProject @arguments
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    New-DotnetBillOfMaterialsReport -jsonInput $jsonOutputBom -OutputFile "$outputReportDirectory\ReportBillOfMaterials.md" -OutputFormat markdown -IgnoreTransitivePackages $true
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()    
    Write-Host "===> After DOTNET LIST PACKAGE BOM elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET nuget-license at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) ===============================================" -ForegroundColor Cyan
    $targetSolutionLicensesJsonFile = [System.IO.Path]::Combine($outputReportDirectory ,"ReportLicenses.json")
    $targetSolutionThirdPartyNoticesFile = [System.IO.Path]::Combine($outputReportDirectory ,"ReportThirdPartyNotices.txt")
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "nuget-license"
    $dotnetProject = @("--input", "$($projectFile.FullName)")
    $arguments = @(
        "--allowed-license-types", "$targetConfigAllowedLicenses",
        "--output","JsonPretty"
        "--file-output","$targetSolutionLicensesJsonFile"
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand @dotnetProject @arguments
    Generate-ThirdPartyNotices -LicenseJsonPath "$targetSolutionLicensesJsonFile" -OutputPath "$targetSolutionThirdPartyNoticesFile"
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET nuget-license elapsed after: $elapsed =================================================" -ForegroundColor Green

    Write-Output "===> Before test =========================================================="
    dotnet test $projectFile.FullName -c Release -p:"Stage=test" @commonProjectParameters
    Write-Output "===> After test =========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before pack =========================================================="
    dotnet pack $projectFile.FullName -p:"Stage=pack" -c Release @commonProjectParameters
    Write-Output "===> After pack =========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before publish ======================================================="
    dotnet publish $projectFile.FullName -p:"Stage=publish" -c Release @commonProjectParameters
    Write-Output "===> After publish ======================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    #$fileItem = Get-Item -Path $targetSolutionThirdPartyNoticesFile
    #$fileName = $fileItem.Name  # Includes extension (e.g., THIRD-PARTY-NOTICES.txt)
    #$destinationPath = Join-Path -Path $topLevelDirectory -ChildPath $fileName
    #Copy-Item -Path $fileItem.FullName -Destination $destinationPath -Force
    
    #git add $destinationPath
    #git commit -m "Updated from Workflow [no ci]"
    #git push origin $currentBranch
}

$stopwatch.Stop()

git config user.name $gitUserLocal
git config user.email $gitMailLocal

$pattern = "*$nugetSuffix.nupkg"

$firstFileMatch = Get-ChildItem -Path $outputRootPackDirectory -Filter $pattern -File -Recurse | Select-Object -First 1

if ($currentBranchRoot.ToLower() -in @("master", "main")) {
    # For branches "master" or "main", push the package to the official NuGet feed.
    # Official NuGet feed: https://api.nuget.org/v3/index.json
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_PAT --source https://api.nuget.org/v3/index.json
    
    dotnet nuget add source --username carsten-riedel --password $NUGET_GITHUB_PUSH --store-password-in-clear-text --name github "https://nuget.pkg.github.com/carsten-riedel/index.json"
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_GITHUB_PUSH --source github
}
elseif ($currentBranchRoot.ToLower() -in @("release")) {
    # For the "release" branch, push the package to the test NuGet feed.
    # Test NuGet feed: https://apiint.nugettest.org/v3/index.json
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_TEST_PAT --source https://apiint.nugettest.org/v3/index.json
    
    dotnet nuget add source --username carsten-riedel --password $NUGET_GITHUB_PUSH --store-password-in-clear-text --name github "https://nuget.pkg.github.com/carsten-riedel/index.json"
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_GITHUB_PUSH --source github
}
else {
    # For all other branches, add the GitHub NuGet feed and push the package there.
    dotnet nuget add source --username carsten-riedel --password $NUGET_GITHUB_PUSH --store-password-in-clear-text --name github "https://nuget.pkg.github.com/carsten-riedel/index.json"
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_GITHUB_PUSH --source github
}

