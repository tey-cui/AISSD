# AISSD

AI 导向 SSD 控制器 **Gen-1 仿真原型**（行为仿真 + 硬件仿真）。  
Clean-room adaptation for an AI-oriented SSD controller — **not** a fork of Cosmos+ OpenSSD.

## 中文摘要

- **本仓**：自有 Apache-2.0 代码 — C 行为孪生（`io_desc` / FDP / FTL / `nand_model`）+ **SystemVerilog 硬件仿真路径**（Verilator/Icarus）。
- **Cosmos+ OpenSSD**：外部 **GPL-3.0 学习基线**（钉扎提交见 `UPSTREAM_PIN.txt`）。默认 **不**把完整 GPL 树 vendor 进产品路径。
- **不做**：不声称 FPGA bitstream、不把 GPL RTL/固件当作专有代码、不把 LMCache/SGLang 当作控制器。

```bash
make smoke    # C 冒烟: smoke_io_desc: PASS
make proto    # C 原型演示 + 短报告
make hw-sim   # 硬件仿真（亦可用 make sim-hw）→ hw_sim: PASS
```

### 硬件仿真依赖

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y verilator iverilog

# macOS
brew install verilator icarus-verilog
```

详见 [`docs/hw-sim-prototype.md`](docs/hw-sim-prototype.md)。波形：`build/hw_sim/aissd_hw_sim.vcd`。

| 路径 | 说明 |
|------|------|
| `include/` · `src/stubs/` · `src/proto/` | C 行为孪生 |
| `rtl/` | Clean-room SV：队列 / FDP / L2P / NAND 时序模型 / top |
| `tb/tb_aissd_hw_sim.sv` | 自检 TB + VCD |
| `scripts/run_hw_sim.sh` | Verilator→Icarus 启动脚本 |
| `tests/` | C smoke / proto demo |
| `docs/prototype-design.md` | C 原型架构 |
| `docs/hw-sim-prototype.md` | **硬件仿真**架构与 runbook |
| `third_party/cosmos-plus-openssd/` | 上游克隆说明（不 vendor 全树） |

## English brief

AISSD provides a **behavioral C twin** (`make proto`) and a **hardware-sim path** (`make hw-sim`) over clean-room SystemVerilog: host SQ → FDP placement → L2P/GC hooks → cycle-approx NAND → completions, with a self-checking TB and VCD. Cosmos+ remains an external GPL study baseline only.

```text
C:   AI traffic → proto_ctrl → io_desc → qos/FTL → nand_model
HW:  Host BFM  → aissd_ctrl_top (SV) → timed NAND model → CQ + VCD
```

License: Apache-2.0 for first-party code — see `LICENSE` and `NOTICE`.
