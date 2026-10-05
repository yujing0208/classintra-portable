#requires -Version 5.1
<#
  watchdog.ps1 - ClassIntra service watchdog (process guard + hotspot monitor)

  GUARDED COMPONENTS
    1. ClassIntra   : node.exe running "src\app.js"          (server\)
    2. Hotspot      : the 192.168.137.1 hotspot interface - re-opened through
                      hotspot-ctl.ps1 when it disappears

  The captive portal itself is kept alive by the launcher script
  (the one-click launcher in the package root), which runs it in a foreground
  restart loop, so the window keeps showing the captive log.

  BEHAVIOUR
    - polls every $Interval seconds (default 20)
    - a component is only restarted if at least $RestartCooldown seconds have
      passed since the last restart attempt (avoid restart storms)
    - waits $StartupGrace seconds before the first check, so the launcher has
      time to bring everything up on a cold start
    - exits when it finds "captive\watchdog.stop", or when the window that
      launched it is closed
    - single instance only: guarded by an exclusive lock on captive\watchdog.lock

  LOG
    logs\watchdog.log
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [int]$Interval = 20,
    [int]$StartupGrace = 45,
    [int]$RestartCooldown = 60,
    [int]$ClassIntraPort = 9001,
    [switch]$NoHotspot,
    [int]$WatchPid = 0,
    [int]$MaxRuns = 0,
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- paths
if (-not $Root) {
    $here = $PSScriptRoot                       # ...\<package>\captive
    $Root = Split-Path -Parent $here            # ...\<package>
    if (-not (Test-Path (Join-Path $Root 'runtime'))) { $Root = $here }
}

$CapDir    = Join-Path $Root 'captive'
$SrvDir    = Join-Path $Root 'server'
$LogDir    = Join-Path $Root 'logs'
$WLog      = Join-Path $LogDir 'watchdog.log'
$CiLog     = Join-Path $LogDir 'classintra.log'
$HsLog     = Join-Path $LogDir 'hotspot.log'
$StopFlag  = Join-Path $CapDir 'watchdog.stop'
$LockPath  = Join-Path $CapDir 'watchdog.lock'
$Hctl      = Join-Path $CapDir 'hotspot-ctl.ps1'
$NodeGui   = Join-Path $Root 'runtime\node_gui\node.exe'
$HotspotIP = '192.168.137.1'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-WdLog {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $WLog -Value $line -Encoding UTF8 } catch { }
}

# ------------------------------------------------- single instance lock
# A lock file held open with FileShare.None acts as the single-instance guard.
# The handle is released automatically when the process dies, so the file is
# opened with OpenOrCreate and NEVER deleted - no file-deletion side effect.
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $lockStream.SetLength(0)
    $lockStream.WriteByte(0)
    $lockStream.Flush()
} catch {
    Write-WdLog 'another watchdog instance is already running - exiting'
    exit 0
}

# --------------------------------------- who launched us (window watch)
if ($WatchPid -le 0) {
    try {
        $me = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $PID) -ErrorAction Stop
        if ($me -and $me.ParentProcessId) {
            $par = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $me.ParentProcessId) -ErrorAction SilentlyContinue
            if ($par -and $par.Name -ieq 'cmd.exe') { $WatchPid = [int]$par.ProcessId }
        }
    } catch { }
}

# ------------------------------------------------------------ helpers
function Get-NodeProcs {
    param([string]$Match)
    @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and ($_.CommandLine -like ('*' + $Match + '*')) })
}

function Test-HotspotIp {
    return [bool](Get-NetIPAddress -IPAddress $HotspotIP -ErrorAction SilentlyContinue)
}

# Fallback liveness probe: a node process that is LISTENING on the given port
# is considered alive even when its command line cannot be read (a non-elevated
# caller cannot see other processes' command lines).
function Test-PortListening {
    param([int]$Port, [string]$ProcName)
    foreach ($x in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) {
        $p = Get-Process -Id $x.OwningProcess -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -ieq $ProcName) { return $true }
    }
    return $false
}

function Start-ClassIntra {
    if ($DryRun) { Write-WdLog '[dry-run] would start ClassIntra'; return }
    $env:NODE_PATH = Join-Path $SrvDir 'node_modules'
    $cmd = '"' + $NodeGui + '" --max-old-space-size=768 src\app.js >> "' + $CiLog + '" 2>&1'
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -WorkingDirectory $SrvDir -WindowStyle Hidden
}

function Start-Hotspot {
    if ($DryRun) { Write-WdLog '[dry-run] would re-open the hotspot'; return }
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $Hctl + '" -Action on -WaitPort 53 -WaitTimeout 120 >> "' + $HsLog + '" 2>&1'
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -WorkingDirectory $CapDir -WindowStyle Hidden
}

# ---------------------------------------------------------------- main
Write-WdLog ('watchdog started (root=' + $Root + ', interval=' + $Interval + 's, watchPid=' + $WatchPid + ')')
Write-WdLog ('startup grace ' + $StartupGrace + 's ...')
Start-Sleep -Seconds $StartupGrace

$lastCi = [datetime]::MinValue
$lastHs = [datetime]::MinValue
$cd = [timespan]::FromSeconds($RestartCooldown)
$runs = 0

try {
    while (-not (Test-Path -LiteralPath $StopFlag)) {
        $runs++

        if ($WatchPid -gt 0 -and -not (Get-Process -Id $WatchPid -ErrorAction SilentlyContinue)) {
            Write-WdLog 'launcher window closed - watchdog exiting'
            break
        }

        # ---- 1) ClassIntra  (node running src\app.js, or listening on its port)
        $ciAlive = ((Get-NodeProcs 'src\app.js').Count -gt 0) -or (Test-PortListening -Port $ClassIntraPort -ProcName 'node')
        if (-not $ciAlive) {
            if (((Get-Date) - $lastCi) -ge $cd) {
                Write-WdLog ('ClassIntra is NOT running (no src\app.js process, port ' + $ClassIntraPort + ' closed) - restarting it')
                Start-ClassIntra
                $lastCi = Get-Date
            }
        }

        # ---- 2) hotspot
        if (-not $NoHotspot) {
            if (-not (Test-HotspotIp)) {
                if (((Get-Date) - $lastHs) -ge $cd) {
                    Write-WdLog ('hotspot interface ' + $HotspotIP + ' is DOWN - re-opening it')
                    Start-Hotspot
                    $lastHs = Get-Date
                }
            }
        }

        Start-Sleep -Seconds $Interval
        if ($MaxRuns -gt 0 -and $runs -ge $MaxRuns) {
            Write-WdLog ('max runs reached (' + $MaxRuns + ') - exiting')
            break
        }
    }
} finally {
    Write-WdLog 'watchdog stopped'
    if ($lockStream) {
        try { $lockStream.Dispose() } catch { }
        $lockStream = $null
    }
}
