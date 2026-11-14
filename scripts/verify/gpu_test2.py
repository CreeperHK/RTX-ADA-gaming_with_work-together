import time
import torch

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False

print("=" * 60)
print("數值正確性（關閉 TF32，與 float64 CPU 對照）")
print("=" * 60)
torch.manual_seed(0)
a = torch.randn(512, 512, dtype=torch.float64)
b = torch.randn(512, 512, dtype=torch.float64)
ref = (a @ b).float()
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    out = (a.float().to(dev) @ b.float().to(dev)).cpu()
    err = (out - ref).abs().max().item()
    rel = err / ref.abs().max().item()
    print(f"cuda:{i}  max_abs_err={err:.3e}  rel={rel:.3e}  allclose={torch.allclose(out, ref, atol=1e-3, rtol=1e-3)}")

print()
print("=" * 60)
print("真實訓練：小型 MLP（784-512-256-10），各卡跑 300 步")
print("=" * 60)

def train(dev, steps=300):
    torch.manual_seed(42)
    model = torch.nn.Sequential(
        torch.nn.Linear(784, 512), torch.nn.ReLU(),
        torch.nn.Linear(512, 256), torch.nn.ReLU(),
        torch.nn.Linear(256, 10),
    ).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    lossf = torch.nn.CrossEntropyLoss()
    x = torch.randn(256, 784, device=dev)
    y = torch.randint(0, 10, (256,), device=dev)
    losses = []
    t0 = time.perf_counter()
    for _ in range(steps):
        opt.zero_grad()
        loss = lossf(model(x), y)
        loss.backward()
        opt.step()
        losses.append(loss.item())
    torch.cuda.synchronize(dev)
    dt = time.perf_counter() - t0
    return losses[0], losses[-1], dt, steps / dt

for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    l0, l1, dt, sps = train(dev)
    print(f"cuda:{i}  loss {l0:.4f} -> {l1:.4f}   {dt:.2f}s   {sps:.0f} step/s")

print()
print("=" * 60)
print("大顯存分配測試（各自吃滿約 80% 顯存並做運算）")
print("=" * 60)
for i in range(torch.cuda.device_count()):
    dev = f"cuda:{i}"
    free, total = torch.cuda.mem_get_info(i)
    target = int(free * 0.8) // 4
    buf = torch.empty(target, dtype=torch.float32, device=dev)
    buf.fill_(1.0)
    s = buf.sum().item()
    expect = float(target)
    print(f"cuda:{i}  分配 {target*4/2**30:.1f} GiB   sum 正確={abs(s-expect) < 1e-3}")
    del buf
    torch.cuda.empty_cache()

print()
print("=" * 60)
print("兩卡同時訓練（各自獨立模型，並行）")
print("=" * 60)
import threading
res = {}
def run(i):
    res[i] = train(f"cuda:{i}", steps=200)

t0 = time.perf_counter()
ths = [threading.Thread(target=run, args=(i,)) for i in range(2)]
[t.start() for t in ths]
[t.join() for t in ths]
wall = time.perf_counter() - t0
for i in sorted(res):
    l0, l1, dt, sps = res[i]
    print(f"cuda:{i}  loss {l0:.4f} -> {l1:.4f}  {sps:.0f} step/s")
print(f"兩卡並行總牆鐘 {wall:.2f}s")
print("\nDONE")
