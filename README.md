English | [中文](README_ZH.md)

# Gaming GeForce + RTX Workstation Card in One Windows PC

![status](https://img.shields.io/badge/status-working-brightgreen)
![platform](https://img.shields.io/badge/platform-Windows%2011-blue)
![gpus](https://img.shields.io/badge/GPUs-RTX%204070%20Ti%20Super%20%2B%20RTX%204000%20Ada-orange)

A practical, verified guide to running a **consumer GeForce card for gaming** and an
**OEM RTX professional card for compute/rendering** side by side in the same Windows
machine — including the exact failure mode that makes most people give up, and the
one workaround that actually holds.

Everything here was reproduced on real hardware:

| | Card A | Card B |
|---|---|---|
| Model | NVIDIA GeForce RTX 4070 Ti Super | NVIDIA RTX 4000 Ada Generation (**HP OEM**) |
| Silicon | AD103, 66 SM, 16 GB | AD104(\*), 48 SM, 20 GB |
| Role | games, display output | CUDA, rendering, AI |
| Slot | CPU PCIe x16 | chipset PCIe x4 |
| Final driver | GeForce **621.14** | HP RTX Enterprise **621.14** |

<del>(\*) Later discovery: According to GPU-Z, the core code name of this graphics card is AD103, not AD104. The following operations may not be applicable to the RTX 4000 Ada Generation of AD104.</del>
(\*) Major discovery: In MSI Afterburner, this core is named AD104GL-A (the RTX 4070 Ti Super uses AD103-A); in AIDA64, it is named AD104GL. Based on the current evidence alone, this is sufficient to refute the claim that the core of the RTX 4000 Ada Generation is AD103.

---

## TL;DR

1. **Both cards must run the exact same driver version.** NVIDIA installs a single
   kernel driver (`nvlddmkm.sys`); two different versions cannot coexist.
2. **A GeForce driver package does not list most OEM professional cards.** It matches
   them by PCI *subsystem ID*, and OEM variants (HP/Dell/Lenovo) are usually missing.
3. Therefore: **install a GeForce driver whose version number is identical to your
   OEM's workstation driver**, one package per card. Same version ⇒ same kernel
   binary ⇒ both cards start.
4. Never update one side alone.

If no matching pair of versions exists for your cards, see
[Solution B](#solution-b--patched-inf-advanced) and
[Solution C](#solution-c--change-the-hardware).

---

## The symptom

Typical reports, all of which are the *same* underlying problem:

- Device Manager shows the GeForce card as **"Microsoft Basic Display Adapter"** or
  with a yellow mark, **Code 31** or **Code 43**.
- Task Manager → Performance lists only one NVIDIA GPU (plus the iGPU).
- `nvidia-smi` sees only one GPU.
- The monitor *does* light up on the GeForce card's HDMI/DP port — because Windows
  falls back to the basic display driver, so you get a picture but no 3D, no CUDA,
  wrong resolution/refresh rate.
- Or the reverse: the workstation card disappears after you install a GeForce driver.

Typical trigger: you installed the vendor's driver for the professional card, then
installed (or Windows Update installed) a GeForce driver — or vice versa.

---

## Root cause

Two independent mechanisms combine.

### 1. One kernel driver, many packages

Windows happily keeps several display driver packages in
`C:\Windows\System32\DriverStore\FileRepository`, but NVIDIA's package installs a
**single** kernel service:

```
HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm  ->  ...\nv_dispi.inf_amd64_xxx\nvlddmkm.sys
```

Only one build of that binary can run. If GPU A is bound to a 621.24 package and
GPU B to a 621.14 package, the card whose package no longer matches the loaded
binary fails to start — `CM_PROB_FAILED_ADD` (Code 31), `CM_PROB_FAILED_START`, or
Code 43.

### 2. OEM subsystem-ID lock

Professional cards are listed in the INF per board variant:

```
%NVIDIA_DEV.27B2.181B.1028% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B1028
%NVIDIA_DEV.27B2.181B.10DE% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B10DE
```

- `27B2` = RTX 4000 Ada
- `181B` = board ID
- `1028` = Dell, `10DE` = NVIDIA reference, **`103C` = HP**

The HP card in this machine reports `SUBSYS_181B103C`, and the official GeForce
package (all 43 INFs inside the 621.24 installer were checked) contains **no**
`DEV_27B2&SUBSYS_181B103C` entry — not even in the HP-specific `nvhmi.inf`.

Conversely, HP's workstation package lists **only** `SUBSYS_181B103C` and contains
no GeForce device IDs at all.

So: **no single signed package covers both cards.** The only way to have both is to
give each card its *own* package, and make those two packages the *same version*.

> `check-inf-coverage.ps1` in this repo prints exactly this matrix for your machine.

---

## Solution A — version-matched paired drivers (recommended)

Fully signed, no hacks, survives reboots.

### Requirements

- A GeForce driver version **V**
- Your OEM's workstation driver version **V** (same number)
- Both packages must be downloaded, not installed by an auto-updater

### How to find a matching pair

Driver version numbering:

```
Windows "32.0.16.2114"  ==  NVIDIA "621.14"
                          ^^^ ^^
                          |   +-- last two digits
                          +------ 6xx branch
```

Check the OEM package's version (Device Manager → card → Driver tab, or the INF's
`DriverVer`). Then probe NVIDIA's archive for a GeForce build with the same number:

```powershell
$v = '621.14'
$u = "https://us.download.nvidia.com/Windows/$v/$v-desktop-win10-win11-64bit-international-dch-whql.exe"
try { (Invoke-WebRequest $u -Method Head -UseBasicParsing).StatusCode } catch { 'not published' }
```

If it returns `200`, you have a matching pair. If not, only odd numbers exist for
that branch — go to [Solution B](#solution-b--patched-inf-advanced) or
[Solution C](#solution-c--change-the-hardware).

### Procedure

> Do all of this from an **elevated** PowerShell. Have both packages extracted to
> local disk first (each is ~4 GB extracted).

```powershell
# 0) Inventory. Note the subsystem ID and every installed NVIDIA package.
.\scripts\check-inf-coverage.ps1
.\scripts\diagnose.ps1

# 1) Back up the OEM package so you can always roll back.
#    Find its folder name in diagnose.ps1 output, then:
robocopy "C:\Windows\System32\DriverStore\FileRepository\nvwuwi.inf_amd64_XXXX" `
         "D:\backup\nvwuwi" /E

# 2) Remove every stale NVIDIA display package.
#    Repeat for each "Published Name" whose "Original Name" starts with nv
#    and whose "Class Name" is Display.
pnputil /delete-driver oem44.inf /uninstall
pnputil /delete-driver oem45.inf /uninstall

# 3) Install the GeForce package for the gaming card, straight from the
#    extracted folder. Using pnputil avoids the vendor installer, which tends
#    to uninstall everything and then fail on downgrades.
pnputil /add-driver "D:\pkg621.14\Display.Driver\nv_dispi.inf" /install

# 4) Install the OEM workstation package for the professional card.
pnputil /add-driver "D:\backup\nvwuwi\nvwuwi.inf" /install

# 5) Re-enumerate so both cards re-run driver selection.
pnputil /scan-devices
```

Then reboot once. A card that reports `CM_PROB_FAILED_POST_START` / Code 43 right
after the swap almost always clears on that reboot, because the kernel driver was
still resident from the previous session.

### Verify

```powershell
nvidia-smi -L
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv
Get-PnpDevice -Class Display -PresentOnly | Select-Object FriendlyName,Problem
```

Expected:

```
GPU 0: NVIDIA GeForce RTX 4070 Ti SUPER
GPU 1: NVIDIA RTX 4000 Ada Generation

index, name, driver_version, memory.total [MiB]
0, NVIDIA GeForce RTX 4070 Ti SUPER, 621.14, 16376 MiB
1, NVIDIA RTX 4000 Ada Generation, 621.14, 20475 MiB
```

Both `Problem` values must be `CM_PROB_NONE`, and both INF paths must be *different*
packages with the *same* driver version.

### Real measured numbers (this machine)

| Test | RTX 4070 Ti Super | RTX 4000 Ada |
|---|---|---|
| FP16 matmul 8192³ | 87.8 TFLOPS | 68.6 TFLOPS |
| TF32 matmul 4096³ | 46.4 TFLOPS | 38.3 TFLOPS |
| VRAM bandwidth (copy) | 604 GB/s | 312 GB/s |
| Training, small MLP | ~1080 step/s | ~1480 step/s |
| Concurrent FP16 matmul | 92.5 TFLOPS | 74.1 TFLOPS |
| **Combined while running both** | **166.6 TFLOPS** | |
| Cross-GPU copy 512 MiB | 6.22 GB/s (no P2P) | |

Run `scripts/verify/gpu_test.py` and `gpu_test2.py` to reproduce.

---

## Maintenance — read this or it will break again

The configuration depends on a **version lock between two packages**. Anything that
updates one side alone will break the professional card.

1. **Do not use NVIDIA App auto-update.** It only knows the GeForce line.
2. **Block Windows Update from installing drivers:**
   - Settings → System → About → Advanced system settings → Hardware →
     Device installation settings → **No**
   - or policy: `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` →
     `ExcludeWUDriversInQualityUpdate = 1`
3. When you *do* want to update: find the new OEM workstation driver first, then
   look for the GeForce build with the same number, and install **both** in one
   session.
4. Keep the OEM package backup (`Solution A` step 1). It is the only fast rollback.

---

## Solution B — patched INF (advanced)

Use only when no matching version pair exists.

The idea: take the GeForce INF, add your OEM subsystem ID, install it for the
professional card. `scripts/update-nvidia.ps1` does the patching.

**What actually happens:** the package installs, but because the INF no longer
matches NVIDIA's signed catalog, Windows **excludes it from driver ranking**. The
card stays on "Microsoft Basic Display Adapter". Forcing it through Device Manager
("Have Disk") requires booting with driver signature enforcement disabled (F7) and
is fragile — a later Windows Update or driver refresh silently reverts it.

```powershell
# Patch a copy (safe, changes nothing on the system)
.\scripts\update-nvidia.ps1 -SubSys 181B103C -PatchOnly

# Attempt install (must be in an F7 "disable driver signature enforcement" session)
.\scripts\update-nvidia.ps1 -SubSys 181B103C
```

Status on this hardware: **did not work** — the card never bound. Documented here so
you don't spend a weekend on it. If it works for you, note that every driver update
needs the same treatment.

---

## Solution C — change the hardware

If your professional card is an OEM variant and no matching driver pair exists:

- **Swap it for a non-OEM unit.** NVIDIA's GeForce INFs do list the Dell
  (`181B1028`) and NVIDIA reference (`181B10DE`) variants, so those bind to a
  GeForce driver without any trickery.
- **Or run one card per machine** and use the other over the network
  (e.g. a small render node).
- **Or accept one card**: keep the GeForce for games, leave the professional card
  installed but unused.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Task Manager shows only one NVIDIA GPU | Card bound to `display.inf` | `check-inf-coverage.ps1` → your INF does not list the card |
| Code 31 (`CM_PROB_FAILED_ADD`) | Two packages of different versions | Align both to the same version |
| Code 43 right after swapping drivers | Kernel driver still resident | Reboot |
| Code 43 persists after reboot | The two packages' binaries differ | No fix; use Solution B/C |
| `nvidia-smi` missing | Installer uninstalled the old driver and failed | Reinstall one package with `pnputil` |
| Game renders on the wrong GPU | Display attached to the other card | Plug the monitor into the gaming card; or Settings → Display → Graphics → per-app GPU |
| Low resolution / 29 Hz on a 4K TV | Basic display driver, or HDMI 1.4 cable | Fix the driver; use an HDMI 2.1 cable |
| Only 1× PCIe width on the pro card | It sits in a chipset x4 slot | Expected; irrelevant for compute |
| Professional card lost Mosaic/Sync/ISV certification | It now runs a GeForce-class driver | Unavoidable when sharing one machine |

---

## Hardware notes

- **Slots:** put the gaming card in the CPU-attached x16 slot. The professional
  card is fine in a chipset x4 slot (measured: full compute throughput, ~6 GB/s
  host copy). Do not put the gaming card behind the chipset.
- **Power:** add both TGP figures plus ~150 W for the rest of the system. Here
  285 W + 130 W ⇒ 850 W PSU minimum, 1000 W comfortable.
- **Airflow:** blower-style workstation cards exhaust outside the case and pair
  well with an open-air gaming card; still leave one slot of gap.
- **BIOS:** enable Above 4G Decoding and Resizable BAR. Set the gaming card as the
  primary display device.
- **ECC:** workstation cards default to ECC off. `nvidia-smi -e 1` enables it at
  the cost of ~1 GB VRAM and some bandwidth.
- **No NVLink on Ada consumer/workstation cards** — no P2P, no VRAM pooling. A model
  must fit in one card unless you implement model parallelism yourself.

---

## Repository layout

```
.
├── README.md                      this file
├── README_ZH.md                   Chinese version
├── docs/
│   ├── EVIDENCE.md                raw diagnostic evidence from the working machine
│   └── DRIVER-VERSION-MAP.md      how to read NVIDIA/Windows version numbers
└── scripts/
    ├── diagnose.ps1               collect full display/driver state
    ├── check-inf-coverage.ps1     does the installed INF list your card?
    ├── rebind-device.ps1          force a device re-enumeration
    ├── update-nvidia.ps1          Solution B: patch INF with an OEM subsystem ID
    └── verify/
        ├── gpu_test.py            tensor-core, bandwidth, correctness, parallel
        ├── gpu_test2.py           precision-correct checks + real training
        └── mem_check.py           large VRAM allocation integrity
```

---

## Appendix — how this was diagnosed

1. `nvidia-smi -L` saw one GPU; Device Manager showed the other as Code 31.
2. `Get-PnpDevice` + `DEVPKEY_Device_DriverInfPath` showed the two cards bound to
   **two different packages with two different versions**.
3. `nvlddmkm.sys` version matched only one of them.
4. Extracting all INFs from the official GeForce installer and grepping for
   `DEV_27B2` proved the HP subsystem ID was missing.
5. Installing a GeForce package whose version equalled HP's package made both
   cards start on the same kernel binary.

See `docs/EVIDENCE.md` for the actual command output.

The entire project was developed by `Deepseek V4.1 Flash 1017`, which explored and executed relevant commands through `Deepseek Harness`.