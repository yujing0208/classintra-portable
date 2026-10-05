#requires -Version 5.1
<#
  hotspot-ctl.ps1 - hotspot controller for the ClassIntra captive portal.

  WHY THE HOTSPOT STARTS *AFTER* THE CAPTIVE PORTAL
  -------------------------------------------------
  Windows "Mobile Hotspot" is powered by Internet Connection Sharing (ICS).
  While the hotspot is on, the ICS DNS proxy binds 0.0.0.0:53 - the very port
  the captive DNS hijack needs.  The two collide:
      * hotspot first -> ICS owns 53 -> captive cannot bind -> hijack dead
      * stop ICS to free 53 -> Windows switches the hotspot off immediately
  Verified workaround: let captive bind 53 FIRST, then start the hotspot.
  ICS fails to grab 53 but the hotspot itself comes up normally.

  STRATEGY
  --------
    1. netsh hostednetwork  : no ICS involved, up to 100 clients,
                              works from a SYSTEM scheduled task   <- preferred
    2. Windows Mobile Hotspot (WinRT) : fallback, but needs an
                              interactive user session. Up to 8 clients only.

  ACTIONS
  -------
    -Action off     : turn every hotspot method off, wait for ICS to release 53
    -Action on      : optionally wait for a port to be held, then start hotspot
    -Action status  : report hotspot state and who owns UDP 53
#>
[CmdletBinding()]
param(
    [ValidateSet('on', 'off', 'status')] [string]$Action = 'status',
    [int]$WaitPort = 0,
    [int]$WaitTimeout = 120,
    [int]$ReadyTimeout = 60,
    [string]$Ssid = $env:COMPUTERNAME,
    [string]$Key = 'classintr',
    [int]$MaxClient = 0
)

$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root 'runtime'))) { $Root = $PSScriptRoot }
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir 'hotspot.log'
$HotspotIP = '192.168.137.1'

function Write-Log {
    param([string]$Msg, [string]$Color = 'Gray')
    $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $Msg
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $line -ForegroundColor $Color
}

# ---------------------------------------------------------------- WinRT glue
$script:WinRTReady = $false
$script:AsTaskGen = $null
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    $script:AsTaskGen = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
    if ($script:AsTaskGen) { $script:WinRTReady = $true }
} catch { $script:WinRTReady = $false }

function Invoke-Await {
    param($Op, $ResultType)
    $task = $script:AsTaskGen.MakeGenericMethod($ResultType).Invoke($null, @($Op))
    $task.Wait(-1) | Out-Null
    if ($task.IsFaulted) { throw $task.Exception }
    return $task.Result
}

function Get-InternetProfile {
    return [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
}

function Get-TetheringManager {
    $profile = Get-InternetProfile
    if (-not $profile) { throw 'no internet connection profile' }
    return [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
}

function Get-TetheringResultType {
    return [Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
}

# ------------------------------------------------------------ port / ip probes
function Get-PortOwnerNames {
    param([int]$Port)
    $names = @()
    try {
        foreach ($e in @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)) {
            $p = Get-Process -Id $e.OwningProcess -ErrorAction SilentlyContinue
            if ($p) { $names += $p.ProcessName }
        }
    } catch { }
    return @($names | Select-Object -Unique)
}

function Wait-PortOwner {
    param([int]$Port, [string]$Owner, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-PortOwnerNames -Port $Port) -contains $Owner) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Test-HotspotIp {
    return [bool](Get-NetIPAddress -IPAddress $HotspotIP -ErrorAction SilentlyContinue)
}

function Wait-HotspotIp {
    param([int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-HotspotIp) { return $true }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

# ------------------------------------------------------------------- hotspot
function Stop-Hotspot {
    Write-Log 'releasing hotspot (netsh stop + mobile hotspot off)...'

    try { netsh wlan stop hostednetwork 2>&1 | Out-Null } catch { }

    if ($script:WinRTReady) {
        try {
            $tm = Get-TetheringManager
            if ($tm.TetheringOperationalState -ne 'Off') {
                $res = Invoke-Await ($tm.StopTetheringAsync()) (Get-TetheringResultType)
                Write-Log ('mobile hotspot stop -> ' + $res.Status)
            } else {
                Write-Log 'mobile hotspot already off'
            }
        } catch { Write-Log ('mobile hotspot stop error: ' + $_.Exception.Message) 'Yellow' }
    }

    # wait for ICS to let go of UDP 53
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if (-not ((Get-PortOwnerNames -Port 53) -contains 'svchost')) { break }
        Start-Sleep -Milliseconds 500
    }

    if (Test-HotspotIp) { Write-Log 'hotspot interface still present' 'Yellow' }
    else { Write-Log 'hotspot is off' 'Green' }
}

function Start-NetshHotspot {
    Write-Log ('netsh: set hostednetwork ssid="' + $Ssid + '" key="' + $Key + '"')

    $ok = $false
    if ($MaxClient -gt 0) {
        netsh wlan set hostednetwork mode=allow ssid="$Ssid" key="$Key" maxclient=$MaxClient 2>&1 | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        if (-not $ok) { Write-Log 'netsh: maxclient not supported by this Windows build, retrying without it' 'Yellow' }
    }
    if (-not $ok) {
        netsh wlan set hostednetwork mode=allow ssid="$Ssid" key="$Key" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log 'netsh: set hostednetwork failed' 'Yellow'; return $false }
    }

    netsh wlan start hostednetwork 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log 'netsh: start hostednetwork failed (driver may not support it)' 'Yellow'; return $false }

    if (Wait-HotspotIp -TimeoutSec 20) {
        Write-Log ('hotspot online (' + $HotspotIP + ') via netsh hostednetwork') 'Green'
        return $true
    }
    Write-Log 'netsh: interface never came up' 'Yellow'
    return $false
}

function Start-MobileHotspot {
    if (-not $script:WinRTReady) { Write-Log 'mobile hotspot: WinRT unavailable' 'Yellow'; return $false }
    try {
        Write-Log 'mobile hotspot: acquiring tethering manager...'
        $profile = Get-InternetProfile
        if (-not $profile) {
            Write-Log 'mobile hotspot: no internet connection profile - Windows refuses to share nothing' 'Yellow'
            return $false
        }
        $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
        Write-Log ('mobile hotspot state: ' + $tm.TetheringOperationalState)
        if ($tm.TetheringOperationalState -eq 'On') {
            if (Wait-HotspotIp -TimeoutSec 10) { Write-Log 'mobile hotspot already on' 'Green'; return $true }
        }

        $res = Invoke-Await ($tm.StartTetheringAsync()) (Get-TetheringResultType)
        Write-Log ('mobile hotspot start -> ' + $res.Status + ' ' + $res.AdditionalErrorMessage)

        if (Wait-HotspotIp -TimeoutSec $ReadyTimeout) {
            Write-Log ('hotspot online (' + $HotspotIP + ') via Windows Mobile Hotspot') 'Green'
            return $true
        }
        Write-Log 'mobile hotspot: interface did not come up in time' 'Yellow'
        return $false
    } catch {
        Write-Log ('mobile hotspot error: ' + $_.Exception.Message) 'Yellow'
        return $false
    }
}

# ---------------------------------------------------------------------- main
Write-Log ('--- hotspot-ctl action=' + $Action + ' ---')

switch ($Action) {

    'status' {
        if (Test-HotspotIp) { Write-Log ('hotspot ON  (' + $HotspotIP + ')') 'Green' }
        else { Write-Log 'hotspot OFF' 'Yellow' }
        $owners = Get-PortOwnerNames -Port 53
        if ($owners.Count -gt 0) { Write-Log ('udp/53 owned by: ' + ($owners -join ', ')) }
        else { Write-Log 'udp/53 is free' }
        exit 0
    }

    'off' {
        Stop-Hotspot
        exit 0
    }

    'on' {
        $portOwnedByUs = $false
        if ($WaitPort -gt 0) { $portOwnedByUs = ((Get-PortOwnerNames -Port $WaitPort) -contains 'node') }

        if (Test-HotspotIp) {
            if ($WaitPort -le 0 -or $portOwnedByUs) {
                Write-Log ('hotspot already online (' + $HotspotIP + ')') 'Green'
                exit 0
            }
            # hotspot came up early and its ICS DNS proxy is sitting on our port:
            # take it down again so the captive portal can bind first
            Write-Log ('hotspot is up but UDP ' + $WaitPort + ' is held by ' + ((Get-PortOwnerNames -Port $WaitPort) -join ',') + ' - restarting hotspot after captive binds') 'Yellow'
            Stop-Hotspot
        }

        if ($WaitPort -gt 0) {
            Write-Log ('waiting for UDP ' + $WaitPort + ' to be held by the captive node process...')
            if (Wait-PortOwner -Port $WaitPort -Owner 'node' -TimeoutSec $WaitTimeout) {
                Write-Log ('port ' + $WaitPort + ' is ours now - safe to bring the hotspot up')
            } else {
                Write-Log ('port ' + $WaitPort + ' still not ours after ' + $WaitTimeout + 's - starting hotspot anyway') 'Yellow'
            }
        }

        $ok = Start-NetshHotspot
        if (-not $ok) {
            Write-Log 'netsh hostednetwork unavailable - switching to Windows Mobile Hotspot' 'Yellow'
            $ok = Start-MobileHotspot
        }

        if ($ok) { Write-Log 'hotspot ready' 'Green'; exit 0 }
        Write-Log 'FAILED to bring up a hotspot (netsh AND mobile hotspot both failed)' 'Red'
        exit 1
    }
}
