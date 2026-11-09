## SPDX-License-Identifier: Apache-2.0
## Generic Artix-7 / Ultrascale+ placeholder constraints.
## Replace PACKAGE_PIN TODO_* with real pins before bitstream.

## Clock — TODO: set package pin + period for your board oscillator
# set_property -dict { PACKAGE_PIN TODO_CLK IOSTANDARD LVCMOS33 } [get_ports { clk_100m }];
create_clock -period 10.000 -name sys_clk_pin [get_ports { clk_100m }];

## Reset — TODO
# set_property -dict { PACKAGE_PIN TODO_RST IOSTANDARD LVCMOS33 } [get_ports { btn_rst_n }];

## TG enable switch — TODO
# set_property -dict { PACKAGE_PIN TODO_SW0 IOSTANDARD LVCMOS33 } [get_ports { sw_tg_enable }];

## LEDs — TODO
# set_property -dict { PACKAGE_PIN TODO_LED0 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
# set_property -dict { PACKAGE_PIN TODO_LED1 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
# set_property -dict { PACKAGE_PIN TODO_LED2 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
# set_property -dict { PACKAGE_PIN TODO_LED3 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## UART TX — TODO
# set_property -dict { PACKAGE_PIN TODO_UART IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## Notes for Ultrascale+:
## - Prefer LVCMOS18 / DIFF_SSTL where applicable
## - Add PCIe GT locations only in Stage C (not this shell)
## - DaisyPlus/Cosmos+: use vendor board XDC; keep AISSD RTL clean-room
