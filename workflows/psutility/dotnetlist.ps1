function New-DotnetBillOfMaterialsReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Array of JSON strings output from dotnet list command.")]
        [string[]]$jsonInput,

        [Parameter(Mandatory = $false, HelpMessage = "Optional file path to save the output.")]
        [string]$OutputFile,

        [Parameter(Mandatory = $false, HelpMessage = "Output format: 'text' or 'markdown'. Defaults to 'text'.")]
        [ValidateSet("text", "markdown")]
        [string]$OutputFormat = "text",

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, transitive packages are ignored. Defaults to true.")]
        [bool]$IgnoreTransitivePackages = $true,

        [Parameter(Mandatory = $false, HelpMessage = "Aggregates the output by grouping on ProjectName, Package, and ResolvedVersion, and optionally PackageType. Defaults to true.")]
        [bool]$Aggregate = $true,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, the aggregated output includes PackageType. Defaults to false.")]
        [bool]$IncludePackageType = $false,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, a professional title is generated and prepended to the output. Defaults to true.")]
        [bool]$GenerateTitle = $true,

        [Parameter(Mandatory = $false, HelpMessage = "Overrides the generated markdown title with a custom title. Only applied when OutputFormat is markdown.")]
        [string]$SetMarkDownTitle,

        [Parameter(Mandatory = $false, HelpMessage = "Array of ProjectNames to always include in the output.")]
        [string[]]$ProjectWhitelist,

        [Parameter(Mandatory = $false, HelpMessage = "Array of ProjectNames to exclude from the output unless they are also in the whitelist.")]
        [string[]]$ProjectBlacklist
    )

    <#
    .SYNOPSIS
    Generates a professional Bill of Materials (BOM) report from dotnet list JSON output.

    .DESCRIPTION
    Processes JSON input from the dotnet list command to extract project, framework, and package information.
    Each package entry is tagged as "TopLevel" or "Transitive". Optionally, transitive packages can be ignored.
    The function supports aggregation, which groups entries by ProjectName, Package, and ResolvedVersion (and optionally PackageType).
    Additionally, a professional title is generated (if enabled via -GenerateTitle) that lists the projects included in the report.
    When OutputFormat is markdown, the title is rendered as an H2 header, or can be overridden via -SetMarkDownTitle.
    BOM entries can also be filtered using project whitelist and blacklist parameters.

    .PARAMETER jsonInput
    Array of JSON strings output from the dotnet list command.

    .PARAMETER OutputFile
    Optional file path to save the output.

    .PARAMETER OutputFormat
    Specifies the output format: 'text' or 'markdown'. Defaults to 'text'.

    .PARAMETER IgnoreTransitivePackages
    When set to $true, transitive packages are ignored. Defaults to $true.

    .PARAMETER Aggregate
    When set to $true, aggregates the output by grouping on ProjectName, Package, and ResolvedVersion,
    and optionally PackageType (based on IncludePackageType). Defaults to $true.

    .PARAMETER IncludePackageType
    When set to $true, the aggregated output includes PackageType. Defaults to $false.

    .PARAMETER GenerateTitle
    When set to $true, a professional title including project names is generated and prepended to the output.
    Defaults to $true.

    .PARAMETER SetMarkDownTitle
    Overrides the generated markdown title with a custom title. Only applied when OutputFormat is markdown.

    .PARAMETER ProjectWhitelist
    Array of ProjectNames to always include in the output.

    .PARAMETER ProjectBlacklist
    Array of ProjectNames to exclude from the output unless they are also in the whitelist.

    .EXAMPLE
    New-DotnetBillOfMaterialsReport -jsonInput $jsonData -OutputFormat markdown -IgnoreTransitivePackages $false

    .EXAMPLE
    New-DotnetBillOfMaterialsReport -jsonInput $jsonData -Aggregate $false -OutputFile "bom.txt"

    .EXAMPLE
    New-DotnetBillOfMaterialsReport -jsonInput $jsonData -ProjectWhitelist "ProjectA","ProjectB" -ProjectBlacklist "ProjectC"

    .EXAMPLE
    New-DotnetBillOfMaterialsReport -jsonInput $jsonData -SetMarkDownTitle "Custom BOM Title"
    #>

    try {
        $result = $jsonInput | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse JSON input from dotnet list command."
        exit 1
    }

    $bomEntries = @()

    # Build BOM entries from projects and their frameworks.
    foreach ($project in $result.projects) {
        if ($project.frameworks) {
            foreach ($framework in $project.frameworks) {
                # Process top-level packages.
                if ($framework.topLevelPackages) {
                    foreach ($package in $framework.topLevelPackages) {
                        $bomEntries += [PSCustomObject]@{
                            ProjectName     = [System.IO.Path]::GetFileNameWithoutExtension($project.path)
                            Framework       = $framework.framework
                            Package         = $package.id
                            ResolvedVersion = $package.resolvedVersion
                            PackageType     = "TopLevel"
                        }
                    }
                }

                # Process transitive packages only if not ignored.
                if (-not $IgnoreTransitivePackages -and $framework.transitivePackages) {
                    foreach ($package in $framework.transitivePackages) {
                        $bomEntries += [PSCustomObject]@{
                            ProjectName     = [System.IO.Path]::GetFileNameWithoutExtension($project.path)
                            Framework       = $framework.framework
                            Package         = $package.id
                            ResolvedVersion = $package.resolvedVersion
                            PackageType     = "Transitive"
                        }
                    }
                }
            }
        }
    }

    # Filter BOM entries by project whitelist and blacklist.
    if ($ProjectWhitelist -or $ProjectBlacklist) {
        $bomEntries = $bomEntries | Where-Object {
            if ($ProjectWhitelist -and ($ProjectWhitelist -contains $_.ProjectName)) {
                # Always include if in whitelist.
                $true
            }
            elseif ($ProjectBlacklist -and ($ProjectBlacklist -contains $_.ProjectName)) {
                # Exclude if in blacklist and not whitelisted.
                $false
            }
            else {
                $true
            }
        }
    }

    # If aggregation is enabled, group entries accordingly.
    if ($Aggregate) {
        if ($IncludePackageType) {
            $bomEntries = $bomEntries | Group-Object -Property ProjectName, Package, ResolvedVersion, PackageType | ForEach-Object {
                [PSCustomObject]@{
                    ProjectName     = $_.Group[0].ProjectName
                    Package         = $_.Group[0].Package
                    ResolvedVersion = $_.Group[0].ResolvedVersion
                    PackageType     = $_.Group[0].PackageType
                }
            }
        }
        else {
            $bomEntries = $bomEntries | Group-Object -Property ProjectName, Package, ResolvedVersion | ForEach-Object {
                [PSCustomObject]@{
                    ProjectName     = $_.Group[0].ProjectName
                    Package         = $_.Group[0].Package
                    ResolvedVersion = $_.Group[0].ResolvedVersion
                }
            }
        }
    }

    # Generate output based on the specified format.
    switch ($OutputFormat) {
        "text" {
            $output = $bomEntries | Format-Table -AutoSize | Out-String
        }
        "markdown" {
            if ($Aggregate) {
                if ($IncludePackageType) {
                    $mdTable = @()
                    $mdTable += "| ProjectName | Package | ResolvedVersion | PackageType |"
                    $mdTable += "|-------------|---------|-----------------|-------------|"
                    foreach ($item in $bomEntries) {
                        $mdTable += "| $($item.ProjectName) | $($item.Package) | $($item.ResolvedVersion) | $($item.PackageType) |"
                    }
                }
                else {
                    $mdTable = @()
                    $mdTable += "| ProjectName | Package | ResolvedVersion |"
                    $mdTable += "|-------------|---------|-----------------|"
                    foreach ($item in $bomEntries) {
                        $mdTable += "| $($item.ProjectName) | $($item.Package) | $($item.ResolvedVersion) |"
                    }
                }
                $output = $mdTable -join "`n"
            }
            else {
                $mdTable = @()
                $mdTable += "| ProjectName | Framework | Package | ResolvedVersion | PackageType |"
                $mdTable += "|-------------|-----------|---------|-----------------|-------------|"
                foreach ($item in $bomEntries) {
                    $mdTable += "| $($item.ProjectName) | $($item.Framework) | $($item.Package) | $($item.ResolvedVersion) | $($item.PackageType) |"
                }
                $output = $mdTable -join "`n"
            }
        }
    }

    # Generate and prepend a professional title if enabled.
    if ($GenerateTitle) {
        $distinctProjects = $bomEntries | Select-Object -ExpandProperty ProjectName -Unique | Sort-Object
        $projectsStr = $distinctProjects -join ", "
        $defaultTitle = "Bill of Materials Report for Projects: $projectsStr"

        if ($OutputFormat -eq "markdown") {
            if ([string]::IsNullOrEmpty($SetMarkDownTitle)) {
                $titleText = "## $defaultTitle`n`n"
            }
            else {
                $titleText = "## $SetMarkDownTitle`n`n"
            }
        }
        else {
            $underline = "-" * $defaultTitle.Length
            $titleText = "$defaultTitle`n$underline`n`n"
        }
        $output = $titleText + $output
    }

    # Write output to file if specified; otherwise, output to the pipeline.
    if ($OutputFile) {
        try {
            Set-Content -Path $OutputFile -Value $output -Force
            Write-Verbose "Output written to $OutputFile"
        }
        catch {
            Write-Error "Failed to write output to file: $_"
        }
    }
    else {
        Write-Output $output
    }
}


function New-DotnetVulnerabilitiesReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Array of JSON strings output from dotnet list command with the '--vulnerable' flag.")]
        [string[]]$jsonInput,

        [Parameter(Mandatory = $false, HelpMessage = "Optional file path to save the output.")]
        [string]$OutputFile,

        [Parameter(Mandatory = $false, HelpMessage = "Output format: 'text' or 'markdown'. Defaults to 'text'.")]
        [ValidateSet("text", "markdown")]
        [string]$OutputFormat = "text",

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, the function exits with error code 1 if any vulnerability is found. Defaults to false.")]
        [bool]$ExitOnVulnerability = $false,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, aggregates the output by grouping on Project, Package, and ResolvedVersion, and optionally PackageType. Defaults to true.")]
        [bool]$Aggregate = $true,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, transitive packages are ignored. Defaults to true.")]
        [bool]$IgnoreTransitivePackages = $true,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, the aggregated output includes PackageType. Defaults to false.")]
        [bool]$IncludePackageType = $false,

        [Parameter(Mandatory = $false, HelpMessage = "When set to true, a professional title is generated and prepended to the output. Defaults to true.")]
        [bool]$GenerateTitle = $true,

        [Parameter(Mandatory = $false, HelpMessage = "Overrides the generated markdown title with a custom title. Only applied when OutputFormat is markdown.")]
        [string]$SetMarkDownTitle,

        [Parameter(Mandatory = $false, HelpMessage = "Array of ProjectNames to always include in the output.")]
        [string[]]$ProjectWhitelist,

        [Parameter(Mandatory = $false, HelpMessage = "Array of ProjectNames to exclude from the output unless they are also in the whitelist.")]
        [string[]]$ProjectBlacklist
    )

    <#
    .SYNOPSIS
    Generates a professional vulnerabilities report from JSON input output by the dotnet list command with the '--vulnerable' flag.

    .DESCRIPTION
    Processes JSON input from the dotnet list command to gather vulnerability details for each project's frameworks and packages.
    Only the resolved version is reported. Top-level packages are always processed, while transitive packages are processed only when
    -IgnoreTransitivePackages is set to false. The report can be aggregated (grouping by Project, Package, ResolvedVersion, and optionally PackageType),
    and filtered by project whitelist/blacklist. The output is generated in text or markdown format, with a professional title prepended.
    Optionally, if ExitOnVulnerability is enabled and any vulnerability is found, the function exits with error code 1.

    .PARAMETER jsonInput
    Array of JSON strings output from the dotnet list command with the '--vulnerable' flag.

    .PARAMETER OutputFile
    Optional file path to save the output.

    .PARAMETER OutputFormat
    Specifies the output format: 'text' or 'markdown'. Defaults to 'text'.

    .PARAMETER ExitOnVulnerability
    When set to true, the function exits with error code 1 if any vulnerability is found. Defaults to false.

    .PARAMETER Aggregate
    When set to true, aggregates the output by grouping on Project, Package, and ResolvedVersion (and optionally PackageType). Defaults to true.

    .PARAMETER IgnoreTransitivePackages
    When set to true, transitive packages are ignored. Defaults to true.

    .PARAMETER IncludePackageType
    When set to true, the aggregated output includes PackageType. Defaults to false.

    .PARAMETER GenerateTitle
    When set to true, a professional title including project names is generated and prepended to the output. Defaults to true.

    .PARAMETER SetMarkDownTitle
    Overrides the generated markdown title with a custom title. Only applied when OutputFormat is markdown.

    .PARAMETER ProjectWhitelist
    Array of ProjectNames to always include in the output.

    .PARAMETER ProjectBlacklist
    Array of ProjectNames to exclude from the output unless they are also in the whitelist.

    .EXAMPLE
    New-DotnetVulnerabilitiesReport -jsonInput $jsonData -OutputFormat markdown -ExitOnVulnerability $true

    .EXAMPLE
    New-DotnetVulnerabilitiesReport -jsonInput $jsonData -OutputFile "vuln_report.txt"

    .EXAMPLE
    New-DotnetVulnerabilitiesReport -jsonInput $jsonData -SetMarkDownTitle "Custom Vulnerability Report"
    #>

    try {
        $result = $jsonInput | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse JSON input from dotnet list command."
        exit 1
    }

    $vulnerabilitiesFound = @()

    # Process each project and its frameworks.
    foreach ($project in $result.projects) {
        if ($project.frameworks) {
            foreach ($framework in $project.frameworks) {
                # Process top-level packages.
                if ($framework.topLevelPackages) {
                    foreach ($package in $framework.topLevelPackages) {
                        if ($package.vulnerabilities) {
                            foreach ($vuln in $package.vulnerabilities) {
                                $vulnerabilitiesFound += [PSCustomObject]@{
                                    Project         = [System.IO.Path]::GetFileNameWithoutExtension($project.path)
                                    Framework       = $framework.framework
                                    Package         = $package.id
                                    ResolvedVersion = $package.resolvedVersion
                                    Severity        = $vuln.severity
                                    AdvisoryUrl     = $vuln.advisoryurl
                                    PackageType     = "TopLevel"
                                }
                            }
                        }
                    }
                }
                # Process transitive packages if not ignored.
                if (-not $IgnoreTransitivePackages -and $framework.transitivePackages) {
                    foreach ($package in $framework.transitivePackages) {
                        if ($package.vulnerabilities) {
                            foreach ($vuln in $package.vulnerabilities) {
                                $vulnerabilitiesFound += [PSCustomObject]@{
                                    Project         = [System.IO.Path]::GetFileNameWithoutExtension($project.path)
                                    Framework       = $framework.framework
                                    Package         = $package.id
                                    ResolvedVersion = $package.resolvedVersion
                                    Severity        = $vuln.severity
                                    AdvisoryUrl     = $vuln.advisoryurl
                                    PackageType     = "Transitive"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Filter vulnerabilities by project whitelist and blacklist.
    if ($ProjectWhitelist -or $ProjectBlacklist) {
        $vulnerabilitiesFound = $vulnerabilitiesFound | Where-Object {
            if ($ProjectWhitelist -and ($ProjectWhitelist -contains $_.Project)) {
                $true
            }
            elseif ($ProjectBlacklist -and ($ProjectBlacklist -contains $_.Project)) {
                $false
            }
            else {
                $true
            }
        }
    }

    # Aggregate vulnerabilities if enabled.
    if ($Aggregate) {
        if ($IncludePackageType) {
            $vulnerabilitiesFound = $vulnerabilitiesFound | Group-Object -Property Project, Package, ResolvedVersion, PackageType | ForEach-Object {
                [PSCustomObject]@{
                    Project         = $_.Group[0].Project
                    Package         = $_.Group[0].Package
                    ResolvedVersion = $_.Group[0].ResolvedVersion
                    PackageType     = $_.Group[0].PackageType
                    Severity        = $_.Group[0].Severity
                    AdvisoryUrl     = $_.Group[0].AdvisoryUrl
                }
            }
        }
        else {
            $vulnerabilitiesFound = $vulnerabilitiesFound | Group-Object -Property Project, Package, ResolvedVersion | ForEach-Object {
                [PSCustomObject]@{
                    Project         = $_.Group[0].Project
                    Package         = $_.Group[0].Package
                    ResolvedVersion = $_.Group[0].ResolvedVersion
                    Severity        = $_.Group[0].Severity
                    AdvisoryUrl     = $_.Group[0].AdvisoryUrl
                }
            }
        }
    }

    # Generate report output based on the specified format.
    if ($OutputFormat -eq "text") {
        if ($vulnerabilitiesFound.Count -gt 0) {
            $output = $vulnerabilitiesFound | Format-Table -AutoSize | Out-String
        }
        else {
            $output = "No vulnerabilities found."
        }
    }
    elseif ($OutputFormat -eq "markdown") {
        if ($vulnerabilitiesFound.Count -gt 0) {
            if ($Aggregate) {
                if ($IncludePackageType) {
                    $mdTable = @()
                    $mdTable += "| Project | Package | ResolvedVersion | PackageType | Severity | AdvisoryUrl |"
                    $mdTable += "|---------|---------|-----------------|-------------|----------|-------------|"
                    foreach ($item in $vulnerabilitiesFound) {
                        $mdTable += "| $($item.Project) | $($item.Package) | $($item.ResolvedVersion) | $($item.PackageType) | $($item.Severity) | $($item.AdvisoryUrl) |"
                    }
                }
                else {
                    $mdTable = @()
                    $mdTable += "| Project | Package | ResolvedVersion | Severity | AdvisoryUrl |"
                    $mdTable += "|---------|---------|-----------------|----------|-------------|"
                    foreach ($item in $vulnerabilitiesFound) {
                        $mdTable += "| $($item.Project) | $($item.Package) | $($item.ResolvedVersion) | $($item.Severity) | $($item.AdvisoryUrl) |"
                    }
                }
            }
            else {
                $mdTable = @()
                $mdTable += "| Project | Framework | Package | ResolvedVersion | PackageType | Severity | AdvisoryUrl |"
                $mdTable += "|---------|-----------|---------|-----------------|-------------|----------|-------------|"
                foreach ($item in $vulnerabilitiesFound) {
                    $mdTable += "| $($item.Project) | $($item.Framework) | $($item.Package) | $($item.ResolvedVersion) | $($item.PackageType) | $($item.Severity) | $($item.AdvisoryUrl) |"
                }
            }
            $output = $mdTable -join "`n"
        }
        else {
            $output = "No vulnerabilities found."
        }
    }

    # Generate and prepend a professional title if enabled.
    if ($GenerateTitle) {
        if ($vulnerabilitiesFound.Count -eq 0) {
            # If no vulnerabilities, compute project list from the JSON input.
            $allProjects = $result.projects | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.path) } | Sort-Object -Unique
            if ($ProjectWhitelist -or $ProjectBlacklist) {
                $filteredProjects = $allProjects | Where-Object {
                    if ($ProjectWhitelist -and ($ProjectWhitelist -contains $_)) {
                        $true
                    }
                    elseif ($ProjectBlacklist -and ($ProjectBlacklist -contains $_)) {
                        $false
                    }
                    else {
                        $true
                    }
                }
            }
            else {
                $filteredProjects = $allProjects
            }
            $projectsForTitle = $filteredProjects
        }
        else {
            $projectsForTitle = $vulnerabilitiesFound | Select-Object -ExpandProperty Project -Unique | Sort-Object
        }
        if ($projectsForTitle.Count -eq 0) {
            $projectsStr = "None"
        }
        else {
            $projectsStr = $projectsForTitle -join ", "
        }
        $defaultTitle = "Vulnerabilities Report for Projects: $projectsStr"
        
        if ($OutputFormat -eq "markdown") {
            if ([string]::IsNullOrEmpty($SetMarkDownTitle)) {
                $titleText = "## $defaultTitle`n`n"
            }
            else {
                $titleText = "## $SetMarkDownTitle`n`n"
            }
        }
        else {
            $underline = "-" * $defaultTitle.Length
            $titleText = "$defaultTitle`n$underline`n`n"
        }
        $output = $titleText + $output
    }

    # Write output to file if specified; otherwise, output to the pipeline.
    if ($OutputFile) {
        try {
            Set-Content -Path $OutputFile -Value $output -Force
            Write-Verbose "Output written to $OutputFile"
        }
        catch {
            Write-Error "Failed to write output to file: $_"
        }
    }
    else {
        Write-Output $output
    }

    # Exit behavior: if vulnerabilities are found and ExitOnVulnerability is enabled, exit with error code 1.
    if ($vulnerabilitiesFound.Count -gt 0 -and $ExitOnVulnerability) {
        Write-Host "Vulnerabilities detected. Exiting with error code 1." -ForegroundColor Red
        exit 1
    }
    elseif ($vulnerabilitiesFound.Count -gt 0) {
        Write-Host "Vulnerabilities detected, but not exiting due to configuration." -ForegroundColor Yellow
    }
}

