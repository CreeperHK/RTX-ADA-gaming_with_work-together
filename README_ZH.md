[English](README.md) | 中文


# 在同一台 Windows 電腦上同時使用「遊戲 GeForce 卡」與「RTX 專業卡」

![status](https://img.shields.io/badge/status-working-brightgreen)
![platform](https://img.shields.io/badge/platform-Windows%2011-blue)
![gpus](https://img.shields.io/badge/GPUs-RTX%204070%20Ti%20Super%20%2B%20RTX%204000%20Ada-orange)

一份經過實機驗證的指南：如何在**同一台 Windows 主機**裡，讓一張**消費級 GeForce 卡負責遊戲**、
一張**OEM 版 RTX 專業卡負責運算／渲染**同時正常工作——包含讓大多數人放棄的那個失敗模式，
以及唯一真正站得住腳的解法。

以下內容全部在真實硬體上重現過：

| | 卡 A | 卡 B |
|---|---|---|
| 型號 | NVIDIA GeForce RTX 4070 Ti Super | NVIDIA RTX 4000 Ada Generation（**HP OEM 版**） |
| 核心 | AD103，66 SM，16 GB | AD104(\*)，48 SM，20 GB |
| 用途 | 遊戲、螢幕輸出 | CUDA、渲染、AI |
| 插槽 | CPU 直連 PCIe x16 | 晶片組 PCIe x4 |
| 最終驅動 | GeForce **621.14** | HP RTX Enterprise **621.14** |

<del> (\*)後期發現：透過 GPU-Z，這張顯示卡的核心代號是 AD103，並非 AD104，下列操作可能並不適用於 AD104 的 RTX 4000 Ada Generation。</del>
(\*)重大發現：在 MSI Afterburner 中，這款核心被命名為 AD104GL-A（ RTX 4070 Ti Super 是 AD103-A ）；在 AIDA64 中，這款核心被命名為 AD104GL。單憑現在的證據，足以推翻 RTX 4000 Ada Generation 的核心是 AD103 的說法。

---

## 一句話結論

1. **兩張卡必須跑在完全相同的驅動版本上。** NVIDIA 只安裝一份核心驅動
   （`nvlddmkm.sys`），兩個不同版本無法共存。
2. **GeForce 驅動包並不認得大部分 OEM 版專業卡。** 它是靠 PCI *子系統 ID*
   來匹配的，而 OEM 變體（HP／Dell／Lenovo）通常不在清單裡。
3. 因此解法是：**安裝一個版本號與 OEM 工作站驅動完全相同的 GeForce 驅動**，
   一張卡一個包。版本相同 ⇒ 核心二進位相同 ⇒ 兩張卡都能啟動。
4. 永遠不要只更新其中一邊。

如果你的卡找不到成對的版本，請看
[方案 B](#方案-b--修改-inf進階) 與 [方案 C](#方案-c--更換硬體)。

---

## 症狀

以下各種描述，其實都是同一個根本問題：

- 裝置管理員裡 GeForce 卡顯示為 **「Microsoft Basic Display Adapter」** 或帶黃色驚嘆號，
  錯誤碼 **31** 或 **43**。
- 工作管理員 → 效能 只列出一個 NVIDIA GPU（加上內顯）。
- `nvidia-smi` 只看得到一張卡。
- 但螢幕**確實**從 GeForce 卡的 HDMI／DP 亮了——因為 Windows 退回了基本顯示驅動，
  所以有畫面，但沒有 3D、沒有 CUDA、解析度與刷新率也不對。
- 或者相反：裝了 GeForce 驅動後，專業卡消失了。

典型觸發情境：你先裝了專業卡的原廠驅動，之後又裝了 GeForce 驅動
（或 Windows Update 幫你裝了），反過來也一樣。

---

## 根本原因

兩個獨立機制疊加造成。

### 1. 一份核心驅動，多個驅動包

Windows 很樂意把多個顯示驅動包同時留在
`C:\Windows\System32\DriverStore\FileRepository`，但 NVIDIA 的驅動包只安裝**一個**
核心服務：

```
HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm  ->  ...\nv_dispi.inf_amd64_xxx\nvlddmkm.sys
```

這個二進位檔只能有一個版本在跑。若 GPU A 綁在 621.24 的包、GPU B 綁在 621.14 的包，
那個「與已載入二進位不符」的卡就會啟動失敗——`CM_PROB_FAILED_ADD`（錯誤碼 31）、
`CM_PROB_FAILED_START`，或錯誤碼 43。

### 2. OEM 子系統 ID 鎖

專業卡在 INF 裡是按板卡變體逐條列出的：

```
%NVIDIA_DEV.27B2.181B.1028% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B1028
%NVIDIA_DEV.27B2.181B.10DE% = Section062, PCI\VEN_10DE&DEV_27B2&SUBSYS_181B10DE
```

- `27B2` = RTX 4000 Ada
- `181B` = 板卡 ID
- `1028` = Dell，`10DE` = NVIDIA 公版，**`103C` = HP**

本機這張 HP 卡回報的是 `SUBSYS_181B103C`，而官方 GeForce 套件
（把 621.24 安裝包裡全部 43 個 INF 都檢查過）**完全沒有**
`DEV_27B2&SUBSYS_181B103C` 這一條——連 HP 專用的 `nvhmi.inf` 裡也沒有。

反過來，HP 的工作站驅動包**只**列了 `SUBSYS_181B103C`，完全沒有任何 GeForce 裝置 ID。

所以：**沒有任何一個已簽名的驅動包能同時涵蓋兩張卡。** 唯一的辦法是讓兩張卡各用
自己的包，並讓這兩個包的**版本號相同**。

> 本倉庫的 `check-inf-coverage.ps1` 會直接印出你這台機器的這張對照表。

---

## 方案 A — 版本配對安裝（推薦）

完全合規、正式簽名、重開機後依然有效。

### 前提

- 一個 GeForce 驅動版本 **V**
- 你的 OEM 工作站驅動版本 **V**（同一個數字）
- 兩個包都要自己下載，不能靠自動更新

### 如何找到成對的版本

版本號對照規則：

```
Windows 的 "32.0.16.2114"  ==  NVIDIA 的 "621.14"
                              ^^^ ^^
                              |   +-- 最後兩位
                              +------ 6xx 分支
```

先確認 OEM 套件的版本（裝置管理員 → 顯卡 → 驅動程式頁籤，或 INF 裡的 `DriverVer`），
再去 NVIDIA 的檔案庫探測同號的 GeForce 版本：

```powershell
$v = '621.14'
$u = "https://us.download.nvidia.com/Windows/$v/$v-desktop-win10-win11-64bit-international-dch-whql.exe"
try { (Invoke-WebRequest $u -Method Head -UseBasicParsing).StatusCode } catch { 'not published' }
```

回傳 `200` 就代表有成對的版本。若沒有，代表該分支只出了奇數版本——請改用
[方案 B](#方案-b--修改-inf進階) 或 [方案 C](#方案-c--更換硬體)。

### 操作步驟

> 全程請在**以系統管理員身分執行**的 PowerShell 中操作。先把兩個安裝包解壓到本機
> （解壓後各約 4 GB）。

```powershell
# 0) 先盤點。記下子系統 ID 與所有已安裝的 NVIDIA 套件。
.\scripts\check-inf-coverage.ps1
.\scripts\diagnose.ps1

# 1) 備份 OEM 驅動包，讓自己永遠有回滾點。
#    資料夾名稱看 diagnose.ps1 的輸出，然後：
robocopy "C:\Windows\System32\DriverStore\FileRepository\nvwuwi.inf_amd64_XXXX" `
         "D:\backup\nvwuwi" /E

# 2) 移除所有殘留的 NVIDIA 顯示套件。
#    對每一個 Original Name 以 nv 開頭、Class Name 為 Display 的
#    "Published Name" 重複執行。
pnputil /delete-driver oem44.inf /uninstall
pnputil /delete-driver oem45.inf /uninstall

# 3) 為遊戲卡安裝 GeForce 套件，直接從解壓後的資料夾安裝。
#    用 pnputil 而不用廠商安裝程式，因為後者常常先把東西全卸了、
#    然後在降版時失敗。
pnputil /add-driver "D:\pkg621.14\Display.Driver\nv_dispi.inf" /install

# 4) 為專業卡安裝 OEM 工作站套件。
pnputil /add-driver "D:\backup\nvwuwi\nvwuwi.inf" /install

# 5) 重新列舉，讓兩張卡重跑驅動選擇。
pnputil /scan-devices
```

然後重開機一次。切換後立刻出現 `CM_PROB_FAILED_POST_START`／錯誤碼 43 的卡，
幾乎都會在這次重開機後恢復，因為核心驅動還停留在上一個工作階段。

### 驗證

```powershell
nvidia-smi -L
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv
Get-PnpDevice -Class Display -PresentOnly | Select-Object FriendlyName,Problem
```

預期輸出：

```
GPU 0: NVIDIA GeForce RTX 4070 Ti SUPER
GPU 1: NVIDIA RTX 4000 Ada Generation

index, name, driver_version, memory.total [MiB]
0, NVIDIA GeForce RTX 4070 Ti SUPER, 621.14, 16376 MiB
1, NVIDIA RTX 4000 Ada Generation, 621.14, 20475 MiB
```

兩個 `Problem` 都必須是 `CM_PROB_NONE`，而且兩張卡的 INF 路徑要是**不同**的套件、
但驅動版本**相同**。

### 本機實測數據

| 測試項目 | RTX 4070 Ti Super | RTX 4000 Ada |
|---|---|---|
| FP16 矩陣乘 8192³ | 87.8 TFLOPS | 68.6 TFLOPS |
| TF32 矩陣乘 4096³ | 46.4 TFLOPS | 38.3 TFLOPS |
| 顯存頻寬（copy） | 604 GB/s | 312 GB/s |
| 訓練，小型 MLP | 約 1080 step/s | 約 1480 step/s |
| 並行 FP16 矩陣乘 | 92.5 TFLOPS | 74.1 TFLOPS |
| **兩卡同時跑的合計** | **166.6 TFLOPS** | |
| 跨卡複製 512 MiB | 6.22 GB/s（無 P2P） | |

執行 `scripts/verify/gpu_test.py` 與 `gpu_test2.py` 即可重現。

---

## 日常維護——不看這段它會再壞一次

這套配置建立在**兩個套件之間的版本鎖**上。任何只更新單邊的行為都會弄壞專業卡。

1. **不要用 NVIDIA App 自動更新。** 它只認得 GeForce 產品線。
2. **阻止 Windows Update 自動安裝驅動：**
   - 設定 → 系統 → 關於 → 進階系統設定 → 硬體 →
     裝置安裝設定 → **否**
   - 或群組原則：`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` →
     `ExcludeWUDriversInQualityUpdate = 1`
3. 真的要更新時：先找新的 OEM 工作站驅動，再找同號的 GeForce 版本，
   然後在**同一個工作階段**內把兩個都裝上。
4. 保留 OEM 套件備份（方案 A 第 1 步）。那是唯一快速的回滾手段。

---

## 方案 B — 修改 INF（進階）

只有在找不到成對版本時才用。

思路：拿 GeForce 的 INF，補上你的 OEM 子系統 ID，再裝給專業卡。
`scripts/update-nvidia.ps1` 會自動完成修補。

**實際會發生什麼：** 套件裝得進去，但因為 INF 已不再符合 NVIDIA 的簽名目錄，
Windows 會在**驅動排序階段直接把它排除**。那張卡會一直停在
「Microsoft Basic Display Adapter」。想在裝置管理員裡用「從磁片安裝」硬上，
必須開機時按 F7 停用驅動程式簽章強制，而且很脆弱——之後任何一次
Windows Update 或驅動重新整理都會悄悄把它還原。

```powershell
# 只修補副本（安全，不改動系統）
.\scripts\update-nvidia.ps1 -SubSys 181B103C -PatchOnly

# 嘗試安裝（必須在按 F7「停用驅動程式簽章強制」的那次工作階段中）
.\scripts\update-nvidia.ps1 -SubSys 181B103C
```

本機結論：**沒有成功**——那張卡始終綁不上。寫在這裡是為了讓你不用再花一個週末。
如果你的機器上可行，請注意之後每次驅動更新都要重做一次。

---

## 方案 C — 更換硬體

如果你的專業卡是 OEM 變體，又找不到成對的驅動版本：

- **換成非 OEM 版本。** NVIDIA 的 GeForce INF 確實有列 Dell（`181B1028`）與
  NVIDIA 公版（`181B10DE`）這兩種變體，那些卡可以不需要任何手腳就綁上 GeForce 驅動。
- **或一台機器一張卡**，另一張透過網路使用（例如當成小型渲染節點）。
- **或接受只留一張**：GeForce 打遊戲，專業卡插著但不用。

---

## 疑難排解

| 現象 | 原因 | 處理 |
|---|---|---|
| 工作管理員只看到一個 NVIDIA GPU | 卡片綁在 `display.inf` 上 | 跑 `check-inf-coverage.ps1`，你的 INF 沒列這張卡 |
| 錯誤碼 31（`CM_PROB_FAILED_ADD`） | 兩個不同版本的套件 | 把兩邊對齊到同一版本 |
| 切換驅動後立刻錯誤碼 43 | 核心驅動仍駐留 | 重開機 |
| 重開機後仍是錯誤碼 43 | 兩個套件的二進位不同 | 無解；改用方案 B／C |
| `nvidia-smi` 不見了 | 安裝程式卸了舊驅動卻沒裝成功 | 用 `pnputil` 重裝一個套件 |
| 遊戲跑在錯的 GPU 上 | 螢幕接在另一張卡 | 把螢幕接到遊戲卡；或 設定 → 顯示 → 圖形 → 逐應用程式指定 GPU |
| 4K 電視只有低解析度／29 Hz | 基本顯示驅動，或 HDMI 1.4 線材 | 修好驅動；換 HDMI 2.1 線 |
| 專業卡只有 1× PCIe 寬度 | 它插在晶片組 x4 槽 | 正常現象，對運算無影響 |
| 專業卡失去 Mosaic／Sync／ISV 認證 | 它現在跑的是 GeForce 類驅動 | 同機共存時無法避免 |

---

## 硬體注意事項

- **插槽：** 遊戲卡插 CPU 直連的 x16 槽。專業卡插晶片組的 x4 槽沒問題
  （實測：運算效能完整，主機複製約 6 GB/s）。**不要**把遊戲卡插到晶片組後面。
- **電源：** 兩張卡的 TGP 相加，再加約 150 W 給其他零件。本機 285 W + 130 W
  ⇒ 電源至少 850 W，1000 W 更從容。
- **風道：** 渦輪式工作站卡把熱風排出機箱外，和開放式散熱的遊戲卡搭配很好；
  但仍建議兩卡之間留一格空隙。
- **BIOS：** 開啟 Above 4G Decoding 與 Resizable BAR，並把遊戲卡設為主要顯示裝置。
- **ECC：** 工作站卡預設關閉 ECC。`nvidia-smi -e 1` 可開啟，代價是約 1 GB 顯存
  與部分頻寬。
- **Ada 的消費級／工作站卡都沒有 NVLink**——沒有 P2P、不能合併顯存。模型必須放得進
  單卡，除非你自己實作模型平行。

---

## 倉庫結構

```
.
├── README.md                      英文版
├── README_ZH.md                   本文件（中文版）
├── docs/
│   ├── EVIDENCE.md                實機診斷證據
│   └── DRIVER-VERSION-MAP.md      如何解讀 NVIDIA／Windows 版本號
└── scripts/
    ├── diagnose.ps1               收集完整的顯示／驅動狀態
    ├── check-inf-coverage.ps1     已安裝的 INF 到底有沒有列你的卡？
    ├── rebind-device.ps1          強制重新列舉裝置
    ├── update-nvidia.ps1          方案 B：把 OEM 子系統 ID 補進 INF
    └── verify/
        ├── gpu_test.py            Tensor Core、頻寬、正確性、並行
        ├── gpu_test2.py           關閉 TF32 的正確性檢查 + 真實訓練
        └── mem_check.py           大顯存分配的完整性
```

---

## 附錄 — 當初是怎麼診斷出來的

1. `nvidia-smi -L` 只看到一張卡；裝置管理員把另一張顯示為錯誤碼 31。
2. `Get-PnpDevice` 加 `DEVPKEY_Device_DriverInfPath` 顯示兩張卡綁在
   **兩個不同版本的不同套件**上。
3. `nvlddmkm.sys` 的版本只和其中一個相符。
4. 把官方 GeForce 安裝包裡全部 INF 解出來、grep `DEV_27B2`，證明 HP 的子系統 ID 不在裡面。
5. 改安裝一個版本號與 HP 套件相同的 GeForce 套件後，兩張卡就一起跑在同一份核心二進位上了。

實際的指令輸出請看 `docs/EVIDENCE.md`。

整個項目由`Deepseek V4.1 Flash 1017`透過`Deepseek Harness`自行探索並執行相關指令。