import torch

for i in range(torch.cuda.device_count()):
    free, total = torch.cuda.mem_get_info(i)
    n = int(free * 0.8) // 4
    buf = torch.empty(n, dtype=torch.float32, device=f"cuda:{i}")
    buf.fill_(1.0)
    s32 = buf.sum().item()
    # 分塊用 float64 累加，避免一次性配置 2 倍顯存
    acc = 0.0
    chunk = 50_000_000
    for start in range(0, n, chunk):
        acc += buf[start:start + chunk].sum(dtype=torch.float64).item()
    print(f"cuda:{i}  elements={n:,}  fp32sum={s32:.1f}  fp64sum={acc:.1f}  diff={abs(acc - n):.1f}")
    del buf
    torch.cuda.empty_cache()
print("OK")
