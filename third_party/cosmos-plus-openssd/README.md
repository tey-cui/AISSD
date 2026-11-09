# Cosmos+ OpenSSD — external study baseline

**Not vendored** into AISSD product paths. This directory only documents how to
clone the upstream GPL tree for **study / laboratory** use.

| Item | Value |
|------|-------|
| Upstream | https://github.com/Cosmos-OpenSSD/Cosmos-plus-OpenSSD |
| Pinned commit | `78601486bb5581e40628ec7e841dea8e97eff034` (2022-07-29, `master` tip; no formal release tags) |
| Homepage | https://openssd.dev/ |
| Repository SPDX | **GPL-3.0** |
| AISSD usage | Study-first; clean-room rewrite for commercial paths |

## Clone (pinned)

```bash
git clone https://github.com/Cosmos-OpenSSD/Cosmos-plus-OpenSSD.git
cd Cosmos-plus-OpenSSD
git checkout 78601486bb5581e40628ec7e841dea8e97eff034
```

Optional: place the checkout beside this repo as `../Cosmos-plus-OpenSSD` or under
a lab-only path such as `/opt/lab/cosmos-plus-openssd`. Do **not** merge upstream
RTL/firmware into `include/`, `src/`, or other AISSD first-party trees.

## Optional git submodule (lab isolation)

If the team prefers a submodule for convenience, keep it **only** under
`third_party/cosmos-plus-openssd/tree` (or a similarly named child) and never
compile it into Apache-2.0 product artifacts without legal review:

```bash
git submodule add https://github.com/Cosmos-OpenSSD/Cosmos-plus-OpenSSD.git \
  third_party/cosmos-plus-openssd/tree
cd third_party/cosmos-plus-openssd/tree
git checkout 78601486bb5581e40628ec7e841dea8e97eff034
```

This repository intentionally does **not** register that submodule by default,
to avoid shipping a full GPL tree inside the main product history.

## License notice

See [LICENSE.NOTICE](./LICENSE.NOTICE). Mixing GPL firmware/RTL into AISSD
without notices / obligations is prohibited.

## What to study (pointers)

| Area | Upstream path (after clone) |
|------|-----------------------------|
| NVMe RTL | `source/hardware/nvme/nvme_host_ctrl_{4,8}lane-1.0.0/` |
| GreedyFTL | `source/software/GreedyFTL-3.0.0/` |
| NFC / ECC | `source/hardware/nfc-substrate/`, `low-level-nfc/` |
| Prebuild FPGA | `project/Prebuild/8Ch8Way-3.0.0/` |

AISSD Gen-1 default path is **simulation** (`make smoke`), not Vivado bitstream.
