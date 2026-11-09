// SPDX-License-Identifier: Apache-2.0
// Self-checking HW-sim TB: KV/checkpoint mix + VCD dump.
`timescale 1ns/1ps

module tb_aissd_hw_sim;
  logic clk;
  logic rst_n;

  logic        cmd_valid, cmd_ready;
  logic [1:0]  cmd_op;
  logic [15:0] cmd_lba;
  logic [7:0]  cmd_nsid, cmd_ruh, cmd_tag;
  logic [2:0]  cmd_tc;
  logic [31:0] cmd_wdata;

  logic        cpl_valid, cpl_ready;
  logic [7:0]  cpl_tag;
  logic [1:0]  cpl_status;
  logic [31:0] cpl_rdata;
  logic [2:0]  cpl_region;

  logic        gc_may_run;
  logic [31:0] gc_suspend_count;
  logic [31:0] nand_reads, nand_writes, nand_busy_cycles;
  logic        gc_resume;

  int unsigned issued;
  int unsigned completed;
  int unsigned errors;
  int unsigned ckpt_region2;
  int unsigned kv_reads;
  bit [31:0]   exp_data [0:255];
  bit          exp_valid [0:255];
  bit [1:0]    pending_tag_op [0:255];
  bit [15:0]   pending_tag_lba [0:255];
  bit          pending_tag_is_wr [0:255];
  bit          tag_inflight [0:255];

  aissd_ctrl_top #(
    .READ_CYC(3),
    .PROG_CYC(5),
    .PAGES(256)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
    .cmd_op(cmd_op), .cmd_lba(cmd_lba), .cmd_nsid(cmd_nsid),
    .cmd_ruh(cmd_ruh), .cmd_tc(cmd_tc), .cmd_tag(cmd_tag),
    .cmd_wdata(cmd_wdata),
    .cpl_valid(cpl_valid), .cpl_ready(cpl_ready),
    .cpl_tag(cpl_tag), .cpl_status(cpl_status),
    .cpl_rdata(cpl_rdata), .cpl_region(cpl_region),
    .gc_may_run(gc_may_run), .gc_suspend_count(gc_suspend_count),
    .nand_reads(nand_reads), .nand_writes(nand_writes),
    .nand_busy_cycles(nand_busy_cycles),
    .gc_resume(gc_resume)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    $dumpfile("aissd_hw_sim.vcd");
    $dumpvars(0, tb_aissd_hw_sim);
  end

  task automatic issue_cmd(
    input [1:0]  op,
    input [15:0] lba,
    input [7:0]  nsid,
    input [7:0]  ruh,
    input [2:0]  tc,
    input [7:0]  tag,
    input [31:0] wdata
  );
    begin
      @(posedge clk);
      while (!cmd_ready) @(posedge clk);
      cmd_op    = op;
      cmd_lba   = lba;
      cmd_nsid  = nsid;
      cmd_ruh   = ruh;
      cmd_tc    = tc;
      cmd_tag   = tag;
      cmd_wdata = wdata;
      cmd_valid = 1'b1;
      @(posedge clk);
      cmd_valid = 1'b0;
      tag_inflight[tag]      = 1'b1;
      pending_tag_op[tag]    = op;
      pending_tag_lba[tag]   = lba;
      pending_tag_is_wr[tag] = (op == 2'd1);
      if (op == 2'd1) begin
        exp_data[lba[7:0]]  = wdata;
        exp_valid[lba[7:0]] = 1'b1;
      end
      issued = issued + 1;
      if (op == 2'd0 && tc == 3'd0) kv_reads = kv_reads + 1;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && cpl_valid && cpl_ready) begin
      completed = completed + 1;
      if (cpl_status != 2'd0) begin
        $display("ERROR: cpl status=%0d tag=%0d", cpl_status, cpl_tag);
        errors = errors + 1;
      end else if (!tag_inflight[cpl_tag]) begin
        $display("ERROR: unexpected tag %0d", cpl_tag);
        errors = errors + 1;
      end else begin
        if (pending_tag_is_wr[cpl_tag]) begin
          if (pending_tag_lba[cpl_tag] >= 16'd40 && cpl_region == 3'd2) begin
            ckpt_region2 = ckpt_region2 + 1;
          end
        end else if (exp_valid[pending_tag_lba[cpl_tag][7:0]] &&
                     cpl_rdata !== exp_data[pending_tag_lba[cpl_tag][7:0]]) begin
          $display("ERROR: data mismatch tag=%0d lba=%0d got=%h exp=%h",
                   cpl_tag, pending_tag_lba[cpl_tag], cpl_rdata,
                   exp_data[pending_tag_lba[cpl_tag][7:0]]);
          errors = errors + 1;
        end
        tag_inflight[cpl_tag] = 1'b0;
      end
    end
  end

  integer t;
  integer seed_i;
  initial begin
    cmd_valid = 0;
    cmd_op = 0; cmd_lba = 0; cmd_nsid = 0; cmd_ruh = 0;
    cmd_tc = 0; cmd_tag = 0; cmd_wdata = 0;
    cpl_ready = 1;
    gc_resume = 0;
    issued = 0; completed = 0; errors = 0;
    ckpt_region2 = 0; kv_reads = 0;
    for (t = 0; t < 256; t = t + 1) begin
      exp_valid[t] = 0;
      tag_inflight[t] = 0;
    end

    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    for (seed_i = 0; seed_i < 8; seed_i = seed_i + 1) begin
      issue_cmd(2'd1, seed_i[15:0], 8'd1, 8'd0, 3'd2, seed_i[7:0],
                32'hA000_0000 + seed_i[31:0]);
    end

    while (completed < issued) @(posedge clk);

    if (!gc_may_run) begin
      $display("ERROR: GC should be runnable before LAT_READ");
      errors = errors + 1;
    end

    for (t = 0; t < 8; t = t + 1) begin
      issue_cmd(2'd0, t[15:0], 8'd1, 8'd1, 3'd0, 8'(16 + t), 32'h0);
    end

    for (t = 0; t < 8; t = t + 1) begin
      issue_cmd(2'd1, 16'(40 + t), 8'd2, 8'd2, 3'd2, 8'(32 + t),
                32'hC000_0000 + t[31:0]);
    end

    for (t = 0; t < 4; t = t + 1) begin
      issue_cmd(2'd0, 16'(t & 7), 8'd1, 8'd1, 3'd0, 8'(48 + t), 32'h0);
    end

    while (completed < issued) @(posedge clk);
    repeat (10) @(posedge clk);

    if (gc_may_run) begin
      $display("ERROR: expected GC suspended after LAT_READ");
      errors = errors + 1;
    end
    if (gc_suspend_count == 0) begin
      $display("ERROR: gc_suspend_count == 0");
      errors = errors + 1;
    end
    if (ckpt_region2 < 4) begin
      $display("ERROR: expected checkpoint writes in region 2, got %0d",
               ckpt_region2);
      errors = errors + 1;
    end
    if (nand_reads == 0 || nand_writes == 0) begin
      $display("ERROR: NAND stats missing R=%0d W=%0d", nand_reads, nand_writes);
      errors = errors + 1;
    end

    @(posedge clk);
    gc_resume = 1'b1;
    @(posedge clk);
    gc_resume = 1'b0;
    @(posedge clk);
    if (!gc_may_run) begin
      $display("ERROR: GC did not resume");
      errors = errors + 1;
    end

    $display("========== AISSD hw-sim report ==========");
    $display("issued/completed : %0d / %0d", issued, completed);
    $display("errors           : %0d", errors);
    $display("kv_reads         : %0d", kv_reads);
    $display("ckpt_region2     : %0d", ckpt_region2);
    $display("gc_suspend_count : %0d", gc_suspend_count);
    $display("nand reads/writes: %0d / %0d", nand_reads, nand_writes);
    $display("nand busy_cycles : %0d", nand_busy_cycles);
    $display("VCD              : aissd_hw_sim.vcd (under build/hw_sim/)");
    $display("=========================================");

    if (errors == 0 && completed == issued && issued > 0) begin
      $display("hw_sim: PASS");
      $finish;
    end else begin
      $display("hw_sim: FAIL");
      $fatal(1);
    end
  end

  initial begin
    #200_000;
    $display("ERROR: timeout");
    $display("hw_sim: FAIL");
    $fatal(1);
  end
endmodule
