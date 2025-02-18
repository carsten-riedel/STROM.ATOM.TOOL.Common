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


$result = Map-DateTimeToUShorts
$currentBranch = Get-GitCurrentBranch
$sanitizedBranch = Sanitize-BranchName -BranchName $currentBranch
$currentBranchRoot = Get-BranchRoot -BranchName "$currentBranch"
$topLevelDirectory = Get-GitTopLevelDirectory
$nugetSuffix = Get-NuGetSuffix -BranchRoot "$currentBranchRoot"

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
$targetDirPack    = [System.IO.Path]::Combine($topLevelDirectory, "output", "pack")
$targetDirPublish = [System.IO.Path]::Combine($topLevelDirectory, "output", "publish")
$targetDirSetup   = [System.IO.Path]::Combine($topLevelDirectory, "output", "setup")
$targetDirTest   = [System.IO.Path]::Combine($topLevelDirectory, "output", "test")
$targetDirOutdated   = [System.IO.Path]::Combine($topLevelDirectory, "output", "outdated")
$targetLicenses   = [System.IO.Path]::Combine($topLevelDirectory, "output", "licenses")
Ensure-Variable -Variable { $targetDirPack } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirPublish } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirSetup } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirTest } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetDirOutdated } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $targetLicenses } -ExitIfNullOrEmpty
[System.IO.Directory]::CreateDirectory($targetDirPack) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirPublish) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirSetup) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirTest) | Out-Null
[System.IO.Directory]::CreateDirectory($targetDirOutdated) | Out-Null
[System.IO.Directory]::CreateDirectory($targetLicenses) | Out-Null

$solutionFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.sln"
Delete-FilesByPattern -Path "$targetDirPack" -Pattern "*.nupkg"
#$csprojFiles = Find-FilesByPattern -Path "C:\dev\github.com\carsten-riedel\STROM.ATOM.TOOL.Common\source" -Pattern "*.csproj"

foreach ($solutionFile in $solutionFiles) {

    Write-Output "===> Before nuget-license =================================================="
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($topLevelDirectory, "output", "licenses", "$($solutionFile.BaseName)")) | Out-Null
    dotnet nuget-license --input "$($solutionFile.FullName)" -a "$($topLevelDirectory)\.config\allowed-licenses.json" --output Table --file-output "$targetLicenses\$($solutionFile.BaseName)\licenses.txt"
    dotnet nuget-license --input "$($solutionFile.FullName)" -a "$($topLevelDirectory)\.config\allowed-licenses.json" --output JsonPretty --file-output "$targetLicenses\$($solutionFile.BaseName)\licenses.json"
    Write-Output "===> After nuget-license ==================================================="
    Generate-ThirdPartyNotices -LicenseJsonPath "$targetLicenses\$($solutionFile.BaseName)\licenses.json" -OutputPath "$targetLicenses\$($solutionFile.BaseName)\THIRD-PARTY-NOTICES.txt"

    Write-Output "===> Before clean ========================================================="
    dotnet clean $solutionFile.FullName -p:"Stage=clean" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After clean =========================================================="

    Write-Output "===> Before restore ======================================================="
    dotnet restore $solutionFile.FullName -p:"Stage=restore" -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After restore ========================================================"

    Write-Output "===> Before build ========================================================="
    dotnet build $solutionFile.FullName -p:"Stage=build" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After build =========================================================="

    Write-Output "===> Before test =========================================================="
    dotnet test $solutionFile.FullName -p:"Stage=test" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart) -p:"TargetDirTest=$targetDirTest" -p:"SanitizedBranch=$sanitizedBranch"
    Write-Output "===> After test ==========================================================="

    Write-Output "===> Before pack =========================================================="
    dotnet pack $solutionFile.FullName -p:"Stage=pack" -c Release -p:"HighPart=$($result.HighPart)" -p:"LowPart=$($result.LowPart)" -p:"TargetDirPack=$targetDirPack" -p:"SanitizedBranch=$sanitizedBranch" -p:"NugetSuffix=$nugetSuffix"
    Write-Output "===> After pack ==========================================================="

    Write-Output "===> Before publish ======================================================="
    dotnet publish $solutionFile.FullName -p:"Stage=publish" -c Release -p:"HighPart=$($result.HighPart)" -p:"LowPart=$($result.LowPart)" -p:"TargetDirPublish=$targetDirPublish" -p:"SanitizedBranch=$sanitizedBranch" -p:"TargetDirSetup=$targetDirSetup"
    Write-Output "===> After publish ========================================================"

    Write-Output "===> Before outdated ======================================================="
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.md" --output-format Markdown
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.json" --output-format json
    dotnet dotnet-outdated "$($solutionFile.FullName)" --no-restore --output "$targetDirOutdated\outdated.csv" --output-format csv
    Write-Output "===> After outdated ========================================================"

    Write-Output "===> Before nuget-license =================================================="
    dotnet nuget-license --input "$($solutionFile.FullName)" -a "$(topLevelDirectory)/.config/allowed-licenses.json" --output Table --file-output "$targetLicenses\licenses.txt"
    dotnet nuget-license --input "$($solutionFile.FullName)" -a "$(topLevelDirectory)/.config/allowed-licenses.json" --output JsonPretty --file-output "$targetLicenses\licenses.json"
    Write-Output "===> After nuget-license ==================================================="
}

# Get current Git user settings once before the loop
$gitUserLocal = & git config user.name
$gitMailLocal = & git config user.email

# Set temporary user for workflow commits
$gitTempUser = "Workflow"
$gitTempMail = "carstenriedel@outlook.com"  # Assuming a placeholder email

foreach ($solutionFile in $solutionFiles) {
    # Define paths
    $sourcePath = "$targetLicenses\$($solutionFile.BaseName)\THIRD-PARTY-NOTICES.txt"
    $destinationPath = "$(topLevelDirectory)\$($solutionFile.BaseName)_THIRD-PARTY-NOTICES.txt"

    # Copy the file (overwrite if exists)
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
        Write-Host "Copied: $sourcePath → $destinationPath"
    } else {
        Write-Host "Source file not found: $sourcePath" -ForegroundColor Red
        continue  # Skip this iteration if the file doesn't exist
    }

    # Set temporary Git user
    git config user.name $gitTempUser
    git config user.email $gitTempMail

    # Git operations
    git add $destinationPath
    git commit -m "Updated from Workflow [no ci]"
    
    if ($?) {  # Check if commit was successful
        git push origin $currentBranch
        Write-Host "Changes pushed to branch: $currentBranch"
    } else {
        Write-Host "Commit failed, skipping push." -ForegroundColor Red
    }

    # Restore original Git user
    & git config user.name $gitUserLocal
    & git config user.email $gitMailLocal
}

exit 1

$pattern = "*$nugetSuffix.nupkg"

$firstFileMatch = Get-ChildItem -Path $targetDirPack -Filter $pattern -File -Recurse | Select-Object -First 1

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


