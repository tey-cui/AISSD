# AI workload I/O drivers (profiling references)

These projects are **host-side AI serving / cache stacks**, not SSD controller
code. Track them for later I/O trace capture and QoS stress against AISSD sim
or FPGA prototypes.

## LMCache

| Item | Value |
|------|-------|
| Upstream | https://github.com/LMCache/LMCache |
| Role | KV cache offloading / reuse between LLM inference engines and storage/memory tiers |
| Suggested pin | Public tags include **`v0.5.7rc3`** and stable **`v0.5.7`** (prefer `v0.5.7` for profiling unless matching an older local zip). Record `git rev-parse HEAD` after checkout. |
| Controller relevance | Generates large KV read/write traffic useful for `TC_LAT_READ` / spill paths |

```bash
git clone https://github.com/LMCache/LMCache.git
cd LMCache
git tag -l 'v0.5.7*'
# checkout the closest matching tag, then record: git rev-parse HEAD
```

## SGLang

| Item | Value |
|------|-------|
| Upstream | https://github.com/sgl-project/sglang |
| Role | High-performance LLM serving; pairs with KV/cache backends |
| Suggested pin | Public tag **`v0.5.23`** (release SHA reported as `297e54f…` on GitHub); record full `git rev-parse HEAD` after checkout |
| Controller relevance | Multi-tenant inference QD, sequential weight/activation paging, checkpoint-like bursts |

```bash
git clone https://github.com/sgl-project/sglang.git
cd sglang
git tag -l 'v0.5.23*'
# checkout the closest matching tag, then record: git rev-parse HEAD
```

## How AISSD will use them (later)

1. Capture storage-facing traces (block or NVMe) under representative chat/batch loads.
2. Replay against `nand_model` + FTL stubs / FEMU for placement & QoS experiments.
3. Do **not** vendor these trees into AISSD controller sources; document pins only.

Local zip archives previously mentioned by the user are **not** available in this
cloud environment; public GitHub tags are the substitute until artifacts are uploaded.
