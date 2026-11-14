# check-inf-coverage.ps1
#
# THE most useful diagnostic for this problem.
#
# It answers one question: for each NVIDIA GPU in this machine, does any driver
# package that is currently installed actually list that GPU?
#
# GeForce cards are listed generically (PCI\VEN_10DE&DEV_xxxx).
# Professional / OEM cards are listed per board variant, with a subsystem ID
# (PCI\VEN_10DE&DEV_xxxx&SUBSYS_181B103C). If your card is an OEM variant that
# the package does not list, Windows silently refuses to bind the driver and the
# card falls back to "Microsoft Basic Display Adapter" - no 3D, no CUDA.
#
# Run:  powershell -ExecutionPolicy Bypass -File check-inf-coverage.ps1

$ErrorActionPreference = 'SilentlyContinue'

function Get-GpuHardwareIds {
  Get-PnpDevice -Class Display -PresentOnly | Where-Object { $_.InstanceId -like 'PCI\VEN_10DE*' } | ForEach-Object {
    if ($_.InstanceId -match 'PCI\\VEN_10DE&DEV_([0-9A-Fa-f]{4})&SUBSYS_([0-9A-Fa-f]{8})') {
      $inf = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data
      $ver = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data
      [pscustomobject]@{
        Name     = $_.FriendlyName
        Device   = 'DEV_' + $Matches[1].ToUpper()
        SubSys   = $Matches[2].ToUpper()
        Problem  = $_.Problem
        BoundInf = $inf
        BoundVer = $ver
      }
    }
  }
}

function Get-DisplayInfs {
  $repo = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
  Get-ChildItem $repo -Directory | Where-Object { $_.Name -match '^nv.*\.inf_amd64' } | ForEach-Object {
    $inf = Get-ChildItem $_.FullName -Filter '*.inf' | Select-Object -First 1
    if ($inf) {
      $raw = Get-Content $inf.FullName -Raw
      $m = [regex]::Match($raw, 'DriverVer\s*=\s*[^,]+,\s*([0-9\.]+)')
      [pscustomobject]@{
        Folder  = $_.Name
        Inf     = $inf
        Version = if ($m.Success) { $m.Groups[1].Value.Trim() } else { '?' }
        Text    = $raw
      }
    }
  }
}

$gpus = @(Get-GpuHardwareIds)
$infs = @(Get-DisplayInfs)

Write-Host ''
Write-Host 'GPUs found:' -ForegroundColor Cyan
foreach ($g in $gpus) {
  Write-Host ("  {0}" -f $g.Name)
  Write-Host ("      hwid   : PCI\VEN_10DE&{0}&SUBSYS_{1}" -f $g.Device, $g.SubSys)
  Write-Host ("      state  : {0}   bound to {1} ({2})" -f $g.Problem, $g.BoundInf, $g.BoundVer)
}

foreach ($g in $gpus) {
  $exact   = "PCI\VEN_10DE&$($g.Device)&SUBSYS_$($g.SubSys)"
  $generic = "PCI\VEN_10DE&$($g.Device)"

  Write-Host ''
  Write-Host ("{0}" -f $g.Name) -ForegroundColor Yellow
  Write-Host ("  looking for  {0}" -f $exact)

  $exactHits = @()
  $genericHits = @()
  foreach ($i in $infs) {
    if ($i.Text -match [regex]::Escape($exact)) { $exactHits += $i }
    elseif ($i.Text -match [regex]::Escape($generic)) { $genericHits += $i }
  }

  if ($exactHits.Count -gt 0) {
    Write-Host '  EXACT MATCH (vendor-specific listing)' -ForegroundColor Green
    foreach ($h in $exactHits) { Write-Host ("      {0,-45} {1}" -f $h.Folder, $h.Version) -ForegroundColor Green }
  } elseif ($genericHits.Count -gt 0) {
    Write-Host '  GENERIC MATCH (listed without subsystem ID - typical for retail GeForce)' -ForegroundColor Yellow
    foreach ($h in $genericHits) { Write-Host ("      {0,-45} {1}" -f $h.Folder, $h.Version) -ForegroundColor Yellow }
  } else {
    Write-Host '  NO INSTALLED PACKAGE LISTS THIS CARD' -ForegroundColor Red
    Write-Host '  -> Windows cannot bind a vendor driver to it.' -ForegroundColor Red
    Write-Host '  -> This is the OEM subsystem-ID lock described in the README.' -ForegroundColor Red
  }
}

Write-Host ''
Write-Host 'Reminder: two cards can only run together if the package bound to each one' -ForegroundColor DarkGray
Write-Host 'has the SAME driver version. Compare the "bound to" versions above.' -ForegroundColor DarkGray
