# AISSD

AI 导向 SSD 控制器 **Gen-1 仿真 / FPGA 外壳**（行为仿真 + 硬件仿真 + 可综合脚手架）。  
Clean-room adaptation — **not** a fork of Cosmos+ OpenSSD.

## 中文摘要

- **本仓**：自有 Apache-2.0 — C 行为孪生 + SystemVerilog HW-sim + **FPGA MMIO 外壳**（AXI-Lite / 板级 TG）。
- **Cosmos+**：外部 GPL 学习基线；**不** vendor 进产品路径。
- **诚实边界**：云端无 Vivado/板卡时 **不**声称已生成 bitstream。

```bash
make smoke       # C 冒烟
make proto       # C 原型演示
make hw-sim      # Verilator/Icarus 硬件仿真 → hw_sim: PASS
make fpga-lint   # Verilator lint-only（+ 可选 Yosys）→ fpga_lint: PASS
make fpga-vivado # 有 Vivado 才跑；否则优雅退出码 2
```

### 依赖

```bash
sudo apt-get update
sudo apt-get install -y verilator iverilog yosys   # sim + lint
# Vivado：仅用户本机；见 docs/fpga-portability.md
```

| 路径 | 说明 |
|------|------|
| `rtl/` | 控制路径 SV（仿真与综合共用） |
| `rtl/fpga/` | 复位同步、AXI-Lite、板级 top / board |
| `tb/` | **仅仿真** |
| `constraints/` | Arty A7 示例 XDC + 通用模板 |
| `docs/fpga-portability.md` | **FPGA 可烧录评估与分期策略** |
| `docs/hw-sim-prototype.md` | 硬件仿真 runbook |

## English brief

Behavioral twin (`make proto`), cycle HW-sim (`make hw-sim`), and an **FPGA Stage-A/B shell** (`rtl/fpga`, `make fpga-lint`). Prefer Artix-7 (Arty A7) with AXI-Lite or on-chip TG before real PCIe/NAND. No bitstream is claimed without a successful local Vivado run.

License: Apache-2.0 — see `LICENSE` / `NOTICE`.
