. "$PSScriptRoot\psutility\mapper.ps1"
. "$PSScriptRoot\psutility\common.ps1"


Set-Location "$PSScriptRoot\.." ; dotnet tool restore; Set-Location "$PSScriptRoot"
dotnet tool list


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


$result = Map-DateTimeToUShorts -VersionBuild 0 -VersionMajor 2
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




$sanitizedBranch = Sanitize-BranchName -BranchName $currentBranch
$currentBranchRoot = Get-BranchRoot -BranchName "$currentBranch"
$topLevelDirectory = Get-GitTopLevelDirectory

#Guard for variables
Ensure-Variable -Variable { $result } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranch } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $sanitizedBranch } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranchRoot } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $topLevelDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $nugetSuffix }
Ensure-Variable -Variable { $NUGET_GITHUB_PUSH } -ExitIfNullOrEmpty -HideValue
Ensure-Variable -Variable { $NUGET_PAT } -ExitIfNullOrEmpty -HideValue
Ensure-Variable -Variable { $NUGET_TEST_PAT } -ExitIfNullOrEmpty -HideValue

#Required directorys
$outputRootTestResultsDirectory = [System.IO.Path]::Combine($topLevelDirectory, "output", "test")
$outputRootPackDirectory = [System.IO.Path]::Combine($topLevelDirectory, "output", "pack")
$outputRootPublishDirectory = [System.IO.Path]::Combine($topLevelDirectory, "output", "publish")
$targetDirSetup   = [System.IO.Path]::Combine($topLevelDirectory, "output", "setup")
$targetDirOutdated   = [System.IO.Path]::Combine($topLevelDirectory, "output", "outdated")
$targetLicenses   = [System.IO.Path]::Combine($topLevelDirectory, "output", "licenses")
$targetConfigAllowedLicenses = [System.IO.Path]::Combine($topLevelDirectory, ".config", "allowed-licenses.json")
Ensure-Variable -Variable { $outputRootTestResultsDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPackDirectory} -ExitIfNullOrEmpty
Ensure-Variable -Variable { $outputRootPublishDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirSetup } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirOutdated } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetLicenses } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetConfigAllowedLicenses } -ExitIfNullOrEmpty
[System.IO.Directory]::CreateDirectory($outputRootTestResultsDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($outputRootPackDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($targetLicenses) | Out-Null
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
    "--verbosity","normal",
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

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($solutionFile in $solutionFiles) {

    Write-Output "===> Before clean ========================================================="
    dotnet clean $solutionFile.FullName -c Release -p:"Stage=clean" @commonParameters
    Write-Output "===> After clean ========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before restore ======================================================="
    dotnet restore $solutionFile.FullName -p:"Stage=restore"
    Write-Output "===> After restore ======================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before build ========================================================="
    dotnet build $solutionFile.FullName -c Release -p:"Stage=build" @commonParameters
    Write-Output "===> After build ========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before test =========================================================="
    dotnet test $solutionFile.FullName -c Release -p:"Stage=test" @commonParameters
    Write-Output "===> After test =========================================================== $($stopwatch.Elapsed)"
    $stopwatch.Restart()

    Write-Output "===> Before nuget-license =================================================="
    $targetSolutionLicensesDir = [System.IO.Path]::Combine($topLevelDirectory, "output", "licenses", "$($solutionFile.BaseName)" , "$branchVersionFolder")
    $targetSolutionLicensesFile = [System.IO.Path]::Combine($targetSolutionLicensesDir ,"licenses.json")
    $targetSolutionLicensesFileOut = [System.IO.Path]::Combine($targetSolutionLicensesDir ,"THIRD-PARTY-NOTICES.txt")
    [System.IO.Directory]::CreateDirectory($targetSolutionLicensesDir) | Out-Null
    dotnet nuget-license --input "$($solutionFile.FullName)" -a "$targetConfigAllowedLicenses" --output JsonPretty --file-output "$targetSolutionLicensesFile"
    Generate-ThirdPartyNotices -LicenseJsonPath "$targetSolutionLicensesFile" -OutputPath "$targetSolutionLicensesFileOut"
    Write-Output "===> After nuget-license =================================================== $($stopwatch.Elapsed)"
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

    dotnet list $solutionFile.FullName package --vulnerable --format json

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

$firstFileMatch = Get-ChildItem -Path $outputPackDirectory-Filter $pattern -File -Recurse | Select-Object -First 1

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



