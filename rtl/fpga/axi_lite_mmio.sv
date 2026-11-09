// SPDX-License-Identifier: Apache-2.0
// Minimal AXI4-Lite slave: doorbells into aissd_ctrl_top + status readout.
`timescale 1ns/1ps

module axi_lite_mmio (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite (32-bit data, 8-bit addr enough)
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

  // To controller
  output logic        cmd_valid,
  input  logic        cmd_ready,
  output logic [1:0]  cmd_op,
  output logic [15:0] cmd_lba,
  output logic [7:0]  cmd_nsid,
  output logic [7:0]  cmd_ruh,
  output logic [2:0]  cmd_tc,
  output logic [7:0]  cmd_tag,
  output logic [31:0] cmd_wdata,
  input  logic        cpl_valid,
  output logic        cpl_ready,
  input  logic [7:0]  cpl_tag,
  input  logic [1:0]  cpl_status,
  input  logic [31:0] cpl_rdata,
  input  logic [2:0]  cpl_region,
  input  logic        gc_may_run,
  input  logic [31:0] gc_suspend_count,
  input  logic [31:0] nand_reads,
  input  logic [31:0] nand_writes,
  input  logic [31:0] nand_busy_cycles,
  output logic        gc_resume,
  // Soft traffic-gen enable (optional stage-B hook)
  output logic        tg_enable,
  input  logic [31:0] tg_issued,
  input  logic [31:0] tg_completed
);
  // Register map (byte addresses):
  // 0x00 CMD_CTRL  [1:0] op [10:8] tc  write: doorbell push when bit31=1
  // 0x04 CMD_LBA
  // 0x08 CMD_IDS   [7:0] nsid [15:8] ruh [23:16] tag
  // 0x0C CMD_WDATA
  // 0x10 STATUS    [0] cmd_ready [1] cpl_valid [2] gc_may_run [3] busy_hint
  // 0x14 CPL_META  [7:0] tag [9:8] status [18:16] region
  // 0x18 CPL_RDATA
  // 0x1C GC_CTRL   write bit0 → gc_resume pulse; bit1 → tg_enable
  // 0x20 NAND_READS
  // 0x24 NAND_WRITES
  // 0x28 NAND_BUSY
  // 0x2C GC_SUSP_CNT
  // 0x30 TG_ISSUED
  // 0x34 TG_COMPLETED
  // 0x38 CPL_POP   write any → accept completion (cpl_ready pulse)

  logic [1:0]  r_op;
  logic [2:0]  r_tc;
  logic [15:0] r_lba;
  logic [7:0]  r_nsid, r_ruh, r_tag;
  logic [31:0] r_wdata;
  logic        cmd_pend;
  logic        cpl_pop;
  logic        gc_resume_r;
  logic        tg_enable_r;

  logic        aw_hs, w_hs, b_wait;
  logic [7:0]  awaddr_r;
  logic        ar_hs, r_wait;
  logic [7:0]  araddr_r;

  assign cmd_op    = r_op;
  assign cmd_lba   = r_lba;
  assign cmd_nsid  = r_nsid;
  assign cmd_ruh   = r_ruh;
  assign cmd_tc    = r_tc;
  assign cmd_tag   = r_tag;
  assign cmd_wdata = r_wdata;
  assign cmd_valid = cmd_pend;
  assign cpl_ready = cpl_pop;
  assign gc_resume = gc_resume_r;
  assign tg_enable = tg_enable_r;

  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;

  // Write channel
  assign aw_hs = s_axi_awvalid && s_axi_awready;
  assign w_hs  = s_axi_wvalid && s_axi_wready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_awready <= 1'b1;
      s_axi_wready  <= 1'b1;
      s_axi_bvalid  <= 1'b0;
      b_wait        <= 1'b0;
      awaddr_r      <= '0;
      r_op <= '0; r_tc <= '0; r_lba <= '0;
      r_nsid <= '0; r_ruh <= '0; r_tag <= '0; r_wdata <= '0;
      cmd_pend <= 1'b0; cpl_pop <= 1'b0; gc_resume_r <= 1'b0;
      tg_enable_r <= 1'b0;
    end else begin
      cpl_pop     <= 1'b0;
      gc_resume_r <= 1'b0;
      if (cmd_pend && cmd_ready) begin
        cmd_pend <= 1'b0;
      end

      if (aw_hs) begin
        awaddr_r      <= s_axi_awaddr;
        s_axi_awready <= 1'b0;
      end
      if (w_hs) begin
        s_axi_wready <= 1'b0;
      end
      if (!s_axi_awready && !s_axi_wready && !b_wait) begin
        b_wait       <= 1'b1;
        s_axi_bvalid <= 1'b1;
        unique case (awaddr_r)
          8'h00: begin
            r_op <= s_axi_wdata[1:0];
            r_tc <= s_axi_wdata[10:8];
            if (s_axi_wdata[31]) cmd_pend <= 1'b1;
          end
          8'h04: r_lba <= s_axi_wdata[15:0];
          8'h08: begin
            r_nsid <= s_axi_wdata[7:0];
            r_ruh  <= s_axi_wdata[15:8];
            r_tag  <= s_axi_wdata[23:16];
          end
          8'h0C: r_wdata <= s_axi_wdata;
          8'h1C: begin
            if (s_axi_wdata[0]) gc_resume_r <= 1'b1;
            tg_enable_r <= s_axi_wdata[1];
          end
          8'h38: cpl_pop <= 1'b1;
          default: ;
        endcase
      end
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid  <= 1'b0;
        b_wait        <= 1'b0;
        s_axi_awready <= 1'b1;
        s_axi_wready  <= 1'b1;
      end
    end
  end

  // Read channel
  assign ar_hs = s_axi_arvalid && s_axi_arready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b1;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= '0;
      araddr_r      <= '0;
      r_wait        <= 1'b0;
    end else begin
      if (ar_hs) begin
        araddr_r      <= s_axi_araddr;
        s_axi_arready <= 1'b0;
        r_wait        <= 1'b1;
      end
      if (r_wait && !s_axi_rvalid) begin
        s_axi_rvalid <= 1'b1;
        unique case (araddr_r)
          8'h00: s_axi_rdata <= {20'd0, r_tc, 5'd0, r_op};
          8'h04: s_axi_rdata <= {16'd0, r_lba};
          8'h08: s_axi_rdata <= {8'd0, r_tag, r_ruh, r_nsid};
          8'h0C: s_axi_rdata <= r_wdata;
          8'h10: s_axi_rdata <= {28'd0, 1'b0, gc_may_run, cpl_valid, cmd_ready};
          8'h14: s_axi_rdata <= {13'd0, cpl_region, 6'd0, cpl_status, cpl_tag};
          8'h18: s_axi_rdata <= cpl_rdata;
          8'h1C: s_axi_rdata <= {30'd0, tg_enable_r, 1'b0};
          8'h20: s_axi_rdata <= nand_reads;
          8'h24: s_axi_rdata <= nand_writes;
          8'h28: s_axi_rdata <= nand_busy_cycles;
          8'h2C: s_axi_rdata <= gc_suspend_count;
          8'h30: s_axi_rdata <= tg_issued;
          8'h34: s_axi_rdata <= tg_completed;
          default: s_axi_rdata <= 32'hDEAD_A15D;
        endcase
      end
      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid  <= 1'b0;
        r_wait        <= 1'b0;
        s_axi_arready <= 1'b1;
      end
    end
  end
endmodule
