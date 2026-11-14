# rebind-device.ps1
#
# Forces Windows to re-enumerate a display adapter and re-run driver selection.
# Use it after installing a driver package when Device Manager still shows
# "Microsoft Basic Display Adapter" or a yellow mark on the card.
#
# It never writes driver files itself - it only removes the device node and
# rescans, which makes PnP pick the best driver that is already installed.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File rebind-device.ps1
#   powershell -ExecutionPolicy Bypass -File rebind-device.ps1 -InstanceId "PCI\VEN_10DE&DEV_27B2&..."
#
# Run elevated.

param([string]$InstanceId)

$ErrorActionPreference = 'Continue'

$admin = (New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
  Start-Process powershell -Verb RunAs -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  )
  exit
}

Write-Host '=== before ===' -ForegroundColor Cyan
Get-PnpDevice -Class Display -PresentOnly |
  Select-Object FriendlyName, Status, Problem | Format-Table -AutoSize

# pick every NVIDIA display node that is not healthy
$targets = Get-PnpDevice -Class Display -PresentOnly | Where-Object {
  $_.InstanceId -like 'PCI\VEN_10DE*' -and $_.Problem -ne 'CM_PROB_NONE'
}
if ($InstanceId) {
  $targets = Get-PnpDevice -InstanceId $InstanceId
}

if (-not $targets) {
  Write-Host 'No unhealthy NVIDIA display device found.' -ForegroundColor Yellow
  exit 0
}

foreach ($t in $targets) {
  Write-Host ("removing node: " + $t.InstanceId)
  pnputil /remove-device $t.InstanceId
  Start-Sleep -Seconds 2
}

Write-Host '=== rescanning ==='
pnputil /scan-devices
Start-Sleep -Seconds 8

Write-Host '=== after ===' -ForegroundColor Cyan
Get-PnpDevice -Class Display -PresentOnly |
  Select-Object FriendlyName, Status, Problem | Format-Table -AutoSize

$smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path $smi) { & $smi -L }
