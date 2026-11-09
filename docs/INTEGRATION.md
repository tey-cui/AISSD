# AISSD 集成计划 / Integration plan

中文优先说明 Gen-1 适配树如何对接 Cosmos+ **学习基线**；英文摘要附后。

## 目标

在 **无 FPGA** 前提下，用主机侧 C 仿真走通：

`Host harness → io_desc → FTL stubs → nand_model`

为后续 hello-NVMe（仿真或上板）保留同一内部契约。

## 仓库布局

```
AISSD/
  include/           # io_desc, ftl_hooks, qos_fdp, nand_model
  src/stubs/         # 自有空实现 / 仿真实现
  tests/             # smoke_io_desc
  docs/              # 集成与工作负载笔记
  third_party/cosmos-plus-openssd/  # 仅克隆说明 + 许可声明（不默认 vendor 全树）
  Makefile           # make smoke
```

## Keep / Replace / Add（相对 Cosmos+）

| 子系统 | 动作 | AISSD 落点 |
|--------|------|------------|
| NVMe 队列 / DMA | Study → 自研 FE | 文档对照；本仓暂无 RTL |
| `io_desc` | **Add** | `include/io_desc.h` |
| L2P / GC 钩子 | Study + Replace hooks | `include/ftl_hooks.h`, `src/stubs/ftl_hooks.c` |
| QoS / FDP | **Add stubs** | `include/qos_fdp.h` |
| NAND | Study + **nand_model** | `include/nand_model.h` |

## 工作包映射

- **WP-1** FE 契约：`io_desc` 字段草案（本仓已冻结初版）。
- **WP-2** FTL：`submit` / `poll_complete` / `gc_*` / identity L2P。
- **WP-3** QoS/FDP：WRR 权重 + RUH→region 表可解析。
- **WP-4** NAND 模型：固定延迟；写页→读回（`make smoke`）。

## 许可隔离

- 本仓一等公民代码：**Apache-2.0**（见根 `LICENSE` / `NOTICE`）。
- Cosmos+：**GPL-3.0 外部基线**；见 `third_party/cosmos-plus-openssd/`。
- **禁止**把上游 RTL/固件静默拷入 `src/` 并当作专有代码。

## 验收（当前）

```bash
make smoke
# → smoke_io_desc: PASS
make proto
# → short report + proto_demo: PASS
```

原型架构、范围与数据路径见 [`docs/prototype-design.md`](./prototype-design.md)。

不声称 Vivado 综合或真实 NVMe 枚举。

---

## English summary

AISSD Gen-1 is a **sim-first clean-room skeleton**: shared `io_desc`, FTL hooks,
QoS/FDP stubs, and a fixed-latency NAND model. Cosmos+ OpenSSD remains an
**external GPL study baseline** (pinned commit documented under `third_party/`);
it is not vendored into product paths. Run `make smoke` for the host-side path.
