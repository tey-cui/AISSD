#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run AISSD hardware simulation (Verilator preferred; Icarus fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${OUT_DIR:-build/hw_sim}"
mkdir -p "$OUT_DIR"

RTL_SRCS=(
  rtl/aissd_pkg.sv
  rtl/host_cmd_queue.sv
  rtl/qos_fdp_place.sv
  rtl/ftl_l2p.sv
  rtl/nand_timing_model.sv
  rtl/aissd_ctrl_top.sv
)
TB_SRC=tb/tb_aissd_hw_sim.sv

have_verilator=0
have_icarus=0
command -v verilator >/dev/null 2>&1 && have_verilator=1
command -v iverilog >/dev/null 2>&1 && have_icarus=1

run_verilator() {
  echo "[hw-sim] Using Verilator $(verilator --version | head -1)"
  verilator --binary --timing --trace -Wall -Wno-fatal \
    -Wno-UNUSED -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -Wno-BLKSEQ -Wno-INITIALDLY -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
    -Wno-SYNCASYNCNET \
    --top-module tb_aissd_hw_sim \
    -Mdir "$OUT_DIR/obj_dir" \
    -o "$ROOT/$OUT_DIR/aissd_hw_sim" \
    "${RTL_SRCS[@]}" "$TB_SRC"
  echo "[hw-sim] Running $OUT_DIR/aissd_hw_sim"
  (cd "$OUT_DIR" && ./aissd_hw_sim)
}

run_icarus() {
  echo "[hw-sim] Using Icarus Verilog $(iverilog -V 2>&1 | head -1)"
  # Icarus: emit VCD under OUT_DIR via relative dump path from cwd
  iverilog -g2012 -o "$OUT_DIR/aissd_hw_sim.vvp" \
    "${RTL_SRCS[@]}" "$TB_SRC"
  echo "[hw-sim] Running vvp"
  (cd "$OUT_DIR" && vvp ./aissd_hw_sim.vvp)
}

if [[ "${AISSD_HW_SIM_ENGINE:-auto}" == "verilator" ]] || \
   { [[ "${AISSD_HW_SIM_ENGINE:-auto}" == "auto" ]] && [[ "$have_verilator" -eq 1 ]]; }; then
  run_verilator
elif [[ "${AISSD_HW_SIM_ENGINE:-auto}" == "icarus" ]] || \
     { [[ "${AISSD_HW_SIM_ENGINE:-auto}" == "auto" ]] && [[ "$have_icarus" -eq 1 ]]; }; then
  # Fix dump path when running from OUT_DIR for Icarus
  run_icarus
else
  cat <<'EOF' >&2
[hw-sim] Neither Verilator nor Icarus (iverilog) found.

Install (Debian/Ubuntu):
  sudo apt-get update
  sudo apt-get install -y verilator iverilog

Or with Homebrew:
  brew install verilator icarus-verilog

Then re-run: make hw-sim
EOF
  exit 2
fi
