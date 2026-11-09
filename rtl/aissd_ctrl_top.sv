// SPDX-License-Identifier: Apache-2.0
// AISSD HW-sim controller top: host SQ → decode → FDP → L2P → NAND → CQ.
`timescale 1ns/1ps

module aissd_ctrl_top #(
  parameter int READ_CYC  = 4,
  parameter int PROG_CYC  = 8,
  parameter int PAGES     = 256
) (
  input  logic        clk,
  input  logic        rst_n,
  // Host command ingress
  input  logic        cmd_valid,
  output logic        cmd_ready,
  input  logic [1:0]  cmd_op,
  input  logic [15:0] cmd_lba,
  input  logic [7:0]  cmd_nsid,
  input  logic [7:0]  cmd_ruh,
  input  logic [2:0]  cmd_tc,
  input  logic [7:0]  cmd_tag,
  input  logic [31:0] cmd_wdata,
  // Completion egress
  output logic        cpl_valid,
  input  logic        cpl_ready,
  output logic [7:0]  cpl_tag,
  output logic [1:0]  cpl_status, // 0=OK, 1=ERR
  output logic [31:0] cpl_rdata,
  output logic [2:0]  cpl_region,
  // Observability
  output logic        gc_may_run,
  output logic [31:0] gc_suspend_count,
  output logic [31:0] nand_reads,
  output logic [31:0] nand_writes,
  output logic [31:0] nand_busy_cycles,
  input  logic        gc_resume
);
  localparam int CMD_W = 2+16+8+8+3+8+32; // 77 → pack to 80

  // Packed command: {op[1:0], lba[15:0], nsid[7:0], ruh[7:0], tc[2:0], tag[7:0], wdata[31:0]}
  logic [79:0] cmd_pack, sq_data;
  logic        sq_valid, sq_ready;

  assign cmd_pack = {3'b0, cmd_op, cmd_lba, cmd_nsid, cmd_ruh, cmd_tc, cmd_tag, cmd_wdata};

  logic [4:0] sq_count_unused;
  host_cmd_queue #(.DEPTH(16), .DATA_W(80)) u_sq (
    .clk(clk), .rst_n(rst_n),
    .in_valid(cmd_valid), .in_ready(cmd_ready), .in_data(cmd_pack),
    .out_valid(sq_valid), .out_ready(sq_ready), .out_data(sq_data),
    .count_o(sq_count_unused)
  );

  logic [1:0]  d_op;
  logic [15:0] d_lba;
  logic [7:0]  d_nsid, d_ruh, d_tag;
  logic [2:0]  d_tc;
  logic [31:0] d_wdata;
  assign {d_op, d_lba, d_nsid, d_ruh, d_tc, d_tag, d_wdata} = sq_data[76:0];

  // Pipeline FSM
  typedef enum logic [3:0] {
    S_IDLE,
    S_L2P_REQ,
    S_L2P_WAIT,
    S_PLACE_REQ,
    S_PLACE_WAIT,
    S_NAND_REQ,
    S_NAND_WAIT,
    S_UPD_L2P,
    S_CPL
  } st_e;
  st_e st;

  logic        lat_pulse;
  logic        lu_valid, lu_ready, lu_rsp_valid, lu_rsp_ready, lu_hit;
  logic [15:0] lu_pba;
  logic        upd_valid, upd_ready;
  logic [15:0] upd_lba, upd_pba;

  logic        pl_valid, pl_ready, pl_rsp_valid, pl_rsp_ready;
  logic [15:0] pl_pba;
  logic [2:0]  pl_region;

  logic        nd_valid, nd_ready, nd_rsp_valid, nd_rsp_ready, nd_err;
  logic [31:0] nd_rdata;
  logic        nd_is_write, nd_is_erase;
  logic [15:0] nd_pba;
  logic [31:0] nd_wdata;

  logic [1:0]  hold_op;
  logic [15:0] hold_lba;
  logic [7:0]  hold_ruh, hold_tag;
  logic [2:0]  hold_tc, hold_region;
  logic [31:0] hold_wdata, hold_rdata;
  logic [15:0] hold_pba;
  logic [1:0]  hold_status;

  ftl_l2p #(.DEPTH(PAGES)) u_l2p (
    .clk(clk), .rst_n(rst_n),
    .lookup_valid(lu_valid), .lookup_ready(lu_ready), .lookup_lba(hold_lba),
    .lookup_rsp_valid(lu_rsp_valid), .lookup_rsp_ready(lu_rsp_ready),
    .lookup_pba(lu_pba), .lookup_hit(lu_hit),
    .upd_valid(upd_valid), .upd_ready(upd_ready),
    .upd_lba(upd_lba), .upd_pba(upd_pba),
    .lat_read_pulse(lat_pulse), .gc_resume(gc_resume),
    .gc_may_run(gc_may_run), .gc_suspend_count(gc_suspend_count)
  );

  qos_fdp_place u_fdp (
    .clk(clk), .rst_n(rst_n),
    .req_valid(pl_valid), .req_ready(pl_ready),
    .ruh(hold_ruh), .is_write(hold_op == 2'd1),
    .fallback_pba(hold_lba),
    .rsp_valid(pl_rsp_valid), .rsp_ready(pl_rsp_ready),
    .pba_o(pl_pba), .region_o(pl_region)
  );

  nand_timing_model #(
    .PAGES(PAGES), .READ_CYC(READ_CYC), .PROG_CYC(PROG_CYC)
  ) u_nand (
    .clk(clk), .rst_n(rst_n),
    .req_valid(nd_valid), .req_ready(nd_ready),
    .req_is_write(nd_is_write), .req_is_erase(nd_is_erase),
    .req_pba(nd_pba), .req_wdata(nd_wdata),
    .rsp_valid(nd_rsp_valid), .rsp_ready(nd_rsp_ready),
    .rsp_rdata(nd_rdata), .rsp_err(nd_err),
    .stat_reads(nand_reads), .stat_writes(nand_writes),
    .stat_busy_cycles(nand_busy_cycles)
  );

  assign sq_ready       = (st == S_IDLE);
  assign lu_valid       = (st == S_L2P_REQ);
  assign lu_rsp_ready   = (st == S_L2P_WAIT);
  assign pl_valid       = (st == S_PLACE_REQ);
  assign pl_rsp_ready   = (st == S_PLACE_WAIT);
  assign nd_valid       = (st == S_NAND_REQ);
  assign nd_rsp_ready   = (st == S_NAND_WAIT);
  assign nd_is_write    = (hold_op == 2'd1);
  assign nd_is_erase    = 1'b0;
  assign nd_pba         = hold_pba;
  assign nd_wdata       = hold_wdata;
  assign upd_valid      = (st == S_UPD_L2P);
  assign upd_lba        = hold_lba;
  assign upd_pba        = hold_pba;
  assign cpl_valid      = (st == S_CPL);
  assign cpl_tag        = hold_tag;
  assign cpl_status     = hold_status;
  assign cpl_rdata      = hold_rdata;
  assign cpl_region     = hold_region;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st          <= S_IDLE;
      lat_pulse   <= 1'b0;
      hold_op     <= '0;
      hold_lba    <= '0;
      hold_ruh    <= '0;
      hold_tag    <= '0;
      hold_tc     <= '0;
      hold_wdata  <= '0;
      hold_rdata  <= '0;
      hold_pba    <= '0;
      hold_region <= '0;
      hold_status <= '0;
    end else begin
      lat_pulse <= 1'b0;
      unique case (st)
        S_IDLE: begin
          if (sq_valid) begin
            hold_op    <= d_op;
            hold_lba   <= d_lba;
            hold_ruh   <= d_ruh;
            hold_tag   <= d_tag;
            hold_tc    <= d_tc;
            hold_wdata <= d_wdata;
            // nsid currently observational only in this slice
            if (d_tc == 3'd0) begin
              lat_pulse <= 1'b1;
            end
            if (d_op == 2'd1) begin
              st <= S_PLACE_REQ; // write: place first
            end else begin
              st <= S_L2P_REQ;   // read: lookup first
            end
          end
        end
        S_L2P_REQ: begin
          if (lu_ready) st <= S_L2P_WAIT;
        end
        S_L2P_WAIT: begin
          if (lu_rsp_valid) begin
            hold_pba    <= lu_pba;
            hold_region <= 3'd0;
            st          <= S_NAND_REQ;
          end
        end
        S_PLACE_REQ: begin
          if (pl_ready) st <= S_PLACE_WAIT;
        end
        S_PLACE_WAIT: begin
          if (pl_rsp_valid) begin
            hold_pba    <= pl_pba;
            hold_region <= pl_region;
            st          <= S_NAND_REQ;
          end
        end
        S_NAND_REQ: begin
          if (nd_ready) st <= S_NAND_WAIT;
        end
        S_NAND_WAIT: begin
          if (nd_rsp_valid) begin
            hold_rdata  <= nd_rdata;
            hold_status <= nd_err ? 2'd1 : 2'd0;
            if (hold_op == 2'd1 && !nd_err) st <= S_UPD_L2P;
            else st <= S_CPL;
          end
        end
        S_UPD_L2P: begin
          if (upd_ready) st <= S_CPL;
        end
        S_CPL: begin
          if (cpl_ready) st <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
