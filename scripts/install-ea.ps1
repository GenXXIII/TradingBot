[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Mt5DataFolder
)

$ErrorActionPreference = 'Stop'
$resolvedDataFolder = (Resolve-Path -LiteralPath $Mt5DataFolder).Path
$expertsFolder = Join-Path $resolvedDataFolder 'MQL5\Experts\AutoScalpingTrading'
$sourceFolder = Join-Path $PSScriptRoot '..\mt5\Experts'
$sourceFolder = (Resolve-Path -LiteralPath $sourceFolder).Path
$presetsFolder = Join-Path $resolvedDataFolder 'MQL5\Profiles\Presets\AutoScalpingTrading'
$presetSourceFolder = Join-Path $PSScriptRoot '..\mt5\Profiles\Presets'
$presetSourceFolder = (Resolve-Path -LiteralPath $presetSourceFolder).Path

if (-not (Test-Path -LiteralPath (Join-Path $resolvedDataFolder 'MQL5'))) {
    throw "The selected folder is not an MT5 data folder: $resolvedDataFolder"
}

if ($PSCmdlet.ShouldProcess($expertsFolder, 'Install AutoScalpingTrading EAs and Hybrid presets')) {
    New-Item -ItemType Directory -Path $expertsFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $presetsFolder -Force | Out-Null
    foreach ($name in 'AutoScalperExness.mq5', 'AutoScalperExness.ex5', 'AutoScalperHybrid.mq5', 'AutoScalperHybrid.ex5') {
        $source = Join-Path $sourceFolder $name
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing compiled/source EA artifact: $source"
        }
        Copy-Item -LiteralPath $source -Destination $expertsFolder -Force
    }
    foreach ($preset in Get-ChildItem -LiteralPath $presetSourceFolder -Filter '*.set' -File) {
        Copy-Item -LiteralPath $preset.FullName -Destination $presetsFolder -Force
    }
    Write-Output "Installed EAs to $expertsFolder"
    Write-Output "Installed Hybrid presets to $presetsFolder"
    Write-Output 'Restart MT5 or refresh Navigator > Expert Advisors.'
}

