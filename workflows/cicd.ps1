. "$PSScriptRoot\psutility\common.ps1"

# Check if the secrets file exists before importing
if (Test-Path "$PSScriptRoot/cicd_secrets.ps1") {
    . "$PSScriptRoot\cicd_secrets.ps1"
    Write-Host "Secrets loaded from file."
} else {
    Write-Host "Secrets will be taken from args."
}

$result = Map-DateTimeToUShorts
$currentBranch = Get-GitCurrentBranch
$currentBranchRoot = Get-BranchRoot -BranchName "$currentBranch"
$topLevelDirectory = Get-GitTopLevelDirectory
$nugetSuffix = Get-NuGetSuffix -BranchRoot "$currentBranchRoot"

Ensure-Variable -Variable { $result } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranch } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $currentBranchRoot } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $topLevelDirectory } -ExitIfNullOrEmpty
Ensure-Variable -Variable { $nugetSuffix }
Ensure-Variable -Variable { $NUGET_PAT } -ExitIfNullOrEmpty -HideValue
Ensure-Variable -Variable { $NUGET_TEST_PAT } -ExitIfNullOrEmpty -HideValue

$solutionFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.sln"
#$csprojFiles = Find-FilesByPattern -Path "C:\dev\github.com\carsten-riedel\STROM.ATOM.TOOL.Common\source" -Pattern "*.csproj"

foreach ($solutionFile in $solutionFiles) {

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
    dotnet test $solutionFile.FullName -p:"Stage=test" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After test ==========================================================="

    Write-Output "===> Before pack =========================================================="
    dotnet pack $solutionFile.FullName -p:"Stage=pack" -c Release -p:"HighPart=$($result.HighPart)" -p:"LowPart=$($result.LowPart)" -p:"NugetSuffix=$nugetSuffix"
    Write-Output "===> After pack ==========================================================="

    Write-Output "===> Before publish ======================================================="
    dotnet publish $solutionFile.FullName -p:"Stage=publish" -c Release -p:"HighPart=$($result.HighPart)" -p:"LowPart=$($result.LowPart)"
    Write-Output "===> After publish ========================================================"
}

$basePath = "$topLevelDirectory/source"

$pattern = "*$nugetSuffix.nupkg"


$firstFileMatch = Get-ChildItem -Path $basePath -Filter $pattern -File -Recurse | Select-Object -First 1

if (![string]::IsNullOrEmpty($nugetSuffix)) {
    # When nugetSuffix is not null or empty, push using the test feed.
    # https://int.nugettest.org/
    # dotnet nuget add source https://apiint.nugettest.org/v3/index.json --name NugetTestFeed
    dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_TEST_PAT --source https://apiint.nugettest.org/v3/index.json
}
else {
    # When nugetSuffix is null or empty, push to production.
    #dotnet nuget push "$($firstFileMatch.FullName)" --api-key $NUGET_PAT --source https://api.nuget.org/v3/index.json
}

