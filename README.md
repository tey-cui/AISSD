# AISSD

AI 导向 SSD 控制器 **Gen-1 原型脚手架**（仿真优先 / sim-first）。  
Clean-room adaptation skeleton for an AI-oriented SSD controller — **not** a fork of Cosmos+ OpenSSD.

## 中文摘要

- **本仓**：自有 Apache-2.0 代码 — 内部 `io_desc`、FTL 钩子、QoS/FDP 占位、固定延迟 `nand_model`、主机侧冒烟测试。
- **Cosmos+ OpenSSD**：外部 **GPL-3.0 学习基线**（钉扎提交见 `UPSTREAM_PIN.txt`）。默认 **不**把完整 GPL 树 vendor 进产品路径；克隆说明在 `third_party/cosmos-plus-openssd/`。
- **不做**：不声称 FPGA bitstream、不把 GPL RTL/固件当作专有代码、不把 LMCache/SGLang 当作控制器。

```bash
make smoke
# 期望输出: smoke_io_desc: PASS
```

| 路径 | 说明 |
|------|------|
| `include/` | 公共头文件契约 |
| `src/stubs/` | 仿真/空实现 |
| `tests/smoke_io_desc.c` | 写→读回冒烟 |
| `docs/INTEGRATION.md` | 集成计划 |
| `docs/workload-notes.md` | LMCache / SGLang 负载参考 |
| `third_party/cosmos-plus-openssd/` | 上游克隆与许可声明 |

## English brief

AISSD hosts a **host-side C simulation path**: FE descriptor → FTL stubs → NAND model.  
Cosmos+ is documented as a **pinned external study baseline** under `third_party/` (GPL; no silent relicensing). Optional AI workload drivers for later profiling are noted in `docs/workload-notes.md`.

```text
Host harness  →  io_desc  →  FTL stubs (L2P/GC hooks)  →  nand_model
                     ↑
              qos_fdp (WRR / RUH stubs)
```

License: Apache-2.0 for first-party code — see `LICENSE` and `NOTICE`.
