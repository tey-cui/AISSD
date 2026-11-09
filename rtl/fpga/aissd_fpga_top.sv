// SPDX-License-Identifier: Apache-2.0
// FPGA board wrapper: sync reset + AXI-Lite MMIO + optional on-chip TG + LEDs.
// Host strategy Stage A/B — not PCIe/NVMe. Clean-room; no Cosmos+ RTL.
`timescale 1ns/1ps

module aissd_fpga_top #(
  parameter int READ_CYC = 4,
  parameter int PROG_CYC = 8,
  parameter int PAGES    = 256
) (
  input  logic        clk_100m,
  input  logic        btn_rst_n,   // active-low button (async)
  // Board switch: force on-chip traffic gen without soft CPU (Stage B)
  input  logic        sw_tg_enable,
  // AXI4-Lite from soft CPU / JTAG-AXI / ILA VIP
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,
  // Status LEDs
  output logic [3:0]  led,
  // Optional UART TX stub (idle high)
  output logic        uart_tx
);
  logic clk;
  logic rst_n;
  logic [23:0] heartbeat;

  assign clk = clk_100m;
  assign uart_tx = 1'b1; // stub: mark idle

  sync_reset #(.STAGES(3)) u_srst (
    .clk(clk),
    .async_rst_n(btn_rst_n),
    .sync_rst_n(rst_n)
  );

  // MMIO path
  logic        m_cmd_valid, m_cmd_ready;
  logic [1:0]  m_cmd_op;
  logic [15:0] m_cmd_lba;
  logic [7:0]  m_cmd_nsid, m_cmd_ruh, m_cmd_tag;
  logic [2:0]  m_cmd_tc;
  logic [31:0] m_cmd_wdata;
  logic        m_cpl_ready;
  logic        gc_resume;
  logic        tg_enable_mmio;
  logic        tg_enable;
  logic [31:0] tg_issued, tg_completed;
  assign tg_enable = tg_enable_mmio | sw_tg_enable;

  // TG path
  logic        t_cmd_valid, t_cmd_ready;
  logic [1:0]  t_cmd_op;
  logic [15:0] t_cmd_lba;
  logic [7:0]  t_cmd_nsid, t_cmd_ruh, t_cmd_tag;
  logic [2:0]  t_cmd_tc;
  logic [31:0] t_cmd_wdata;

  // Muxed into controller
  logic        c_cmd_valid, c_cmd_ready;
  logic [1:0]  c_cmd_op;
  logic [15:0] c_cmd_lba;
  logic [7:0]  c_cmd_nsid, c_cmd_ruh, c_cmd_tag;
  logic [2:0]  c_cmd_tc;
  logic [31:0] c_cmd_wdata;
  logic        c_cpl_valid, c_cpl_ready;
  logic [7:0]  c_cpl_tag;
  logic [1:0]  c_cpl_status;
  logic [31:0] c_cpl_rdata;
  logic [2:0]  c_cpl_region;
  logic        gc_may_run;
  logic [31:0] gc_suspend_count;
  logic [31:0] nand_reads, nand_writes, nand_busy_cycles;

  // When TG enabled, it owns the command stream; else MMIO.
  always_comb begin
    if (tg_enable) begin
      c_cmd_valid = t_cmd_valid;
      c_cmd_op    = t_cmd_op;
      c_cmd_lba   = t_cmd_lba;
      c_cmd_nsid  = t_cmd_nsid;
      c_cmd_ruh   = t_cmd_ruh;
      c_cmd_tc    = t_cmd_tc;
      c_cmd_tag   = t_cmd_tag;
      c_cmd_wdata = t_cmd_wdata;
      t_cmd_ready = c_cmd_ready;
      m_cmd_ready = 1'b0;
    end else begin
      c_cmd_valid = m_cmd_valid;
      c_cmd_op    = m_cmd_op;
      c_cmd_lba   = m_cmd_lba;
      c_cmd_nsid  = m_cmd_nsid;
      c_cmd_ruh   = m_cmd_ruh;
      c_cmd_tc    = m_cmd_tc;
      c_cmd_tag   = m_cmd_tag;
      c_cmd_wdata = m_cmd_wdata;
      m_cmd_ready = c_cmd_ready;
      t_cmd_ready = 1'b0;
    end
  end

  assign c_cpl_ready = tg_enable ? 1'b1 : m_cpl_ready;

  axi_lite_mmio u_mmio (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .cmd_valid(m_cmd_valid), .cmd_ready(m_cmd_ready),
    .cmd_op(m_cmd_op), .cmd_lba(m_cmd_lba), .cmd_nsid(m_cmd_nsid),
    .cmd_ruh(m_cmd_ruh), .cmd_tc(m_cmd_tc), .cmd_tag(m_cmd_tag), .cmd_wdata(m_cmd_wdata),
    .cpl_valid(c_cpl_valid), .cpl_ready(m_cpl_ready),
    .cpl_tag(c_cpl_tag), .cpl_status(c_cpl_status), .cpl_rdata(c_cpl_rdata),
    .cpl_region(c_cpl_region),
    .gc_may_run(gc_may_run), .gc_suspend_count(gc_suspend_count),
    .nand_reads(nand_reads), .nand_writes(nand_writes),
    .nand_busy_cycles(nand_busy_cycles),
    .gc_resume(gc_resume), .tg_enable(tg_enable_mmio),
    .tg_issued(tg_issued), .tg_completed(tg_completed)
  );

  simple_traffic_gen u_tg (
    .clk(clk), .rst_n(rst_n), .enable(tg_enable),
    .cmd_valid(t_cmd_valid), .cmd_ready(t_cmd_ready),
    .cmd_op(t_cmd_op), .cmd_lba(t_cmd_lba), .cmd_nsid(t_cmd_nsid),
    .cmd_ruh(t_cmd_ruh), .cmd_tc(t_cmd_tc), .cmd_tag(t_cmd_tag),
    .cmd_wdata(t_cmd_wdata),
    .cpl_valid(c_cpl_valid), .cpl_ready(c_cpl_ready),
    .issued(tg_issued), .completed(tg_completed)
  );

  aissd_ctrl_top #(
    .READ_CYC(READ_CYC),
    .PROG_CYC(PROG_CYC),
    .PAGES(PAGES)
  ) u_ctrl (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(c_cmd_valid), .cmd_ready(c_cmd_ready),
    .cmd_op(c_cmd_op), .cmd_lba(c_cmd_lba), .cmd_nsid(c_cmd_nsid),
    .cmd_ruh(c_cmd_ruh), .cmd_tc(c_cmd_tc), .cmd_tag(c_cmd_tag),
    .cmd_wdata(c_cmd_wdata),
    .cpl_valid(c_cpl_valid), .cpl_ready(c_cpl_ready),
    .cpl_tag(c_cpl_tag), .cpl_status(c_cpl_status),
    .cpl_rdata(c_cpl_rdata), .cpl_region(c_cpl_region),
    .gc_may_run(gc_may_run), .gc_suspend_count(gc_suspend_count),
    .nand_reads(nand_reads), .nand_writes(nand_writes),
    .nand_busy_cycles(nand_busy_cycles),
    .gc_resume(gc_resume)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) heartbeat <= '0;
    else heartbeat <= heartbeat + 1'b1;
  end

  assign led[0] = heartbeat[23];
  assign led[1] = c_cpl_valid;
  assign led[2] = ~gc_may_run;
  assign led[3] = tg_enable;
endmodule
