import time, sys
import torch

def hr(t):
    print("\n" + "=" * 60)
    print(t)
    print("=" * 60)

hr("環境")
print("torch      :", torch.__version__)
print("CUDA build :", torch.version.cuda)
print("available  :", torch.cuda.is_available())
print("device_cnt :", torch.cuda.device_count())

hr("裝置資訊")
props = []
for i in range(torch.cuda.device_count()):
    p = torch.cuda.get_device_properties(i)
    props.append(p)
    free, total = torch.cuda.mem_get_info(i)
    print(f"[cuda:{i}] {p.name}")
    print(f"    CC {p.major}.{p.minor}  SMs {p.multi_processor_count}  "
          f"VRAM {total/2**30:.1f} GiB (free {free/2**30:.1f})")

def bench_matmul(dev, dtype, n, iters=15):
    a = torch.randn(n, n, device=dev, dtype=dtype)
    b = torch.randn(n, n, device=dev, dtype=dtype)
    for _ in range(5):
        c = a @ b
    torch.cuda.synchronize(dev)
    t0 = time.perf_counter()
    for _ in range(iters):
        c = a @ b
    torch.cuda.synchronize(dev)
    dt = (time.perf_counter() - t0) / iters
    return dt, 2 * n**3 / dt / 1e12

def bench_bw(dev, mib=1024, iters=10):
    n = mib * 1024 * 1024 // 4
    x = torch.empty(n, dtype=torch.float32, device=dev)
    y = torch.empty_like(x)
    for _ in range(3):
        y.copy_(x)
    torch.cuda.synchronize(dev)
    t0 = time.perf_counter()
    for _ in range(iters):
        y.copy_(x)
    torch.cuda.synchronize(dev)
    dt = (time.perf_counter() - t0) / iters
    return 2 * n * 4 / dt / 1e9

hr("矩陣乘法 (FP16 / Tensor Core)")
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    dt, tf = bench_matmul(dev, torch.float16, 8192)
    print(f"cuda:{i}  8192^3 fp16 : {dt*1000:8.1f} ms   {tf:8.1f} TFLOPS")

hr("矩陣乘法 (FP32 / TF32)")
torch.backends.cuda.matmul.allow_tf32 = True
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    dt, tf = bench_matmul(dev, torch.float32, 4096)
    print(f"cuda:{i}  4096^3 fp32 : {dt*1000:8.1f} ms   {tf:8.1f} TFLOPS")

hr("顯存頻寬 (D2D copy)")
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    gb = bench_bw(dev)
    print(f"cuda:{i}  1 GiB copy   : {gb:8.1f} GB/s")

hr("數值正確性 (與 CPU 對照)")
torch.manual_seed(0)
a_cpu = torch.randn(256, 256)
b_cpu = torch.randn(256, 256)
ref = a_cpu @ b_cpu
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    out = (a_cpu.to(dev) @ b_cpu.to(dev)).cpu()
    err = (out - ref).abs().max().item()
    ok = torch.allclose(out, ref, atol=1e-4, rtol=1e-4)
    print(f"cuda:{i}  max_abs_err={err:.2e}  allclose={ok}")

hr("跨卡傳輸 (PCIe P2P / 經主機記憶體)")
if torch.cuda.device_count() >= 2:
    n = 512 * 1024 * 1024 // 4  # 512 MiB
    src = torch.empty(n, dtype=torch.float32, device="cuda:0").fill_(1.0)
    torch.cuda.synchronize()
    dst = src.to("cuda:1")
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    for _ in range(5):
        dst = src.to("cuda:1")
    torch.cuda.synchronize()
    dt = (time.perf_counter() - t0) / 5
    print(f"cuda:0 -> cuda:1  512 MiB : {dt*1000:7.1f} ms   {n*4/dt/1e9:6.2f} GB/s")
    print(f"內容正確: {bool((dst == 1.0).all().item())}")
    p2p = torch.cuda.can_device_access_peer(0, 1)
    print(f"can_device_access_peer(0,1): {p2p}")

hr("兩卡同時並行 (各自跑獨立負載)")
if torch.cuda.device_count() >= 2:
    def work(dev, n=4096, iters=30):
        a = torch.randn(n, n, device=dev, dtype=torch.float16)
        b = torch.randn(n, n, device=dev, dtype=torch.float16)
        for _ in range(3):
            a @ b
        torch.cuda.synchronize(dev)
        t0 = time.perf_counter()
        for _ in range(iters):
            a @ b
        torch.cuda.synchronize(dev)
        return (time.perf_counter() - t0) / iters

    import threading
    res = {}
    def run(i):
        res[i] = work(f"cuda:{i}")

    t0 = time.perf_counter()
    th = [threading.Thread(target=run, args=(i,)) for i in range(2)]
    [t.start() for t in th]
    [t.join() for t in th]
    wall = time.perf_counter() - t0
    for i in sorted(res):
        tf = 2 * 4096**3 / res[i] / 1e12
        print(f"cuda:{i} 並行 4096^3 fp16 : {res[i]*1000:7.1f} ms  {tf:6.1f} TFLOPS")
    print(f"總牆鐘時間 {wall:.2f}s")
    total = sum(2 * 4096**3 / res[i] / 1e12 for i in res)
    single = 2 * 4096**3 / work("cuda:0") / 1e12
    print(f"合計吞吐 {total:.1f} TFLOPS (單卡 cuda:0 約 {single:.1f})")

print("\nDONE")
