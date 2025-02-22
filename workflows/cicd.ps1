. "$PSScriptRoot\psutility\mapper.ps1"
. "$PSScriptRoot\psutility\common.ps1"
. "$PSScriptRoot\psutility\dotnetlist.ps1"

$env:MSBUILDTERMINALLOGGER = "off" # Disables the terminal logger to ensure full build output is displayed in the console

Write-Host "===> Before DOTNET TOOL RESTORE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) ========================================================" -ForegroundColor Cyan
Set-Location "$PSScriptRoot\.."
$LASTEXITCODE = 0
$dotnet = "dotnet"
$dotnetCommand = @("tool","restore","--verbosity","diagnostic")
$arguments = @("--tool-manifest", "$PSScriptRoot\dotnet-tools.json")
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
$buildOutputFolderName = "output"
$outputRootLicensesResultsDirectory   = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "licenses")
$outputRootTestResultsDirectory = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "test")
$outputRootPackDirectory = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "pack")
$outputRootPublishDirectory = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "publish")

$targetDirSetup   = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "setup")
$targetDirOutdated   = [System.IO.Path]::Combine($topLevelDirectory, $buildOutputFolderName, "outdated")

$targetConfigAllowedLicenses = [System.IO.Path]::Combine($topLevelDirectory, ".config", "allowed-licenses.json")
Ensure-Variable -Variable { $outputRootTestResultsDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPackDirectory} -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPublishDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirSetup } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirOutdated } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootLicensesResultsDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetConfigAllowedLicenses } -ExitIfNullOrEmpty
[System.IO.Directory]::CreateDirectory($outputRootTestResultsDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootPackDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootLicensesResultsDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootPublishDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirSetup) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirOutdated) | Out-Null


# Get current Git user settings once before the loop
$gitUserLocal = git config user.name
$gitMailLocal = git config user.email

$gitTempUser = "Workflow"
$gitTempMail = "carstenriedel@outlook.com"  # Assuming a placeholder email

git config user.name $gitTempUser
git config user.email $gitTempMail

$solutionFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.sln"
#Delete-FilesByPattern -Path "$outputRootPackDirectory" -Pattern "*.nupkg"
#$csprojFiles = Find-FilesByPattern -Path "C:\dev\github.com\carsten-riedel\STROM.ATOM.TOOL.Common\source" -Pattern "*.csproj"



$commonParameters = @(
    "--verbosity","quiet",
    "-p:""VersionBuild=$($result.VersionBuild)""",
    "-p:""VersionMajor=$($result.VersionMajor)""",
    "-p:""VersionMinor=$($result.VersionMinor)""",
    "-p:""VersionRevision=$($result.VersionRevision)""",
    "-p:""VersionSuffix=-$($channelSegments[0])""",
    "-p:""BranchFolder=$branchFolder""",
    "-p:""BranchVersionFolder=$branchVersionFolder""",
    "-p:""ChannelVersionFolder=$channelVersionFolder""",
    "-p:""ChannelVersionFolderRoot=$channelVersionFolderRoot""",
    "-p:""OutputRootTestResultsDirectory=$outputRootTestResultsDirectory""",
    "-p:""OutputRootPackDirectory=$outputRootPackDirectory""",
    "-p:""OutputRootPublishDirectory=$outputRootPublishDirectory"""
)



foreach ($solutionFile in $solutionFiles) {

    Write-Host "===> Before DOTNET CLEAN at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "clean"
    $dotnetSolution = """$($solutionFile.FullName)"""
    $dotnetStage = "-p:""Stage=$dotnetCommand"""
    $arguments = @("-c", "Release")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand $dotnetSolution @arguments $dotnetStage @commonParameters
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
    & $dotnet $dotnetCommand $dotnetSolution $dotnetStage @commonParameters
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
    & $dotnet $dotnetCommand $dotnetSolution @arguments $dotnetStage @commonParameters
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET BUILD elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Host "===> Before DOTNET LIST VULNERABLE at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) =======================================================" -ForegroundColor Cyan
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "list"
    $dotnetSolution = "$($solutionFile.FullName)"
    $arguments = @("package", "--vulnerable", "--format", "json")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonOutputVulnerable = & $dotnet $dotnetCommand $dotnetSolution @arguments  2>&1
    #New-DotnetVulnerabilitiesReport -jsonInput $jsonOutputVulnerable -OutputFile "C:\temp\testv.md" -OutputFormat markdown -ProjectBlacklist @("STROM.ATOM.TOOL.Common.Tests") -ExitOnVulnerability $true
    New-DotnetVulnerabilitiesReport -jsonInput $jsonOutputVulnerable -ProjectBlacklist @("STROM.ATOM.TOOL.Common.Tests") -ExitOnVulnerability $true
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET LIST VULNERABLE elapsed after: $elapsed =========================================================" -ForegroundColor Green

    Write-Output "===> Before vulnerable ======================================================="
    dotnet list $solutionFile.FullName package --vulnerable --format json
    $jsonOutputVulnerable = & dotnet list $solutionFile.FullName package --vulnerable --include-transitive  --format json 2>&1
    #$jsonOutputOutdated = & dotnet list $solutionFile.FullName package --outdated --include-transitive  --format json 2>&1
    #$jsonOutputDeprecated = & dotnet list $solutionFile.FullName package --deprecated --include-transitive  --format json 2>&1
    $jsonOutputBom = & dotnet list $solutionFile.FullName package --include-transitive --format json 2>&1
    $joinedString = $jsonOutputBom -join "`r`n"
    New-DotnetBillOfMaterialsReport -jsonInput $jsonOutputBom -OutputFile "C:\temp\test.md" -OutputFormat markdown -ProjectBlacklist @("STROM.ATOM.TOOL.Common.Tests") -IgnoreTransitivePackages $true
    New-DotnetVulnerabilitiesReport -jsonInput $jsonOutputVulnerable -OutputFile "C:\temp\testv.md" -OutputFormat markdown -ExitOnVulnerability $true
    Write-Output "===> After vulnerable ======================================================= $($stopwatch.Elapsed)"


    Write-Host "===> Before DOTNET nuget-license at $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) (UTC) ===============================================" -ForegroundColor Cyan
    $targetSolutionLicensesDirectory = [System.IO.Path]::Combine($outputRootLicensesResultsDirectory, "$($solutionFile.BaseName)" , "$branchVersionFolder")
    $targetSolutionLicensesJsonFile = [System.IO.Path]::Combine($targetSolutionLicensesDirectory ,"licenses.json")
    $targetSolutionThirdPartyNoticesFile = [System.IO.Path]::Combine($targetSolutionLicensesDirectory ,"THIRD-PARTY-NOTICES.txt")
    [System.IO.Directory]::CreateDirectory($targetSolutionLicensesDirectory) | Out-Null
    $LASTEXITCODE = 0
    $dotnet = "dotnet"
    $dotnetCommand = "nuget-license"
    $dotnetSolution = @("--input", "$($solutionFile.FullName)")
    $arguments = @(
        "--allowed-license-types", "$targetConfigAllowedLicenses",
        "--output","JsonPretty"
        "--file-output","$targetSolutionLicensesJsonFile"
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $dotnetCommand @dotnetSolution @arguments
    Generate-ThirdPartyNotices -LicenseJsonPath "$targetSolutionLicensesJsonFile" -OutputPath "$targetSolutionThirdPartyNoticesFile"
    if ($LASTEXITCODE -ne 0) { Write-Error "Command failed with exit code $LASTEXITCODE. Exiting script." -ForegroundColor Red ; exit $LASTEXITCODE }
    $elapsed = $stopwatch.Elapsed.ToString("hh\:mm\:ss\.fff") ; $stopwatch.Stop()
    Write-Host "===> After DOTNET nuget-license elapsed after: $elapsed =================================================" -ForegroundColor Green
    

    Write-Output "===> Before test =========================================================="
    dotnet test $solutionFile.FullName -c Release -p:"Stage=test" @commonParameters
    Write-Output "===> After test =========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before pack =========================================================="
    dotnet pack $solutionFile.FullName -p:"Stage=pack" -c Release @commonParameters
    Write-Output "===> After pack =========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before publish ======================================================="
    dotnet publish $solutionFile.FullName -p:"Stage=publish" -c Release @commonParameters
    Write-Output "===> After publish ======================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before outdated ======================================================="
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.md" --output-format Markdown
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.json" --output-format json
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.csv" --output-format csv
    Write-Output "===> After outdated ======================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    $fileItem = Get-Item -Path $targetSolutionLicensesFileOut
    $fileName = $fileItem.Name  # Includes extension (e.g., THIRD-PARTY-NOTICES.txt)
    $destinationPath = Join-Path -Path $topLevelDirectory -ChildPath $fileName
    Copy-Item -Path $fileItem.FullName -Destination $destinationPath -Force
    
    git add $destinationPath
    git commit -m "Updated from Workflow [no ci]"
    git push origin $currentBranch
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

