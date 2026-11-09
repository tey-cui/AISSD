## SPDX-License-Identifier: Apache-2.0
## Example constraints for Digilent Arty A7-100T (xc7a100tcsg324-1).
## Intended top: aissd_fpga_board (AXI tied off; SW0 enables on-chip TG).
## Pinout from Digilent Arty A7 reference — verify against your board revision.

## 100 MHz system clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk_100m }];
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports { clk_100m }];

## Reset: use CK_RST (active low) as btn_rst_n — TODO confirm silkscreen vs schematic
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { btn_rst_n }];

## SW0 → on-chip traffic generator enable
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { sw_tg_enable }];

## LEDs LD0..LD3
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## UART USB-UART TX (stub idle-high)
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## For Stage A soft-CPU MMIO: use aissd_fpga_top inside a Block Design instead.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
