// SPDX-License-Identifier: Apache-2.0
// Pin-level board top for blinky / Stage-B TG without soft CPU.
// AXI tied idle; enable traffic via sw_tg_enable.
`timescale 1ns/1ps

module aissd_fpga_board (
  input  logic       clk_100m,
  input  logic       btn_rst_n,
  input  logic       sw_tg_enable,
  output logic [3:0] led,
  output logic       uart_tx
);
  aissd_fpga_top u_top (
    .clk_100m(clk_100m),
    .btn_rst_n(btn_rst_n),
    .sw_tg_enable(sw_tg_enable),
    .s_axi_awaddr(8'd0),
    .s_axi_awvalid(1'b0),
    .s_axi_awready(),
    .s_axi_wdata(32'd0),
    .s_axi_wstrb(4'd0),
    .s_axi_wvalid(1'b0),
    .s_axi_wready(),
    .s_axi_bresp(),
    .s_axi_bvalid(),
    .s_axi_bready(1'b0),
    .s_axi_araddr(8'd0),
    .s_axi_arvalid(1'b0),
    .s_axi_arready(),
    .s_axi_rdata(),
    .s_axi_rresp(),
    .s_axi_rvalid(),
    .s_axi_rready(1'b0),
    .led(led),
    .uart_tx(uart_tx)
  );
endmodule
