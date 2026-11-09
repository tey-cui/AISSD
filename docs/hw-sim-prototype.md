# AISSD 硬件仿真原型（Hardware Simulation Prototype）

> 关联：[`prototype-design.md`](./prototype-design.md) · Project bootstrap  
> 目标：第一个**可用的硬件仿真系统** — 用 Verilator/Icarus 跑通 clean-room RTL 控制路径。  
> **不是** Cosmos+ GPL RTL 移植；**不是** FPGA bitstream / ASIC 签核模型。

---

## 1. 目标与成功标准

| # | 标准 | 验收 |
|---|------|------|
| 1 | 可克隆即跑（有工具链时） | `make hw-sim` → `hw_sim: PASS` |
| 2 | 行为孪生仍在 | `make smoke` / `make proto` 继续绿 |
| 3 | 自检而非只编译 | TB 校验完成计数、读回数据、FDP region、GC suspend/resume |
| 4 | 波形可抓 | 生成 `build/hw_sim/aissd_hw_sim.vcd` |
| 5 | 场景覆盖 | KV 类 `TC_LAT_READ` + checkpoint 写（RUH2→region2）混合 |

---

## 2. 框图

```
┌─────────────────────────────────────────────────────────────┐
│ tb_aissd_hw_sim (Host BFM + scoreboard + VCD)               │
│   issue_cmd / cpl monitor / PASS-FAIL                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ valid/ready cmd + cpl
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ aissd_ctrl_top                                              │
│  host_cmd_queue → decode                                    │
│       │                                                     │
│       ├─(LAT_READ)→ ftl_l2p.gc_suspend                      │
│       ├─ READ → L2P lookup → nand_timing_model              │
│       └─ WRITE→ qos_fdp_place (RUH→region→PBA) → NAND       │
│                 → L2P update → completion                   │
└─────────────────────────────────────────────────────────────┘
```

### 模块

| 模块 | 路径 | 作用 |
|------|------|------|
| `host_cmd_queue` | `rtl/host_cmd_queue.sv` | 主机提交队列 FIFO |
| `qos_fdp_place` | `rtl/qos_fdp_place.sv` | RUH1→reg1@64、RUH2→reg2@128 bump 分配 |
| `ftl_l2p` | `rtl/ftl_l2p.sv` | 页级 L2P + GC suspend 计数 |
| `nand_timing_model` | `rtl/nand_timing_model.sv` | 周期近似读写忙等待（非 ONFI PHY） |
| `aissd_ctrl_top` | `rtl/aissd_ctrl_top.sv` | 串联数据/控制路径 |
| TB | `tb/tb_aissd_hw_sim.sv` | 混合负载 + 自检 + VCD |

与 C 行为原型（`make proto`）对照：同一概念切片（io_desc / FDP / L2P / GC / NAND 统计），本路径是 **RTL + 周期近似**。

---

## 3. 依赖安装

### Debian / Ubuntu（本云 VM 已验证）

```bash
sudo apt-get update
sudo apt-get install -y verilator iverilog
verilator --version   # 已测：5.020
iverilog -V | head -1 # 已测：12.0
```

### macOS

```bash
brew install verilator icarus-verilog
```

脚本优先 **Verilator**（`--binary --timing`）；若无则回退 **Icarus**。可用环境变量强制：

```bash
AISSD_HW_SIM_ENGINE=verilator make hw-sim
AISSD_HW_SIM_ENGINE=icarus make hw-sim
```

---

## 4. 如何运行

```bash
make smoke      # C 冒烟
make proto      # C 行为原型演示
make hw-sim     # 硬件仿真（等价 make sim-hw）
```

或直接：

```bash
./scripts/run_hw_sim.sh
```

期望末尾：

```text
hw_sim: PASS
```

波形：`build/hw_sim/aissd_hw_sim.vcd`（可用 GTKWave 打开）。

---

## 5. TB 证明了什么

1. **提交→完成闭环**：seed 写 + KV 读 + checkpoint 写全部完成且无错误状态。  
2. **读数据一致性**：对已写入 LBA 的读回匹配。  
3. **FDP 放置**：checkpoint（RUH=2）完成包上报 `region==2`。  
4. **读优先 GC 钩子**：`TC_LAT_READ` 后 `gc_may_run==0`；`gc_resume` 后恢复。  
5. **NAND 忙时序**：`nand_busy_cycles` / read/write 计数非零（周期模型在跑）。

---

## 6. 范围外

- 真实 NVMe/PCIe、Admin、PRP/SGL、MSI-X  
- Cosmos+ / DaisyPlus RTL 或 GPL 固件  
- 可综合到具体 FPGA 工程的约束/时钟树  
- LDPC、多 channel ONFI PHY、掉电 journal  

下一步可把 C `io_desc` 字段与 RTL 打包格式钉成正式 SIRD，或加 cocotb/DPI 复用 `host_traffic` 刺激。

---

## English summary

First **usable hardware-sim prototype**: clean-room SystemVerilog controller path (host SQ → FDP → L2P → timed NAND → CQ) with a self-checking TB and VCD. Run `make hw-sim` after installing Verilator (preferred) or Icarus. Behavioral twin remains `make proto`.
