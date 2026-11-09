#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# FPGA lint / elaboration checks. Does NOT produce a bitstream.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/fpga

FILELIST=(
  rtl/host_cmd_queue.sv
  rtl/qos_fdp_place.sv
  rtl/ftl_l2p.sv
  rtl/nand_timing_model.sv
  rtl/aissd_ctrl_top.sv
  rtl/fpga/sync_reset.sv
  rtl/fpga/axi_lite_mmio.sv
  rtl/fpga/simple_traffic_gen.sv
  rtl/fpga/aissd_fpga_top.sv
  rtl/fpga/aissd_fpga_board.sv
)

ok=0

if command -v verilator >/dev/null 2>&1; then
  echo "[fpga-lint] Verilator lint-only (synth RTL, top=aissd_fpga_board)"
  verilator --lint-only -Wall -Wno-fatal \
    -Wno-UNUSED -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET -Wno-BLKSEQ \
    --top-module aissd_fpga_board \
    "${FILELIST[@]}"
  echo "[fpga-lint] Verilator: OK"
  ok=1
else
  echo "[fpga-lint] Verilator not found — skip (install verilator for primary lint)"
fi

if command -v yosys >/dev/null 2>&1; then
  echo "[fpga-lint] Yosys elaboration/synth check (best-effort SV)"
  set +e
  yosys -s scripts/yosys_fpga_lint.ys > build/fpga/yosys_lint.log 2>&1
  ys=$?
  set -e
  if [[ "$ys" -eq 0 ]]; then
    echo "[fpga-lint] Yosys: OK (see build/fpga/yosys_lint.log)"
    ok=1
  else
    echo "[fpga-lint] Yosys: FAILED or unsupported SV constructs (see build/fpga/yosys_lint.log)"
    echo "[fpga-lint] This is non-fatal if Verilator lint passed — Yosys 0.33 SV is limited."
    # Prefer not failing the make target if Verilator already succeeded.
    if [[ "$ok" -eq 0 ]]; then
      tail -40 build/fpga/yosys_lint.log >&2 || true
      exit 1
    fi
  fi
else
  echo "[fpga-lint] Yosys not found — skip (sudo apt-get install -y yosys)"
fi

if [[ "$ok" -eq 0 ]]; then
  echo "[fpga-lint] FAIL: need verilator and/or yosys" >&2
  exit 2
fi

echo "fpga_lint: PASS"
echo "Note: no bitstream generated (Vivado/board not required for this target)."
