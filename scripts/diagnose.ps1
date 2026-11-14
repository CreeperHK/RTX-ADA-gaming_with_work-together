# diagnose.ps1
# Collects everything needed to understand a mixed GeForce + RTX (pro) setup.
# Run in an elevated PowerShell:  powershell -ExecutionPolicy Bypass -File diagnose.ps1
# Output: console + diagnose-report.txt next to this script.

$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path $PSScriptRoot 'diagnose-report.txt'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line($t) { $lines.Add($t); Write-Host $t }

function Section($t) {
  Add-Line ''
  Add-Line ('=' * 70)
  Add-Line $t
  Add-Line ('=' * 70)
}

Section 'SYSTEM'
Add-Line ("OS        : " + (Get-CimInstance Win32_OperatingSystem).Caption + " " + (Get-CimInstance Win32_OperatingSystem).Version)
Add-Line ("Board     : " + (Get-CimInstance Win32_BaseBoard).Manufacturer + " " + (Get-CimInstance Win32_BaseBoard).Product)
Add-Line ("CPU       : " + (Get-CimInstance Win32_Processor).Name)
Add-Line ("Boot      : " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)

Section 'NVIDIA-SMI'
$smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path $smi) {
  Add-Line (& $smi -L | Out-String)
  Add-Line (& $smi --query-gpu=index,name,driver_version,memory.total,pcie.link.gen.max,pcie.link.width.max,power.limit --format=csv | Out-String)
  Add-Line ('KMD service: ' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm').ImagePath)
  $sysPath = Join-Path $env:SystemRoot 'System32\drivers\nvlddmkm.sys'
  if (Test-Path $sysPath) {
    Add-Line ('nvlddmkm   : ' + [System.Diagnostics.FileVersionInfo]::GetVersionInfo($sysPath).FileVersion)
  }
} else {
  Add-Line 'nvidia-smi.exe NOT FOUND - the NVIDIA display driver is not properly installed.'
}

Section 'DISPLAY DEVICES (class Display)'
Get-PnpDevice -Class Display -PresentOnly | ForEach-Object {
  $inf = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data
  $ver = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data
  $loc = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo').Data
  Add-Line ("{0,-45} {1,-32} inf={2,-14} ver={3}" -f $_.FriendlyName, $_.Problem, $inf, $ver)
  Add-Line ("    instance: " + $_.InstanceId)
  Add-Line ("    location: " + $loc)
}

Section 'NVIDIA DISPLAY DRIVER PACKAGES IN DRIVER STORE'
$drv = pnputil /enum-drivers | Out-String
$blocks = $drv -split "(`r`n){2,}"
foreach ($b in $blocks) {
  if ($b -match 'Original Name:\s+(nv.*\.inf)' -and $b -match 'Class Name:\s+Display') {
    $orig = $Matches[1]
    $pub  = ([regex]::Match($b, 'Published Name:\s+(\S+)')).Groups[1].Value
    $ver  = ([regex]::Match($b, 'Driver Version:\s+(.+)')).Groups[1].Value
    $sign = ([regex]::Match($b, 'Signer Name:\s+(.+)')).Groups[1].Value
    Add-Line ("{0,-12} {1,-18} {2,-28} signer={3}" -f $pub, $orig, $ver.Trim(), $sign.Trim())
  }
}

Section 'MONITORS AND THEIR ADAPTER'
Get-PnpDevice -Class Monitor -PresentOnly | ForEach-Object {
  $parent = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_Parent').Data
  Add-Line ("{0,-35} parent={1}" -f $_.FriendlyName, $parent)
}

Section 'RECENT DISPLAY / NVIDIA ERRORS (last 24h)'
Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-1) } |
  Where-Object { $_.ProviderName -match 'nvlddmkm|Display|Kernel-PnP' -and $_.LevelDisplayName -ne 'Information' } |
  Select-Object -First 15 |
  ForEach-Object { Add-Line ("{0}  id={1}  {2}  {3}" -f $_.TimeCreated, $_.Id, $_.ProviderName, ($_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(110, $_.Message.Length))) }

$lines -join "`r`n" | Set-Content -Path $out -Encoding UTF8
Write-Host ''
Write-Host "Report written to $out"
