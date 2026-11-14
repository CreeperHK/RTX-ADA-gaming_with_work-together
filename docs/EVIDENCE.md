# Diagnostic evidence

Collected on the reference machine (Windows 11, build 26200, ASUS B650-A, Ryzen 7 9850X3D).
Names of the machine and user have been removed; paths are generic.

---

## 1. Hardware IDs of the two cards

```
NVIDIA GeForce RTX 4070 Ti Super
  PCI\VEN_10DE&DEV_2705&SUBSYS_18CE1771&REV_A1   location: PCI bus 1  (CPU x16)
  subsystem: 18CE1771  -> 1771 = board vendor, 18CE = board id

NVIDIA RTX 4000 Ada Generation
  PCI\VEN_10DE&DEV_27B2&SUBSYS_181B103C&REV_A1   location: PCI bus 5  (chipset x4)
  subsystem: 181B103C  -> 103C = HP, 181B = board id
```

`103C` is the important part. It is an HP OEM board variant.

---

## 2. Broken state (before the fix)

Two NVIDIA display packages, two different versions, one kernel driver:

```
FriendlyName                     Problem               INF            Driver version
NVIDIA RTX 4000 Ada Generation   CM_PROB_NONE          oem44.inf      32.0.16.2114   (621.14)
NVIDIA GeForce RTX 4070 Ti SUPER CM_PROB_FAILED_ADD    oem85.inf      32.0.16.2124   (621.24)
```

```
nvlddmkm ImagePath : ...\nvwuwi.inf_amd64_b98dcb64\nvlddmkm.sys   (621.14)
nvidia-smi -L      : GPU 0: NVIDIA RTX 4000 Ada Generation        (only one GPU)
```

The GeForce card was present on the PCI bus and its HDMI output produced a picture,
because Windows attached the **Microsoft Basic Display Adapter** to it:

```
ROOT\BasicDisplay\0000  ->  Generic Monitor (SAMSUNG)   Status: OK
```

That is why "the display works but Task Manager shows no GeForce GPU".

---

## 3. INF coverage — the root cause

### GeForce 621.24 package (`nv_dispsi.inf`, also `nv_dispi.inf` from the official installer)

Every line mentioning the Ada device:

```
%NVIDIA_DEV.27B2.181B.1028% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B1028   (Dell)
%NVIDIA_DEV.27B2.181B.10DE% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B10DE   (NVIDIA ref)
%NVIDIA_DEV.27B2.181B.1028% = Section063, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B1028
%NVIDIA_DEV.27B2.181B.10DE% = Section063, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B10DE
```

`SUBSYS_181B103C` appears **nowhere** in the whole official 621.24 installer —
all 43 INFs inside were extracted and searched, including the HP-specific
`nvhmi.inf` (which contains 1296 other `103C` entries, none for `27B2`).

### HP RTX Enterprise 621.14 package (`nvwuwi.inf`)

Every line mentioning the Ada device:

```
%NVIDIA_DEV.27B2.181B.103C% = Section028, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B103C
%NVIDIA_DEV.27B2.181B.103C% = Section029, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B103C
```

And **zero** occurrences of `DEV_2705` (the GeForce card).

### Conclusion

| Package | RTX 4070 Ti Super | HP RTX 4000 Ada |
|---|---|---|
| GeForce 621.24 | yes | **no** |
| HP RTX Enterprise 621.14 | **no** | yes |
| GeForce 621.14 | yes | **no** |

No single signed package covers both. Two packages are required, and their versions
must match.

---

## 4. Intermediate failure — mixed versions

Installing GeForce 621.24 for one card and HP 621.14 for the other gives, on the
card whose package no longer matches the loaded binary:

```
Device Status: 0x01802400  [0x0a - 0xc01e0438]
```

`0xC01E0438` is the kernel-mode driver reporting a version mismatch with the INF.
The card ends up on `display.inf` with Code 10/31.

A patched (unsigned) INF does not help: the package is accepted into the driver
store but excluded from ranking.

```
pnputil /add-driver (patched nv_dispsi.inf) /install     -> exit 259
  "The driver package on the device is already the newest version"
  ... but the device still binds to display.inf
```

SetupAPI log shows it installing the device from a *different*, older signed
package (`nvwu.inf`, 31.0.15.3667), then failing:

```
flq:  File '...\nvwu.inf_amd64_f669fa13\...' pruned from copy
dvi:  Device Status: 0x01802400 [0x0a - 0xc01e0438]
```

---

## 5. Fixed state

```
NVIDIA RTX 4000 Ada Generation   CM_PROB_NONE   oem45.inf   32.0.16.2114  (nvwuwi.inf)
NVIDIA GeForce RTX 4070 Ti SUPER CM_PROB_NONE   oem44.inf   32.0.16.2114  (nv_dispi.inf)

nvlddmkm ImagePath : ...\nvwuwi.inf_amd64_b98dcb64\nvlddmkm.sys  (32.0.16.2114)

GPU 0: NVIDIA GeForce RTX 4070 Ti SUPER
GPU 1: NVIDIA RTX 4000 Ada Generation
```

Two different INF packages, **identical driver version**. One kernel binary serves
both cards, no mismatch, no fallback.

`nvidia-smi` detail:

```
index, name, driver_version, memory.total [MiB], pcie.link.gen.max, pcie.link.width.max, power.limit
0, NVIDIA GeForce RTX 4070 Ti SUPER, 621.14, 16376 MiB, 4, 16, 320.00 W
1, NVIDIA RTX 4000 Ada Generation, 621.14, 20475 MiB, 4, 4, 130.00 W
```

---

## 6. Functional verification

```
FP16 8192^3   : cuda:0  87.8 TFLOPS   cuda:1  68.6 TFLOPS
TF32 4096^3   : cuda:0  46.4 TFLOPS   cuda:1  38.3 TFLOPS
D2D copy      : cuda:0 604 GB/s       cuda:1 312 GB/s
Correctness   : max_abs_err 4.96e-05 / 3.82e-05  (vs float64 CPU)
Parallel      : 92.5 + 74.1 = 166.6 TFLOPS combined (single card ~93.5)
Cross-GPU     : 512 MiB  6.22 GB/s,  can_device_access_peer = False
VRAM integrity: 11.8 GiB and 15.0 GiB filled and verified, error 0
```

No Xid errors, no `nvlddmkm` events after the reboot.

---

## 7. Things that were tried and did not work

| Attempt | Result |
|---|---|
| Patch GeForce INF with `SUBSYS_181B103C`, install normally | `0xE000024B` — hash not found in catalog |
| Same, after setting `HKLM\SOFTWARE\Microsoft\Driver Signing\Policy = 0` | still rejected |
| Same, in an F7 "disable driver signature enforcement" session | package installs, but is excluded from ranking; card stays on `display.inf` |
| Force rebind with `pnputil /remove-device` + `/scan-devices` | Windows binds the old 31.0.15.3667 package instead |
| Install GeForce 621.14 with the official installer while 621.24 present | installer exit 1, uninstalled the existing driver, left no `nvidia-smi` |
| Match versions the other way (HP driver for both) | HP package contains no GeForce IDs at all |

The only approach that held was installing two same-version packages through
`pnputil`, bypassing the vendor installers entirely.
