# AISSD

AI 导向 SSD 控制器 **Gen-1 仿真原型**（仿真优先 / sim-first）。  
Clean-room adaptation for an AI-oriented SSD controller — **not** a fork of Cosmos+ OpenSSD.

## 中文摘要

- **本仓**：自有 Apache-2.0 代码 — `io_desc`、多队列原型控制器、AI 形态流量生成、FDP RUH 放置、FTL L2P/GC 挂起、带统计的 `nand_model`。
- **Cosmos+ OpenSSD**：外部 **GPL-3.0 学习基线**（钉扎提交见 `UPSTREAM_PIN.txt`）。默认 **不**把完整 GPL 树 vendor 进产品路径；克隆说明在 `third_party/cosmos-plus-openssd/`。
- **不做**：不声称 FPGA bitstream、不把 GPL RTL/固件当作专有代码、不把 LMCache/SGLang 当作控制器。

```bash
make smoke   # 期望: smoke_io_desc: PASS
make proto   # 期望: 短报告 + proto_demo: PASS
```

| 路径 | 说明 |
|------|------|
| `include/` | 公共头文件契约 |
| `src/stubs/` | FTL / QoS / NAND 仿真实现 |
| `src/proto/` | 多队列控制器 + AI 流量生成 |
| `tests/smoke_io_desc.c` | 写→读回冒烟 |
| `tests/proto_demo.c` | 端到端原型演示 |
| `docs/prototype-design.md` | **原型架构说明**（框图 / 范围 / 成功标准） |
| `docs/INTEGRATION.md` | 集成计划 |
| `docs/workload-notes.md` | LMCache / SGLang 负载参考 |
| `third_party/cosmos-plus-openssd/` | 上游克隆与许可声明 |

## English brief

AISSD hosts a **host-side C simulation path**: AI traffic → multi-queue → `io_desc` → FDP/QoS → FTL → `nand_model` (with IOPS/p99).  
Cosmos+ is a **pinned external study baseline** under `third_party/` (GPL; no silent relicensing). See `docs/prototype-design.md`.

```text
AI traffic gens → proto_ctrl (multi-SQ) → io_desc
                      ↓
              qos_fdp (RUH→region) → FTL (L2P/GC) → nand_model
```

License: Apache-2.0 for first-party code — see `LICENSE` and `NOTICE`.
