# Start Windows Mobile Hotspot via WinRT API
# Usage: powershell -File start-hotspot.ps1 [-Verbose]

param(
    [switch]$Verbose
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    if ($Verbose) {
        Write-Host "[Hotspot] $Message" -ForegroundColor $Color
    }
}

# Load WinRT assemblies
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

function Start-Tethering {
    try {
        # Get internet connection profile
        $connectionProfile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()

        if (-not $connectionProfile) {
            Write-Log "No active network connection found" "Red"
            return $false
        }

        # Create tethering manager
        $tetheringManager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($connectionProfile)

        $state = $tetheringManager.TetheringOperationalState
        Write-Log "Current hotspot state: $state" "Cyan"

        switch ($state) {
            "On" {
                Write-Log "Hotspot is already running" "Green"
                Write-Log "Connected clients: $($tetheringManager.ClientCount)" "Green"
                return $true
            }
            "Off" {
                Write-Log "Starting mobile hotspot..." "Yellow"

                $asyncOp = $tetheringManager.StartTetheringAsync()

                # Wait for async completion (max 60 seconds)
                $timeout = 60
                while ($asyncOp.Status -eq [Windows.Foundation.AsyncStatus]::Started -and $timeout -gt 0) {
                    Start-Sleep -Seconds 1
                    $timeout--
                }

                if ($asyncOp.Status -eq [Windows.Foundation.AsyncStatus]::Completed) {
                    Write-Log "Hotspot start API completed" "Green"
                } elseif ($asyncOp.Status -eq [Windows.Foundation.AsyncStatus]::Error) {
                    Write-Log "Hotspot start failed: $($asyncOp.ErrorCode)" "Red"
                    return $false
                } else {
                    Write-Log "Hotspot async start timed out (60s)" "Yellow"
                }

                # Even if async timed out, the hotspot may still be transitioning to ON
                # Wait for InTransition -> On (max 30 more seconds)
                if ($tetheringManager.TetheringOperationalState -eq "InTransition") {
                    Write-Log "Hotspot is still transitioning, waiting..." "Yellow"
                    $timeout = 30
                    while ($tetheringManager.TetheringOperationalState -eq "InTransition" -and $timeout -gt 0) {
                        Start-Sleep -Seconds 1
                        $timeout--
                    }
                }

                if ($tetheringManager.TetheringOperationalState -eq "On") {
                    Write-Log "Hotspot started successfully" "Green"
                    return $true
                } else {
                    Write-Log "Hotspot state: $($tetheringManager.TetheringOperationalState)" "Yellow"
                    Write-Log "Hotspot may need manual activation" "Yellow"
                    return $false
                }
            }
            "InTransition" {
                Write-Log "Hotspot is transitioning, waiting..." "Yellow"
                $timeout = 15
                while ($tetheringManager.TetheringOperationalState -eq "InTransition" -and $timeout -gt 0) {
                    Start-Sleep -Seconds 1
                    $timeout -= 1
                }
                Write-Log "Current state: $($tetheringManager.TetheringOperationalState)" "Cyan"
                return ($tetheringManager.TetheringOperationalState -eq "On")
            }
            default {
                Write-Log "Unknown state: $state" "Red"
                return $false
            }
        }
    }
    catch {
        Write-Log "Exception: $_" "Red"
        return $false
    }
}

# Execute
$result = Start-Tethering
if ($result) {
    Write-Log "Mobile hotspot is ready" "Green"
    exit 0
} else {
    Write-Log "Failed to start mobile hotspot" "Red"
    exit 1
}
