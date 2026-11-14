# update-nvidia.ps1
#
# Advanced / fallback path (README "Solution B").
#
# Use this only when you cannot match driver versions (README "Solution A").
# It takes the newest GeForce display package from the Windows driver store,
# adds your OEM's PCI subsystem ID to its INF, and tries to install it.
#
# A patched INF no longer matches NVIDIA's signed catalog, so Windows will accept
# it only in a boot session started with "Disable driver signature enforcement"
# (Troubleshoot > Advanced options > Startup Settings > 7).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File update-nvidia.ps1 -SubSys 181B103C -PatchOnly
#   powershell -ExecutionPolicy Bypass -File update-nvidia.ps1 -SubSys 181B103C
#
#   -SubSys    subsystem ID of the professional card (last 8 hex of the hardware
#              ID reported by check-inf-coverage.ps1), e.g. 181B103C for HP's
#              RTX 4000 Ada
#   -DeviceId  PCI device id, default DEV_27B2 (RTX 4000 Ada)
#   -PatchOnly patch a copy without installing

param(
  [Parameter(Mandatory = $true)][string]$SubSys,
  [string]$DeviceId = 'DEV_27B2',
  [switch]$PatchOnly,
  [string]$Source
)

$ErrorActionPreference = 'Stop'
$workRoot = Split-Path $PSScriptRoot -Parent
$latin1 = [Text.Encoding]::GetEncoding(28591)
$sub = $SubSys.ToUpper()

function Patch-Inf {
  param([string]$infPath, [string]$dev, [string]$subsys)

  $text = [IO.File]::ReadAllText($infPath, $latin1)
  if ($text -match [regex]::Escape("SUBSYS_$subsys")) {
    Write-Output "  INF already lists SUBSYS_$subsys - nothing to patch"
    return
  }
  $devHex = $dev -replace 'DEV_', ''

  $lines = $text -split "`r`n|`n"
  $out = New-Object System.Collections.Generic.List[string]
  $newTokens = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    $out.Add($line)
    # device line, e.g.:
    #   %NVIDIA_DEV.27B2.181B.1028% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B1028
    $m = [regex]::Match($line, '^%NVIDIA_DEV\.' + $devHex + '\.([0-9A-Fa-f]{4})\.([0-9A-Fa-f]{4})%\s*=\s*(Section\d+),\s*PCI\\VEN_10DE&DEV_' + $devHex + '&SUBSYS_([0-9A-Fa-f]{8})')
    if ($m.Success) {
      $board = $m.Groups[1].Value
      $token = "%NVIDIA_DEV.$devHex.$board.$subsys%"
      $out.Add("$token = $($m.Groups[3].Value), PCI\VEN_10DE&DEV_$devHex&SUBSYS_$subsys")
      if (-not $newTokens.Contains("NVIDIA_DEV.$devHex.$board.$subsys")) {
        $newTokens.Add("NVIDIA_DEV.$devHex.$board.$subsys")
      }
    }
  }

  if ($newTokens.Count -eq 0) { throw "No device line for $dev found - INF layout changed" }

  # add [Strings] entries at the end of each strings block that has our device
  $result = New-Object System.Collections.Generic.List[string]
  $pending = [System.Collections.Generic.Queue[string]]::new()
  foreach ($t in $newTokens) { $pending.Enqueue($t) }

  for ($i = 0; $i -lt $out.Count; $i++) {
    $line = $out[$i]
    $result.Add($line)
    if ($line -match "^NVIDIA_DEV\.$devHex\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\s*=" -and $pending.Count -gt 0) {
      $t = $pending.Dequeue()
      $friendly = ($line -split '=', 2)[1].Trim()
      $result.Add("$t = $friendly")
    }
  }

  [IO.File]::WriteAllText($infPath, ($result -join "`r`n"), $latin1)
  Write-Output ("  patched: " + ($newTokens -join ', '))
}

Write-Output '=== locating newest NVIDIA GeForce display package ==='
if ($Source) {
  $pick = [pscustomobject]@{ Dir = (Split-Path $Source); Inf = $Source; Ver = 'manual' }
} else {
  $repo = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
  $cands = Get-ChildItem $repo -Directory |
    Where-Object { $_.Name -match '^nv_dispi.*\.inf_amd64' } |
    ForEach-Object {
      $inf = Get-ChildItem $_.FullName -Filter '*.inf' | Select-Object -First 1
      if ($inf) {
        $m = Select-String -Path $inf.FullName -Pattern '^\s*DriverVer\s*=\s*([^,\r\n]+),([^\r\n]+)' | Select-Object -First 1
        [pscustomobject]@{
          Dir = $_.FullName; Inf = $inf.FullName
          Ver = if ($m) { $m.Matches.Groups[2].Value.Trim() } else { '0' }
        }
      }
    } | Sort-Object Ver -Descending
  if (-not $cands) { throw 'No GeForce display package found. Install the official driver first.' }
  $pick = $cands[0]
}
Write-Output ("  using: {0}  ({1})" -f $pick.Dir, $pick.Ver)

if ($PatchOnly) {
  $newInf = $pick.Inf
} else {
  $dst = Join-Path $workRoot ('patch-' + ($pick.Ver -replace '[^\d\.]', ''))
  if (-not (Test-Path $dst)) {
    Write-Output "=== copying package to $dst ==="
    robocopy $pick.Dir $dst /E /MT:16 /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
  }
  $newInf = Join-Path $dst (Split-Path $pick.Inf -Leaf)
}

Write-Output '=== patching INF ==='
Patch-Inf -infPath $newInf -dev $DeviceId -subsys $sub

if ($PatchOnly) { Write-Output "`nPatched copy: $newInf"; return }

Write-Output '=== installing ==='
pnputil /add-driver "$newInf" /install
$code = $LASTEXITCODE
Write-Output "pnputil exit=$code"

if ($code -ne 0) {
  Write-Output ''
  Write-Output 'Install refused - patched INF has an invalid signature (expected).'
  Write-Output 'Reboot: Troubleshoot > Advanced options > Startup Settings > 7'
  Write-Output 'then run this script again in that session.'
  return
}

pnputil /scan-devices | Out-Null
Start-Sleep -Seconds 6
Get-PnpDevice -Class Display -PresentOnly | Select-Object FriendlyName, Status, Problem | Format-Table -AutoSize
& (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe') -L
