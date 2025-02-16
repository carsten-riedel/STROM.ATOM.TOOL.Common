
. "$PSScriptRoot\psutility\common.ps1"

$result = Map-DateTimeToUShorts

$currentBranch = Get-GitCurrentBranch
$currentBranchRoot = Get-BranchRoot -BranchName "$currentBranch"
$topLevelDirectory = Get-GitTopLevelDirectory

$nugetSuffix = Get-NuGetSuffix -BranchRoot "$currentBranchRoot"

Write-Output "$($result.HighPart)"
Write-Output "$($result.LowPart)"

Write-Output "$currentBranch"
Write-Output "$currentBranchRoot"
Write-Output "$topLevelDirectory"
Write-Output "$nugetSuffix"

$solutionFiles = Find-FilesByPattern -Path "$topLevelDirectory\source" -Pattern "*.sln"
#$csprojFiles = Find-FilesByPattern -Path "C:\dev\github.com\carsten-riedel\STROM.ATOM.TOOL.Common\source" -Pattern "*.csproj"



foreach ($solutionFile in $solutionFiles) {
    Write-Output $solutionFile.Directory
    Write-Output $solutionFile.FullName


    Write-Output "===> Before clean ========================================================="
    dotnet clean $solutionFile.FullName -p:"Stage=clean" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After clean =========================================================="

    Write-Output "===> Before restore ======================================================="
    dotnet restore $solutionFile.FullName -p:"Stage=restore" -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After restore ========================================================"

    Write-Output "===> Before build ========================================================="
    dotnet build $solutionFile.FullName -p:"Stage=build" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After build =========================================================="

    Write-Output "===> Before pack =========================================================="
    dotnet pack $solutionFile.FullName -p:"Stage=pack" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After pack ==========================================================="

    Write-Output "===> Before publish ======================================================="
    dotnet publish $solutionFile.FullName -p:"Stage=publish" -c Release -p:HighPart=$($result.HighPart) -p:LowPart=$($result.LowPart)
    Write-Output "===> After publish ========================================================"
}

