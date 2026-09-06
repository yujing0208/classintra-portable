param(
    [string]$TaskName = 'IR_Hotspot_Redirect'
)

$ErrorActionPreference = 'Stop'

$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$root = $service.GetFolder('\')
$task = $root.GetTask($TaskName)
$definition = $task.Definition

# PT0S means no execution time limit. Keep recovery on the task itself as a
# second layer in case the watchdog wrapper is terminated unexpectedly.
$definition.Settings.ExecutionTimeLimit = 'PT0S'
$definition.Settings.RestartCount = 999
$definition.Settings.RestartInterval = 'PT1M'
$definition.Settings.DisallowStartIfOnBatteries = $false
$definition.Settings.StopIfGoingOnBatteries = $false
$root.RegisterTaskDefinition($TaskName, $definition, 6, $null, $null, $task.Definition.Principal.LogonType, $null) | Out-Null
