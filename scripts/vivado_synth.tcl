# SPDX-License-Identifier: Apache-2.0
# Non-project Vivado synth/impl stub for aissd_fpga_top.
# Run on a machine with Vivado:  vivado -mode batch -source scripts/vivado_synth.tcl
# Cloud agents typically lack Vivado — do not claim bitstream without a successful run.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
cd $repo_root

set out_dir [file join $repo_root build fpga vivado]
file mkdir $out_dir

set part {xc7a100tcsg324-1}
puts "INFO: Using part $part (Arty A7-100T class). Edit scripts/vivado_synth.tcl to change."

create_project -in_memory -part $part

set sources [list \
  rtl/host_cmd_queue.sv \
  rtl/qos_fdp_place.sv \
  rtl/ftl_l2p.sv \
  rtl/nand_timing_model.sv \
  rtl/aissd_ctrl_top.sv \
  rtl/fpga/sync_reset.sv \
  rtl/fpga/axi_lite_mmio.sv \
  rtl/fpga/simple_traffic_gen.sv \
  rtl/fpga/aissd_fpga_top.sv \
  rtl/fpga/aissd_fpga_board.sv \
]

foreach f $sources {
  add_files -norecurse [file join $repo_root $f]
}

set_property top aissd_fpga_board [current_fileset]
add_files -fileset constrs_1 [file join $repo_root constraints arty_a7_100t.xdc]

# Board top ties AXI idle; SW0 enables on-chip TG. For MMIO host, wrap
# aissd_fpga_top in a BD with JTAG-AXI / MicroBlaze instead.

update_compile_order -fileset sources_1

puts "INFO: Running synth_design..."
synth_design -top aissd_fpga_board -part $part

write_checkpoint -force [file join $out_dir post_synth.dcp]
report_utilization -file [file join $out_dir util_synth.rpt]
report_timing_summary -file [file join $out_dir timing_synth.rpt]

puts "INFO: Running place/route (example)..."
opt_design
place_design
route_design

write_checkpoint -force [file join $out_dir post_route.dcp]
report_timing_summary -file [file join $out_dir timing_route.rpt]

# Bitstream only if user sets AISSD_WRITE_BITSTREAM=1
if {[info exists ::env(AISSD_WRITE_BITSTREAM)] && $::env(AISSD_WRITE_BITSTREAM) eq "1"} {
  write_bitstream -force [file join $out_dir aissd_fpga_top.bit]
  puts "INFO: Wrote bitstream build/fpga/vivado/aissd_fpga_top.bit"
} else {
  puts "INFO: Skipping write_bitstream (set AISSD_WRITE_BITSTREAM=1 to enable)."
  puts "INFO: Also wire AXI in a Block Design before expecting host MMIO on hardware."
}

puts "vivado_synth: DONE"
