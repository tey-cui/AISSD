#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Invoke Vivado batch synth stub; fail gracefully if Vivado is absent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v vivado >/dev/null 2>&1; then
  cat <<'EOF'
[fpga-vivado] Vivado not found in PATH.

This cloud/dev environment typically has no Xilinx license or board.
No bitstream was produced (and none is claimed).

On a machine with Vivado:
  source /path/to/Vivado/settings64.sh
  make fpga-vivado
  # optional bitstream:
  AISSD_WRITE_BITSTREAM=1 make fpga-vivado

See docs/fpga-portability.md and constraints/arty_a7_100t.xdc.
EOF
  exit 2
fi

echo "[fpga-vivado] Running Vivado batch flow..."
mkdir -p build/fpga/vivado
vivado -mode batch -source scripts/vivado_synth.tcl \
  -log build/fpga/vivado/vivado.log \
  -journal build/fpga/vivado/vivado.jou
echo "[fpga-vivado] Finished — inspect build/fpga/vivado/"
