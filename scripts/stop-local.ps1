[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = Join-Path $projectRoot '.runtime'

function Stop-TrackedProcess {
    param(
        [string]$PidFile,
        [string[]]$AllowedNames,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $PidFile)) {
        if (-not $Quiet) { Write-Output "$Label is not tracked as running." }
        return
    }

    $savedPid = 0
    $rawPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if ([int]::TryParse($rawPid, [ref]$savedPid)) {
        $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            if ($AllowedNames -notcontains $process.ProcessName) {
                throw "Refusing to stop PID $savedPid because it is '$($process.ProcessName)', not the expected $Label process."
            }
            Stop-Process -Id $savedPid -Force
            if (-not $Quiet) { Write-Output "Stopped $Label (PID $savedPid)." }
        }
    }

    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

Stop-TrackedProcess -PidFile (Join-Path $runtimeRoot 'web.pid') -AllowedNames @('node') -Label 'dashboard'
Stop-TrackedProcess -PidFile (Join-Path $runtimeRoot 'api.pid') -AllowedNames @('dotnet', 'AutoScalping.Api') -Label 'API'

