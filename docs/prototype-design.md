# AISSD 仿真原型设计（Sim-First Vertical Slice）

> 关联：仓库脚手架 · Project `controller-design-bootstrap.md` · `docs/INTEGRATION.md`  
> 范围：**可运行的主机侧仿真原型**；不声称 FPGA bitstream / ASIC RTL。  
> 许可：本仓一等公民代码 Apache-2.0；**不** vendor Cosmos+ GPL 全树。

---

## 1. 目标与成功标准

### 1.1 本原型要证明什么

用一条干净的软件垂直切片，演示 AI 导向控制路径端到端：

```
Host traffic (AI patterns)
  → multi-queue / multi-NS enqueue
  → io_desc
  → QoS/FDP（RUH → region → PBA）
  → FTL hooks（L2P + GC-suspend-on-LAT_READ）
  → nand_model（延迟/带宽旋钮 + IOPS/p99 统计）
```

### 1.2 成功标准（可检查）

| # | 标准 | 验收 |
|---|------|------|
| 1 | 冒烟不回归 | `make smoke` → `smoke_io_desc: PASS` |
| 2 | 原型可跑 | `make proto` → 打印短报告 + `proto_demo: PASS` |
| 3 | 多队列 / 多 NS | demo 同时提交 Q0/Q1/NS1 读 + Q2/NS2 checkpoint 写 |
| 4 | FDP 放置 | RUH→region 生效；checkpoint 写落在配置的 PBA 区间 |
| 5 | 读优先 GC | `TC_LAT_READ` 提交后 `gc_may_run==0`；统计可见 `gc_suspends` / `gc_blocked_ticks` |
| 6 | 媒体统计 | NAND 模型输出 reads/writes、sim 时间、近似 p99 延迟 |

---

## 2. 框图与数据路径

```
┌──────────────────────────────────────────────────────────────────┐
│ Host harness (tests/proto_demo.c)                                │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────────┐         │
│  │ KV overflow │ │ Embed rand   │ │ Checkpoint seq wr  │         │
│  │ PAT (Q0/NS1)│ │ PAT (Q1/NS1) │ │ PAT (Q2/NS2)       │         │
│  └──────┬──────┘ └──────┬───────┘ └─────────┬──────────┘         │
│         └───────────────┼────────────────────┘                   │
│                         ▼                                        │
│              proto_ctrl (multi SQ) ── WRR pick TC                │
└─────────────────────────┬────────────────────────────────────────┘
                          │ aissd_io_desc
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│ QoS / FDP          ruh → region_id → bump-alloc PBA              │
│ FTL hooks          L2P update/lookup · GC suspend/resume/tick    │
└─────────────────────────┬────────────────────────────────────────┘
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│ nand_model         fixed + per-KiB latency · hist → p99 · IOPS   │
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 组件一览

| 组件 | 路径 | 职责 |
|------|------|------|
| `io_desc` | `include/io_desc.h` | 统一内部描述符：LBA/NSID/RUH/TC/buf |
| `host_traffic` | `src/proto/host_traffic.c` | 三类 AI 形态流量生成（非框架移植） |
| `proto_ctrl` | `src/proto/proto_ctrl.c` | 多队列入队、按 TC WRR 排水、触发 GC tick |
| `qos_fdp` | `src/stubs/qos_fdp.c` | WRR 权重、RUH 表、region 布局与 PBA 分配 |
| `ftl_hooks` | `src/stubs/ftl_hooks.c` | submit/complete、L2P、放置、GC 挂起 |
| `nand_model` | `src/stubs/nand_model.c` | 页读写擦、时序旋钮、统计直方图 |

### 2.2 `io_desc` → 放置 → 媒体

1. Host 生成 `aissd_io_desc_t`（含 `nsid`、`ruh`、`traffic_class`）。  
2. `proto_ctrl` 按队列暂存，排水时优先 WRR 选中的 TC。  
3. `ftl_submit`：若 `TC_LAT_READ` → `gc_suspend_for_lat_read`。  
4. Write：`ruh` → `region_for_ruh` → `alloc_pba` → NAND program → L2P 更新。  
5. Read：L2P lookup → NAND read；可选仍解析 RUH 做遥测计数。  
6. `nand_model` 累加 sim 时间与延迟直方图，供 IOPS / p99 报告。

---

## 3. 范围内 / 范围外

| 在范围内（本原型） | 范围外（FPGA / ASIC / 后续） |
|--------------------|------------------------------|
| 主机侧 C 仿真垂直切片 | PCIe PHY / 可综合 NVMe RTL |
| 合成 AI I/O 形态（KV / embed / ckpt） | 完整 LMCache / SGLang 集成 |
| 多 SQ、多 Namespace 语义占位 | 真实 doorbell / MSI-X / Admin 全集 |
| FDP RUH→region bump 放置 | 完整 RU 回收、WAF 模型、ZNS |
| 简单页级 L2P + GC 挂起钩子 | 生产级 GC/WL/journal/掉电 |
| 固定+带宽旋钮 NAND 延迟模型 | ONFI/Toggle PHY、LDPC、坏块替换策略 |
| `make smoke` / `make proto` | Vivado 工程、上板 hello-NVMe |

**明确不做**：把 Cosmos+ GPL RTL/固件拷进 `src/`；声称本树可流片。

---

## 4. AI 流量形态（host_traffic）

受 LMCache / SGLang **I/O 形状启发**（见 `docs/workload-notes.md`），本仓只实现轻量 C harness，不 vendor 框架：

| Pattern | 语义 | TC | 典型用法 |
|---------|------|----|----------|
| `AISSD_PAT_KV_OVERFLOW` | 顺序大页读 | `TC_LAT_READ` | KV cache 溢出/回灌 |
| `AISSD_PAT_EMBED_RAND` | 伪随机小粒度读 | `TC_LAT_READ` | embedding / ANN 探查 |
| `AISSD_PAT_CKPT_SEQ` | 顺序写 | `TC_BW_WRITE` | checkpoint；配独立 RUH |

Demo 默认：NS1 上双队列读争用 + NS2 checkpoint 写；checkpoint 走 RUH=2 → region 2，与热读区隔离。

---

## 5. 如何运行

```bash
make smoke   # 基础写读回 + QoS 解析 + GC suspend
make proto   # 多队列 AI 场景 + 短报告
make clean && make all
```

期望：`smoke_io_desc: PASS` 与 `proto_demo: PASS`，并打印 sim 时间、IOPS、p99、GC/FDP 计数。

---

## 6. 与脚手架 / 工作包关系

本原型把 bootstrap 中 **WP-1…WP-4** 从「空钩子」推进到「可演示策略行为」，仍属 **路线 A（仿真优先）**。  
下一步（不在本 PR 强制范围）：FEMU/MQSim 对照、真实 trace 回放、有板后 hello-NVMe。

---

## English summary

This document defines the **sim-first vertical slice** in AISSD: AI-shaped host traffic through multi-queue `io_desc`, FDP RUH placement, FTL L2P + GC-suspend, and a timed `nand_model` with IOPS/p99 stats. Run `make smoke` and `make proto`. No Cosmos+ GPL RTL is vendored; FPGA/ASIC remain out of scope.
