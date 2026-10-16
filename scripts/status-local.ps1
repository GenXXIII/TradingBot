[CmdletBinding()]
param()

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = Join-Path $projectRoot '.runtime'

function Get-TrackedStatus {
    param([string]$PidFile, [string[]]$AllowedNames)

    if (-not (Test-Path -LiteralPath $PidFile)) {
        return 'stopped'
    }
    $savedPid = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $PidFile -Raw).Trim(), [ref]$savedPid)) {
        return 'invalid pid file'
    }
    $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    if ($null -eq $process -or $AllowedNames -notcontains $process.ProcessName) {
        return 'stopped (stale pid file)'
    }
    return "running (PID $savedPid)"
}

$apiHealth = 'unavailable'
$webHealth = 'unavailable'
try { $apiHealth = (Invoke-RestMethod -Uri 'http://127.0.0.1:5182/health' -TimeoutSec 2).status } catch {}
try { $webHealth = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:3000' -TimeoutSec 2).StatusCode } catch {}

[pscustomobject]@{
    Service = 'API'
    Process = Get-TrackedStatus -PidFile (Join-Path $runtimeRoot 'api.pid') -AllowedNames @('dotnet', 'AutoScalping.Api')
    Health = $apiHealth
    Url = 'http://127.0.0.1:5182'
}
[pscustomobject]@{
    Service = 'Dashboard'
    Process = Get-TrackedStatus -PidFile (Join-Path $runtimeRoot 'web.pid') -AllowedNames @('node')
    Health = $webHealth
    Url = 'http://127.0.0.1:3000'
}
