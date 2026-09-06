param(
    [string]$BaseDir = $PSScriptRoot
)

$ErrorActionPreference = 'SilentlyContinue'
$batch = Join-Path $BaseDir 'start-hotspot-redirect.bat'
$stopFlag = Join-Path $BaseDir 'watchdog.stop'
$log = Join-Path $BaseDir 'logs\watchdog.log'
$lockPath = Join-Path $BaseDir 'watchdog.lock'
$lockStream = $null

# A file handle is more reliable than a named mutex across scheduled-task
# sessions. CreateNew is atomic, so only one watchdog can continue.
try {
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $lockStream.WriteByte(0)
    $lockStream.Flush()
} catch {
    # A forced termination can leave the marker behind. If the file is not
    # currently locked, remove the stale marker and acquire it once more.
    try {
        $staleStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $staleStream.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $lockStream.WriteByte(0)
        $lockStream.Flush()
    } catch {
        exit 0
    }
}

function Write-WatchdogLog {
    param([string]$Message)
    Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Get-HotspotState {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
        $profile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
        if (-not $profile) { return 'NoConnection' }
        $manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($profile)
        return [string]$manager.TetheringOperationalState
    } catch { return 'Unknown' }
}

function Get-ProxyProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -like '*hotspot-redirect.js*'
    })
}

function Get-LauncherProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -like '*start-hotspot-redirect.bat*--silent*'
    })
}

function Test-ProxyHealthy {
    $processes = Get-ProxyProcesses
    if ($processes.Count -ne 1) { return $false }

    $proxyPid = [int]$processes[0].ProcessId
    $httpsEndpoint = @(Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $proxyPid })
    return ($httpsEndpoint.Count -gt 0)
}

function Stop-ProxyProcesses {
    $processes = Get-ProxyProcesses
    foreach ($process in $processes) {
        Write-WatchdogLog "Stopping proxy PID $($process.ProcessId)."
        Stop-Process -Id $process.ProcessId -Force
    }
    if ($processes.Count -gt 0) { Start-Sleep -Seconds 3 }
}

function Start-Proxy {
    $existing = @(Get-ProxyProcesses)
    if (-not (Test-Path -LiteralPath $stopFlag) -and $existing.Count -eq 0) {
        Write-WatchdogLog 'Starting hotspot and redirect service.'
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/d', '/c', "`"$batch`" --silent" -WorkingDirectory $BaseDir -WindowStyle Hidden
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null
Write-WatchdogLog 'Watchdog started.'

$lastStart = [datetime]::MinValue
$startCooldown = [timespan]::FromSeconds(60)

try {
    while (-not (Test-Path -LiteralPath $stopFlag)) {
        $processes = Get-ProxyProcesses
        $launchers = Get-LauncherProcesses
        $state = Get-HotspotState
        $healthy = Test-ProxyHealthy

        if ($state -eq 'Off' -or $state -eq 'NoConnection') {
            if ($processes.Count -gt 0 -or $launchers.Count -gt 0) {
                Write-WatchdogLog "Hotspot state is $state; restarting proxy."
                Stop-ProxyProcesses
            }
            if ($launchers.Count -eq 0 -and ((Get-Date) - $lastStart) -ge $startCooldown) {
                $lastStart = Get-Date
                Start-Proxy
            }
            Start-Sleep -Seconds 5
        } elseif (-not $healthy -and $launchers.Count -eq 0 -and ((Get-Date) - $lastStart) -ge $startCooldown) {
            Write-WatchdogLog "Proxy health check failed (process or port 443 missing); restarting."
            Stop-ProxyProcesses
            $lastStart = Get-Date
            Start-Proxy
            Start-Sleep -Seconds 5
        }

        Start-Sleep -Seconds 15
    }
} finally {
    Write-WatchdogLog 'Watchdog stopped.'
    if ($lockStream) {
        $lockStream.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}
