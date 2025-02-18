<#
.SYNOPSIS
    Maps a DateTime to two string-encoded parts based on elapsed seconds since the start of the year.

.DESCRIPTION
    This function computes the total seconds elapsed since January 1st of the provided DateTime's year, discards the lower 6 bits (i.e. each increment in the low part represents 64 seconds), and splits the result into:
      - LowPart: The lower 16 bits (computed as the remainder modulo 65536).
      - HighPart: The upper bits combined with a year-based offset (year multiplied by 10).
    The function supports years only up to 6553.

.PARAMETER InputDate
    An optional DateTime value. If not provided, the current date/time (Get-Date) is used.
    The year of the InputDate must not exceed 6553.

.EXAMPLE
    PS C:\> $result = Map-DateTimeToUShorts -InputDate (Get-Date "2025-05-01")
    PS C:\> $result
    Name                           Value
    ----                           -----
    HighPart                       20250
    LowPart                        1234
#>
function Map-DateTimeToUShorts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [datetime]$InputDate = (Get-Date)
    )

    # Number of bits to discard (i.e. one low part unit equals 64 seconds)
    $discardBits = 6

    $now = $InputDate

    if ($now.Year -gt 6553) {
        throw "Year must not be greater than 6553."
    }

    # Calculate the start of the current year
    $startOfYear = [datetime]::new($now.Year, 1, 1, 0, 0, 0, $now.Kind)
    
    # Compute total seconds elapsed since the start of the year
    $seconds = [int](([timespan]($now - $startOfYear)).TotalSeconds)
    
    # Discard the lower 6 bits by integer division by 64
    $computedLow = [int]($seconds / 64)
    
    # LowPart: lower 16 bits of computedLow (simulate ushort by modulo 65536)
    $low = $computedLow % 65536
    
    # HighPart: remaining bits from computedLow (simulate right-shift by 16)
    $high = [int]($computedLow / 65536)
    
    # Composite high part: combine high with a year offset (year multiplied by 10)
    $highPartFull = $high + ($now.Year * 10)
    
    # Return a hashtable with both parts as strings
    return @{
        HighPart = $highPartFull.ToString();
        LowPart  = $low.ToString()
    }
}

<#
.SYNOPSIS
    Recursively searches a directory for files matching a specified filename pattern.
.DESCRIPTION
    This function searches the specified directory and all its subdirectories for files that match
    the given filename pattern (e.g., *.sln or *.csproj). It returns an array of matching FileInfo objects,
    which can be iterated with a ForEach loop.
.PARAMETER Path
    The root directory where the search should begin.
.PARAMETER Pattern
    The filename pattern to search for (e.g., "*.sln" or "*.csproj").
.EXAMPLE
    $files = Find-ProjectFiles -Path "C:\MyProjects" -Pattern "*.csproj"
    foreach ($file in $files) {
        Write-Output $file.FullName
    }
#>
<#
.SYNOPSIS
    Recursively searches a directory for files matching a specified pattern.
.DESCRIPTION
    This function searches the specified directory and all its subdirectories for files
    that match the provided filename pattern (e.g., "*.txt", "*.sln", "*.csproj").
    It returns an array of matching FileInfo objects, which can be iterated with a ForEach loop.
.PARAMETER Path
    The root directory where the search should begin.
.PARAMETER Pattern
    The filename pattern to search for (e.g., "*.txt", "*.sln", "*.csproj").
.EXAMPLE
    $files = Find-FilesByPattern -Path "C:\MyProjects" -Pattern "*.txt"
    foreach ($file in $files) {
        Write-Output $file.FullName
    }
#>
function Find-FilesByPattern {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    # Validate that the provided path exists and is a directory.
    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "The specified path '$Path' does not exist or is not a directory."
    }

    try {
        # Recursively search for files matching the given pattern.
        $results = Get-ChildItem -Path $Path -Filter $Pattern -Recurse -File -ErrorAction Stop
        return $results
    }
    catch {
        Write-Error "An error occurred while searching for files: $_"
    }
}

function Delete-FilesByPattern {
    <#
    .SYNOPSIS
        Deletes files matching a specified pattern and optionally removes empty directories.

    .DESCRIPTION
        This function recursively searches for files under the given path that match the provided
        pattern and deletes them. After deleting the files, if the optional parameter 'DeleteEmptyDirs'
        is set to $true (default), it will also remove any directories that become empty as a result
        of the deletions.

    .PARAMETER Path
        The directory path in which to search for files.

    .PARAMETER Pattern
        The file search pattern (e.g., "*.log", "*.tmp").

    .PARAMETER DeleteEmptyDirs
        Optional. If set to $true (default), any directories that become empty after deletion are removed.

    .EXAMPLE
        PS> Delete-FilesByPattern -Path "C:\Temp" -Pattern "*.log"
        Deletes all .log files under C:\Temp and its subdirectories, and then removes any empty directories.

    .NOTES
        Ensure you have the necessary permissions to delete files and directories.
    #>

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter()]
        [bool]$DeleteEmptyDirs = $true
    )

    # Validate that the provided path exists and is a directory.
    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "The specified path '$Path' does not exist or is not a directory."
    }

    try {
        # Recursively search for files matching the given pattern.
        $files = Get-ChildItem -Path $Path -Filter $Pattern -Recurse -File -ErrorAction Stop
        foreach ($file in $files) {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            Write-Verbose "Deleted file: $($file.FullName)"
        }

        if ($DeleteEmptyDirs) {
            # Get all directories under $Path in descending order by depth.
            $dirs = Get-ChildItem -Path $Path -Directory -Recurse | Sort-Object {
                $_.FullName.Split([System.IO.Path]::DirectorySeparatorChar).Count
            } -Descending

            foreach ($dir in $dirs) {
                # Check if directory is empty.
                if (-not (Get-ChildItem -Path $dir.FullName -Force)) {
                    Remove-Item -Path $dir.FullName -Force -ErrorAction SilentlyContinue
                    Write-Verbose "Deleted empty directory: $($dir.FullName)"
                }
            }
        }
    }
    catch {
        Write-Error "An error occurred while deleting files or directories: $_"
    }
}


function Get-GitCurrentBranch {
    <#
    .SYNOPSIS
    Retrieves the current Git branch name.

    .DESCRIPTION
    This function calls Git to determine the current branch. It first uses
    'git rev-parse --abbrev-ref HEAD' to get the branch name. If the output is
    "HEAD" (indicating a detached HEAD state), it then attempts to find a branch
    that contains the current commit using 'git branch --contains HEAD'. If no
    branch is found, it falls back to returning the commit hash.

    .EXAMPLE
    PS C:\> Get-GitCurrentBranch

    Returns:
    master

    .NOTES
    - Ensure Git is available in your system's PATH.
    - In cases of a detached HEAD with multiple containing branches, the first
      branch found is returned.
    #>

    try {
        # Get the abbreviated branch name
        $branch = git rev-parse --abbrev-ref HEAD 2>$null

        # If HEAD is returned, we're in a detached state.
        if ($branch -eq 'HEAD') {
            # Try to get branch names that contain the current commit.
            $branches = git branch --contains HEAD 2>$null | ForEach-Object {
                # Remove any asterisks or leading/trailing whitespace.
                $_.Replace('*','').Trim()
            } | Where-Object { $_ -ne '' }

            if ($branches.Count -gt 0) {
                # Return the first branch found
                return $branches[0]
            }
            else {
                # As a fallback, return the commit hash.
                return git rev-parse HEAD 2>$null
            }
        }
        else {
            return $branch.Trim()
        }
    }
    catch {
        Write-Error "Error retrieving Git branch: $_"
    }
}

function Get-GitTopLevelDirectory {
    <#
    .SYNOPSIS
        Retrieves the top-level directory of the current Git repository.

    .DESCRIPTION
        This function calls Git using 'git rev-parse --show-toplevel' to determine
        the root directory of the current Git repository. If Git is not available
        or the current directory is not within a Git repository, the function returns
        an error. The function converts any forward slashes to the system's directory
        separator (works correctly on both Windows and Linux).

    .EXAMPLE
        PS C:\Projects\MyRepo> Get-GitTopLevelDirectory
        C:\Projects\MyRepo

    .NOTES
        Ensure Git is installed and available in your system's PATH.
    #>

    try {
        # Attempt to retrieve the top-level directory of the Git repository.
        $topLevel = git rev-parse --show-toplevel 2>$null

        if (-not $topLevel) {
            Write-Error "Not a Git repository or Git is not available in the PATH."
            return $null
        }

        # Trim the result and replace forward slashes with the current directory separator.
        $topLevel = $topLevel.Trim().Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        return $topLevel
    }
    catch {
        Write-Error "Error retrieving Git top-level directory: $_"
    }
}


function Get-BranchRoot {
    <#
    .SYNOPSIS
    Extracts the root segment from a Git branch name.

    .DESCRIPTION
    This function splits the provided branch name by the '/' delimiter and returns the first segment.
    For branch names without a '/', it returns the original branch name.

    .PARAMETER BranchName
    The full branch name (e.g., "feature/integreateupdates/fsdd" or "master").

    .EXAMPLE
    PS C:\> Get-BranchRoot -BranchName "feature/integreateupdates/fsdd"
    Returns: feature

    .EXAMPLE
    PS C:\> Get-BranchRoot -BranchName "master"
    Returns: master

    .NOTES
    Ensure that the branch name is correctly passed as a string.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    if (-not $BranchName) {
        Write-Error "BranchName cannot be empty."
        return $null
    }

    # Split the branch name by '/' and return the first part.
    $parts = $BranchName.Split('/')
    return $parts[0]
}

function Get-NuGetSuffix {
    <#
    .SYNOPSIS
    Maps a Git branch root to a NuGet package suffix.

    .DESCRIPTION
    This function maps the provided Git branch root (e.g., "feature", "develop") to a NuGet package suffix.
    For branch roots named 'main' or 'master', it returns an empty string. For all other branch roots,
    it returns the suffix by prefixing the branch root with a hyphen.

    .PARAMETER BranchRoot
    The root of the Git branch (e.g., "feature", "develop", "master").

    .EXAMPLE
    PS C:\> Get-NuGetSuffix -BranchRoot "feature"
    Returns: -feature

    .EXAMPLE
    PS C:\> Get-NuGetSuffix -BranchRoot "master"
    Returns: 

    .NOTES
    This mapping assumes that the 'main' and 'master' branches do not require a suffix,
    while all other branch roots are suffixed.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$BranchRoot
    )

    if ([string]::IsNullOrWhiteSpace($BranchRoot)) {
        Write-Error "BranchRoot cannot be empty."
        return $null
    }

    switch ($BranchRoot.ToLower()) {
        'main' { return "" }
        'master' { return "" }
        default { return "-$BranchRoot" }
    }
}


function Ensure-Variable {
    <#
    .SYNOPSIS
    Ensures a variable meets conditions and displays its details.

    .DESCRIPTION
    Accepts a script block containing a simple variable reference (e.g. { $currentBranch }),
    extracts the variable's name from the AST, evaluates its value, and displays both in one line.
    The -HideValue switch suppresses the actual value by displaying "[Hidden]". When -ExitIfNullOrEmpty
    is specified, the function exits with code 1 if the variable's value is null, an empty string,
    or (in the case of a hashtable) empty.

    .PARAMETER Variable
    A script block that must contain a simple variable reference.

    .PARAMETER HideValue
    If specified, the displayed value will be replaced with "[Hidden]".

    .PARAMETER ExitIfNullOrEmpty
    If specified, the function exits with code 1 when the variable's value is null or empty.

    .EXAMPLE
    $currentBranch = "develop"
    Ensure-Variable -Variable { $currentBranch }
    # Output: Variable Name: currentBranch, Value: develop

    .EXAMPLE
    $currentBranch = ""
    Ensure-Variable -Variable { $currentBranch } -ExitIfNullOrEmpty
    # Outputs an error and exits with code 1.

    .EXAMPLE
    $myHash = @{ Key1 = "Value1"; Key2 = "Value2" }
    Ensure-Variable -Variable { $myHash }
    # Output: Variable Name: myHash, Value: {"Key1":"Value1","Key2":"Value2"}

    .NOTES
    The script block must contain a simple variable reference for the AST extraction to work correctly.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Variable,
        
        [switch]$HideValue,
        
        [switch]$ExitIfNullOrEmpty
    )

    # Extract variable name from the script block's AST.
    $ast = $Variable.Ast
    $varAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
    if (-not $varAst) {
        Write-Error "The script block must contain a simple variable reference."
        return
    }
    $varName = $varAst.VariablePath.UserPath

    # Evaluate the script block to get the variable's value.
    $value = & $Variable

    # Check if the value is null or empty and exit if required.
    if ($ExitIfNullOrEmpty) {
        if ($null -eq $value) {
            Write-Error "Variable '$varName' is null."
            exit 1
        }
        if (($value -is [string]) -and [string]::IsNullOrEmpty($value)) {
            Write-Error "Variable '$varName' is an empty string."
            exit 1
        }
        if ($value -is [hashtable] -and ($value.Count -eq 0)) {
            Write-Error "Variable '$varName' is an empty hashtable."
            exit 1
        }
    }

    # Prepare the display value.
    if ($HideValue) {
        $displayValue = "[Hidden]"
    }
    else {
        if ($value -is [hashtable]) {
            # Convert the hashtable to a compact JSON string for one-line output.
            $displayValue = $value | ConvertTo-Json -Compress
        }
        else {
            $displayValue = $value
        }
    }

    Write-Output "Variable Name: $varName, Value: $displayValue"
}

<#
.SYNOPSIS
    Sanitizes a branch name for use as a directory name.

.DESCRIPTION
    This function takes a branch name string, replaces invalid filename characters 
    (as determined by System.IO.Path.GetInvalidFileNameChars) with underscores, 
    and converts forward slashes (/) into the current directory separator 
    (obtained via System.IO.Path.DirectorySeparatorChar).

.PARAMETER BranchName
    The branch name string to sanitize.

.EXAMPLE
    PS> $sanitizedBranch = Sanitize-BranchName -BranchName "feature/some/branch"
    PS> Write-Host $sanitizedBranch
#>
function Sanitize-BranchName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    # Get the invalid file name characters
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

    # Start with the original branch name
    $sanitized = $BranchName

    # Replace each invalid character with an underscore
    foreach ($char in $invalidChars) {
        $pattern = [Regex]::Escape($char)
        $sanitized = $sanitized -replace $pattern, "_"
    }

    # Replace forward slashes with the current directory separator
    $dirSep = [System.IO.Path]::DirectorySeparatorChar
    $sanitized = $sanitized -replace '/', $dirSep

    return $sanitized
}

function Generate-ThirdPartyNotices {
    <#
    .SYNOPSIS
    Generates a visually formatted THIRD-PARTY-NOTICES.txt file from a NuGet license JSON.

    .DESCRIPTION
    Reads the `licenses.json` generated by `dotnet nuget-license` and extracts
    package name, version, license type, URL, and authors. It formats them
    into a structured THIRD-PARTY-NOTICES.txt file.

    If any package contains `ValidationErrors`, the script will throw an error and exit.

    .PARAMETER LicenseJsonPath
    Path to the JSON file containing NuGet license information.

    .PARAMETER OutputPath
    Path where the THIRD-PARTY-NOTICES.txt file should be created.

    .EXAMPLE
    Generate-ThirdPartyNotices -LicenseJsonPath "licenses.json" -OutputPath "THIRD-PARTY-NOTICES.txt"

    Generates a THIRD-PARTY-NOTICES.txt file based on `licenses.json`.
    #>
    param(
        [string]$LicenseJsonPath = "licenses.json",
        [string]$OutputPath = "THIRD-PARTY-NOTICES.txt"
    )

    if (!(Test-Path $LicenseJsonPath)) {
        Write-Host "Error: License JSON file not found at $LicenseJsonPath" -ForegroundColor Red
        exit 1
    }

    # Read and parse JSON
    $licenses = Get-Content $LicenseJsonPath | ConvertFrom-Json

    # Check for validation errors
    $hasErrors = $false
    foreach ($package in $licenses) {
        if ($package.ValidationErrors.Count -gt 0) {
            $hasErrors = $true
            Write-Host "License validation error in package: $($package.PackageId) - $($package.PackageVersion)" -ForegroundColor Red
            foreach ($error in $package.ValidationErrors) {
                Write-Host "   $error" -ForegroundColor Yellow
            }
        }
    }

    if ($hasErrors) {
        Write-Host "Exiting due to license validation errors." -ForegroundColor Red
        exit 1
    }

    # Prepare the notice text
    $notices = @()
    $notices += "============================================"
    $notices += "          THIRD-PARTY LICENSE NOTICES       "
    $notices += "============================================"
    $notices += "`nThis project includes third-party libraries under open-source licenses.`n"

    foreach ($package in $licenses) {
        $name = $package.PackageId
        $version = $package.PackageVersion
        $license = $package.License
        $url = $package.LicenseUrl
        $authors = $package.Authors
        $packageProjectUrl = $package.PackageProjectUrl

        $notices += "--------------------------------------------"
        $notices += "📦 Package: $name (v$version)"
        $notices += "🔖 License: $license"
        if ($url) { $notices += "🌍 License URL: $url" }
        if ($authors) { $notices += "👤 Authors: $authors" }
        if ($packageProjectUrl) { $notices += "🔗 Project: $packageProjectUrl" }
        $notices += "--------------------------------------------`n"
    }

    # Write to file
    $notices | Out-File -Encoding utf8 $OutputPath

    Write-Host "THIRD-PARTY-NOTICES.txt generated at: $OutputPath" -ForegroundColor Green
}

