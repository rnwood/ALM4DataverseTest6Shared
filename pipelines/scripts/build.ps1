<# 
.SYNOPSIS
    Builds the artifacts that can be used to deploy to a Dataverse environment.

.DESCRIPTION
    This script packs the solutions from the source directory into managed and unmanaged
    zip files in the artifact staging directory. It also copies any additional assets
    defined in alm-config.psd1 and creates a lock file for script dependencies.

    Hooks defined in alm-config.psd1 are invoked at various stages of the build process
    to allow for custom pre- and post-build actions.
.PARAMETER SourceDirectory
    The root directory containing the solution folders and alm-config.psd1 file.
.PARAMETER ArtifactStagingDirectory
    The directory where the built artifacts will be placed.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceDirectory,
    
    [Parameter(Mandatory=$true)]
    [string]$ArtifactStagingDirectory
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host "##[section]Building Artifacts"

# Read solutions configuration
$config = Get-AlmConfig -BaseDirectory $SourceDirectory
Write-Host "##[debug]Loaded configuration from alm-config.psd1"

Invoke-Hooks -HookType "preBuild" -BaseDirectory $SourceDirectory -Config $config -AdditionalContext @{
    SourceDirectory = $SourceDirectory
    ArtifactStagingDirectory = $ArtifactStagingDirectory
}

foreach ($solution in $config.solutions) {
    $solutionName = $solution.name
    
    Write-Host "##[group]Building solution: $solutionName"
    
    Write-Host "Packing solution: $solutionName (Managed)"

    Compress-DataverseSolutionFile -Verbose `
        -Path "$SourceDirectory/solutions/$solutionName" `
        -OutputPath "$ArtifactStagingDirectory/solutions/${solutionName}.zip" `
        -PackageType Both
    
    Write-Host "##[endgroup]"
}

if ($config.assets -and $config.assets.Count -gt 0) {
    Write-Host "##[group]Copying extra asset files"
    foreach ($asset in $config.assets) {
        $sourcePath = Join-Path $SourceDirectory $asset
        $destinationPath = Join-Path $ArtifactStagingDirectory $asset
        
        if (Test-Path $sourcePath) {
            Write-Host "Copying asset: $asset"
            Copy-Item $sourcePath -Destination $destinationPath -Recurse -Force -Verbose
        } else {
            write-Host "##[error]Asset path not found: $sourcePath"
            throw "Asset path not found: $sourcePath"
        }
    }
    Write-Host "##[endgroup]"
}

Write-Host "##[group]Copying deployment scripts"
Copy-Item $PSScriptRoot/../.. -Destination "$ArtifactStagingDirectory/alm" -Recurse -Force -Verbose
Copy-Item (Join-Path $SourceDirectory 'alm-config.psd1') -Destination (Join-Path $ArtifactStagingDirectory 'alm-config.psd1') -Force -Verbose

# Create lock file with pinned module versions
$lockConfig = @{
    scriptDependencies = [hashtable]::new($config.scriptDependencies)
}
foreach ($moduleName in ([string[]] $lockConfig.scriptDependencies.Keys)) {
    $module = Get-Module -Name $moduleName
    if ($module) {
        $version = $module.Version.ToString()
        if ($module.PrivateData -and $module.PrivateData.PSData -and $module.PrivateData.PSData.Prerelease) {
            $version += "-$($module.PrivateData.PSData.Prerelease)"
        }
        $lockConfig.scriptDependencies[$moduleName] = $version
    } else {
        write-Host "##[error]Module $moduleName not found in loaded modules."
        throw "Module $moduleName not found in loaded modules."
    }
}
$lockPath = Join-Path $ArtifactStagingDirectory 'scriptDependencies.lock.json'
$lockConfig | ConvertTo-Json | Out-File $lockPath -Encoding UTF8

Write-Host "##[endgroup]"

# Save PS modules for self-contained/offline deployment (Package Deployer scenario)
Write-Host "##[group]Saving PowerShell modules for offline deployment"
$modulesDir = Join-Path $ArtifactStagingDirectory 'modules'
foreach ($moduleName in $lockConfig.scriptDependencies.Keys) {
    $version = $lockConfig.scriptDependencies[$moduleName]
    Write-Host "Saving $moduleName $version to $modulesDir"
    Save-Module -Name $moduleName -RequiredVersion $version -Path $modulesDir -Force -AllowPrerelease:($version.Contains("-"))
}
Write-Host "##[endgroup]"

Write-Host "##[section]Build completed successfully!"

Invoke-Hooks -HookType "postBuild" -BaseDirectory $SourceDirectory -Config $config -AdditionalContext @{
    SourceDirectory = $SourceDirectory
    ArtifactStagingDirectory = $ArtifactStagingDirectory
}

# Build Package Deployer package if the project exists
$pdProjectPath = Join-Path $PSScriptRoot ".." ".." "ALM4Dataverse.PackageDeployer" "ALM4Dataverse.PackageDeployer.csproj"
if (Test-Path $pdProjectPath) {
    Write-Host "##[section]Building Package Deployer package"
    $pdProjectPath = Resolve-Path $pdProjectPath | Select-Object -ExpandProperty Path
    $pdPublishDir = Join-Path $ArtifactStagingDirectory "packagedeployer"

    dotnet publish $pdProjectPath `
        -c Release `
        -o $pdPublishDir `
        "-p:BuildArtifactsPath=$ArtifactStagingDirectory"

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish for Package Deployer failed with exit code $LASTEXITCODE"
    }

    $pdpkgZip = Join-Path $ArtifactStagingDirectory "ALM4Dataverse.PackageDeployer.pdpkg.zip"
    Compress-Archive -Path "$pdPublishDir/*" -DestinationPath $pdpkgZip -Force
    Write-Host "Package Deployer package created: $pdpkgZip"
}
