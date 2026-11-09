# AISSD FPGA 可烧录路径评估与脚手架

> 关联：[`hw-sim-prototype.md`](./hw-sim-prototype.md) · Project 文档 `fpga-burnable-path.md` · **分期上板与购板清单**：Project `fpga-prototype-next-steps.md`（Cursor Project「SSD」文档区；含可买 SKU）  
> 诚实前提：**本云环境无 Vivado/Quartus 许可证、无物理 FPGA 板** → **不能**在此产出真实 bitstream。  
> 本 PR 交付：可综合外壳 + 约束模板 + 本地 TCL/yosys 检查，为日后上板做准备。

---

## 1. 当前 SV 哪些能上 FPGA / 哪些不能

| 资产 | 今日状态 | 说明 |
|------|----------|------|
| `rtl/host_cmd_queue.sv` | **可综合倾向** | 小 FIFO；推断寄存器 |
| `rtl/qos_fdp_place.sv` | **可综合倾向** | 组合/时序逻辑，无 TB 结构 |
| `rtl/ftl_l2p.sv` | **可综合倾向** | 小 L2P 阵列 → 推断分布式 RAM/BRAM |
| `rtl/nand_timing_model.sv` | **可综合作「片上媒体模型」** | **不是**真实 NAND PHY；上板仅作功能闭环 |
| `rtl/aissd_ctrl_top.sv` | **可综合倾向** | 控制路径 FSM；无 `$display`/`#delay` |
| `tb/tb_aissd_hw_sim.sv` | **仅仿真** | Host BFM、`$dumpfile`、`$finish` |
| `rtl/fpga/*`（本 PR） | **面向综合的外壳** | 复位同步、AXI-Lite MMIO、板级 TG 开关、LED、UART stub；`aissd_fpga_board` 可作无软核烧录练习 top |
| PCIe / NVMe Host IP | **未包含** | Gen-1 **不**从真实 NVMe 起步 |
| Cosmos+ NFC / GreedyFTL | **禁止拷入** | GPL；仅学习对照 |

**结论**：控制切片 + **片上 NAND 时序模型** 可走「软主机 MMIO 打流」上板演示；**真实闪存通道 / PCIe NVMe** 仍属后续阶段。

---

## 2. 目标板卡选项与约束

| 选项 | 适用 | 诚实约束 |
|------|------|----------|
| **Digilent Arty A7-100T**（XC7A100T；**A7-35T 已停产**） | **推荐 Gen-1 购板与烧录练习** | 与 `constraints/arty_a7_100t.xdc` 对齐；无板载 OpenSSD NAND；AXI-Lite / 片上 TG |
| **Nexys Video**（XC7A200T）等更大 Artix | 逻辑/BRAM 余量 | 仍无真 NAND；适合 Stage B 复杂外壳 |
| **Kintex Ultrascale 评估**（KCU105 等） | PCIe 互连练习 | 成本高；无 OpenSSD NAND 子卡 |
| **Cosmos+ OpenSSD 兼容板** | 日后真实 NAND/NVMe | 需板卡+Vivado；固件/对照 GPL 隔离；**不**把上游 RTL 拷进 AISSD |
| **DaisyPlus / CRZ** | 现代 OpenSSD 平台 | 价高；许可需邮件澄清后再作主路径 |

完整购板表、实验室清单与决策树见 Project 文档 **`fpga-prototype-next-steps.md`**。

**云端**：无许可证、无板 → 只跑 `make hw-sim` / `make fpga-lint`（yosys/verilator）；bitstream 留给用户本地 Vivado。

---

## 3. 时钟 / 复位 / BRAM / 主机接口（Gen-1 建议）

### 3.1 分阶段主机策略（推荐）

```
Stage A（本 PR）: AXI-Lite MMIO doorbell + 片上 BRAM/数组缓冲
                  Soft CPU / JTAG / VIP 写寄存器 → aissd_ctrl_top
Stage B:          片上流量发生器（KV/ckpt 图案）一键演示
Stage C:          外购/自研 PCIe EP + NVMe 前端（真实主机）
Stage D:          真实 NAND 通道替换 nand_timing_model
```

**不要**在 Gen-1 同时深做 PCIe Gen5 + 全 NVMe + 真闪存。

### 3.2 时钟与复位

- 单时钟域假设：板载 100 MHz（Arty）或用户 PLL 输出 → `clk`。  
- 异步复位按键 → `sync_reset` 同步释放到 `rst_n`。  
- 跨时钟（若日后加 UART 高速/PCIe）另开 CDC；本壳单时钟。

### 3.3 存储映射（概念）

| 区域 | 用途 |
|------|------|
| AXI-Lite 寄存器 | SQ 门铃字段、CQ 弹出、状态/统计、GC resume |
| 推断 RAM（L2P/NAND 模型） | 页级映射与「假媒体」数据 |
| （可选）Block RAM IP | 放大页容量时再显式例化 |

### 3.4 LED / UART

- LED：心跳、busy、cpl pending、gc suspended。  
- UART：可选 stub（TX 拉高空闲）；正式日志后续接。

---

## 4. 仓库落点

```
rtl/          # 核心控制路径（仿真与综合共用，无 TB 结构）
rtl/fpga/     # 板级外壳：sync_reset、axi_lite_mmio、aissd_fpga_top
tb/           # 仅仿真
constraints/  # 示例 XDC（Arty A7 类 + 通用 Artix 模板）
scripts/vivado_synth.tcl
scripts/yosys_fpga_lint.ys
scripts/run_fpga_lint.sh
```

---

## 5. 本地如何跑

```bash
make hw-sim      # 行为/周期仿真（须绿）
make fpga-lint   # yosys 综合检查（若已装）+ verilator lint-only
make fpga-vivado # 有 Vivado 时本地综合/实现 stub；无则优雅失败
```

依赖示例：

```bash
sudo apt-get install -y yosys verilator   # lint
# Vivado：用户本机安装；云端通常不可用
```

---

## 6. 明确不声称

- **未**在本环境生成 `.bit` / `.sof`。  
- **未**上板点亮。  
- `nand_timing_model` 上板 ≠ 真实闪存。  
- 不含 Cosmos+ GPL RTL。

---

## English summary

Current controller SV is **synth-oriented**; the TB is sim-only. This PR adds an **AXI-Lite MMIO FPGA shell**, XDC templates, and Vivado/yosys scripts. Prefer **Arty A7-100T** (35T retired) for Stage-A bring-up; Cosmos+/DaisyPlus later for real NAND/NVMe. **No bitstream** is produced in-cloud without Vivado/board. Purchase / lab next steps live in Project doc `fpga-prototype-next-steps.md`.
