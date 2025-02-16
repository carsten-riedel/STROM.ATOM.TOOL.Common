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
    or the current directory is not within a Git repository, the function
    returns an error.

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

        return $topLevel.Trim()
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


