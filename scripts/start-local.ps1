[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$SkipMt5Launch
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = Join-Path $projectRoot '.runtime'
$apiOutput = Join-Path $runtimeRoot 'api'
$logFolder = Join-Path $runtimeRoot 'logs'
$apiPidFile = Join-Path $runtimeRoot 'api.pid'
$webPidFile = Join-Path $runtimeRoot 'web.pid'

function Test-TrackedProcess {
    param([string]$PidFile, [string[]]$AllowedNames)

    if (-not (Test-Path -LiteralPath $PidFile)) {
        return $false
    }

    $savedPid = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $PidFile -Raw).Trim(), [ref]$savedPid)) {
        return $false
    }

    $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    return $null -ne $process -and $AllowedNames -contains $process.ProcessName
}

function Resolve-Mt5TerminalPath {
    $candidates = @()
    if ($env:MT5_TERMINAL_PATH) {
        $candidates += $env:MT5_TERMINAL_PATH
    }
    $candidates += @(
        (Join-Path $env:ProgramFiles 'MetaTrader 5\terminal64.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'MetaTrader 5\terminal64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\MetaTrader 5\terminal64.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Start-Mt5IfNeeded {
    if ($SkipMt5Launch) {
        Write-Output 'MT5 automatic launch skipped.'
        return
    }

    $runningTerminal = Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($runningTerminal) {
        Write-Output "MT5 is already running (PID $($runningTerminal.Id))."
        return
    }

    $terminalPath = Resolve-Mt5TerminalPath
    if (-not $terminalPath) {
        Write-Warning 'MT5 terminal64.exe was not found. Set MT5_TERMINAL_PATH in .env for a custom installation.'
        return
    }

    $terminalProcess = Start-Process -FilePath $terminalPath -PassThru
    Write-Output "MT5 started (PID $($terminalProcess.Id)): $terminalPath"
}

function Import-LocalEnvironment {
    $environmentFile = Join-Path $projectRoot '.env'
    if (Test-Path -LiteralPath $environmentFile) {
        foreach ($line in Get-Content -LiteralPath $environmentFile) {
            $trimmed = $line.Trim()
            if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
                continue
            }

            $separator = $trimmed.IndexOf('=')
            if ($separator -le 0) {
                continue
            }

            $name = $trimmed.Substring(0, $separator).Trim()
            $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }

    if ($env:MT5_BRIDGE_KEY) {
        $env:Mt5__BridgeKey = $env:MT5_BRIDGE_KEY
    }
    if ($env:ALLOW_REAL_CONTROL) {
        $env:Mt5__AllowRealControl = $env:ALLOW_REAL_CONTROL
    }

    $env:ASPNETCORE_ENVIRONMENT = 'Production'
    $env:State__Path = Join-Path $projectRoot 'data\control-state.json'
    $env:NEXT_PUBLIC_API_URL = if ($env:NEXT_PUBLIC_API_URL) { $env:NEXT_PUBLIC_API_URL } else { 'http://127.0.0.1:5182' }
}

Import-LocalEnvironment

if ((Test-TrackedProcess -PidFile $apiPidFile -AllowedNames @('dotnet', 'AutoScalping.Api')) -and
    (Test-TrackedProcess -PidFile $webPidFile -AllowedNames @('node'))) {
    Write-Output 'AutoScalper services are already running.'
    Start-Mt5IfNeeded
    & (Join-Path $PSScriptRoot 'status-local.ps1')
    exit 0
}

New-Item -ItemType Directory -Path $runtimeRoot, $apiOutput, $logFolder -Force | Out-Null

Push-Location $projectRoot
try {
    if (-not $SkipBuild) {
        dotnet publish '.\src\AutoScalping.Api\AutoScalping.Api.csproj' -c Release -o $apiOutput --nologo
        if ($LASTEXITCODE -ne 0) {
            throw 'API publish failed.'
        }

        Push-Location (Join-Path $projectRoot 'web')
        try {
            if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'web\node_modules'))) {
                npm.cmd install
                if ($LASTEXITCODE -ne 0) {
                    throw 'Web dependency installation failed.'
                }
            }
            npm.cmd run build
            if ($LASTEXITCODE -ne 0) {
                throw 'Dashboard production build failed.'
            }
        }
        finally {
            Pop-Location
        }
    }

    $apiDll = Join-Path $apiOutput 'AutoScalping.Api.dll'
    $nextCli = Join-Path $projectRoot 'web\node_modules\next\dist\bin\next'
    if (-not (Test-Path -LiteralPath $apiDll)) {
        throw "Published API was not found at $apiDll. Run without -SkipBuild."
    }
    if (-not (Test-Path -LiteralPath $nextCli)) {
        throw "Next.js runtime was not found at $nextCli. Run without -SkipBuild."
    }

    $apiProcess = Start-Process -FilePath 'dotnet' `
        -ArgumentList @($apiDll, '--urls', 'http://127.0.0.1:5182') `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logFolder 'api.out.log') `
        -RedirectStandardError (Join-Path $logFolder 'api.err.log') `
        -PassThru

    $webProcess = Start-Process -FilePath 'node' `
        -ArgumentList @($nextCli, 'start', '--hostname', '127.0.0.1', '--port', '3000') `
        -WorkingDirectory (Join-Path $projectRoot 'web') `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logFolder 'web.out.log') `
        -RedirectStandardError (Join-Path $logFolder 'web.err.log') `
        -PassThru

    [IO.File]::WriteAllText($apiPidFile, $apiProcess.Id.ToString())
    [IO.File]::WriteAllText($webPidFile, $webProcess.Id.ToString())

    $apiReady = $false
    $webReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            $apiReady = (Invoke-RestMethod -Uri 'http://127.0.0.1:5182/health' -TimeoutSec 2).status -eq 'healthy'
        }
        catch {
            $apiReady = $false
        }
        try {
            $webReady = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:3000' -TimeoutSec 2).StatusCode -eq 200
        }
        catch {
            $webReady = $false
        }
        if ($apiReady -and $webReady) {
            break
        }
    }

    if (-not $apiReady -or -not $webReady) {
        throw "Native services failed health checks. Inspect $logFolder."
    }

    Write-Output "AutoScalper API started (PID $($apiProcess.Id)): http://127.0.0.1:5182"
    Write-Output "AutoScalper dashboard started (PID $($webProcess.Id)): http://127.0.0.1:3000"
    Start-Mt5IfNeeded
    Write-Output 'Trading remains paused until fresh allowed MT5 telemetry is connected and a matching profile button is pressed.'
}
catch {
    & (Join-Path $PSScriptRoot 'stop-local.ps1') -Quiet
    throw
}
finally {
    Pop-Location
}

