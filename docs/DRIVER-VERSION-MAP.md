# Reading NVIDIA driver version numbers

Windows reports one string, NVIDIA's website another. They encode the same build.

```
Windows   :  32.0.16.2114
NVIDIA    :  621.14

Mapping   :  take the branch digit from the 3rd field and the last four digits
             32.0.1[6].[2114]
                        ^    ^^^^
                        |    └── 21.14  -> minor . patch
                        └─────── 6      -> 6xx branch
             => 6 + 21.14 = 621.14
```

More examples:

| Windows version | NVIDIA version |
|---|---|
| 31.0.15.3667 | 536.67 |
| 32.0.15.9579 | 559.79 |
| 32.0.16.1088 | 621.08 |
| 32.0.16.2114 | 621.14 |
| 32.0.16.2124 | 621.24 |

Rule of thumb: the *last two digits* of the Windows string are the NVIDIA minor
version; they must match exactly for two packages to share a kernel driver.

---

## Finding a matching GeForce build

NVIDIA publishes desktop DCH packages at a predictable URL:

```
https://us.download.nvidia.com/Windows/<ver>/<ver>-desktop-win10-win11-64bit-international-dch-whql.exe
```

Probe without downloading:

```powershell
function Test-NvidiaDriver($v) {
  $u = "https://us.download.nvidia.com/Windows/$v/$v-desktop-win10-win11-64bit-international-dch-whql.exe"
  try { "OK   $v  $((Invoke-WebRequest $u -Method Head -UseBasicParsing).StatusCode)" }
  catch { "MISS $v" }
}
'621.08','621.10','621.14','621.18','621.24' | ForEach-Object { Test-NvidiaDriver $_ }
```

GeForce desktop builds are released weekly-ish but not for every number, so a given
OEM workstation version may have no GeForce twin. Check before planning.

---

## Reading a package's version

From an INF file:

```powershell
Select-String -Path .\nv_dispi.inf -Pattern '^\s*DriverVer'
# DriverVer = 11/07/2026, 32.0.16.2124
```

From the driver store:

```powershell
pnputil /enum-drivers
```

From Device Manager: card → Properties → Driver → Driver Version.

---

## Which INF name is which

Official NVIDIA installers ship one INF per vendor variant plus a universal one.
Inside `Display.Driver\`:

| INF | Covers |
|---|---|
| `nv_dispi.inf` | universal / retail GeForce |
| `nvhmi.inf`, `nvhqi.inf` | HP-branded systems |
| `nvdmi.inf` | Dell |
| `nvlei.inf` | Lenovo |
| `nvami.inf`, `nvaei.inf` | ASUS / Acer |
| `nvmii.inf`, `nvmsi.inf`-style | MSI |
| `nv_dispsi.inf` | reduced universal package (delivered via Windows Update / OEM tools) |

An OEM *workstation* driver from HP/Dell/Lenovo usually ships a single INF
(`nvwuwi.inf`, `nvwu.inf`) restricted to that vendor's subsystem IDs and containing
no GeForce device IDs at all.

---

## Quick sanity check

After installing a pair, confirm both devices point at **different INFs with the
same version**:

```powershell
Get-PnpDevice -Class Display -PresentOnly | ForEach-Object {
  "{0,-35} {1,-22} {2}" -f $_.FriendlyName, $_.Problem,
    (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data
}
```

If the versions differ, one of the cards will fall over on the next boot.
