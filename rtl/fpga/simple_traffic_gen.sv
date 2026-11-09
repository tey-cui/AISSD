// SPDX-License-Identifier: Apache-2.0
// Optional Stage-B on-chip traffic: few KV reads + checkpoint writes.
// Gated by tg_enable; shares cmd stream with MMIO via simple mux upstream.
`timescale 1ns/1ps

module simple_traffic_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
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
  input  logic        cpl_ready,
  output logic [31:0] issued,
  output logic [31:0] completed
);
  typedef enum logic [1:0] {TG_IDLE, TG_ISSUE, TG_WAIT, TG_DONE} st_e;
  st_e st;
  logic [4:0] idx;
  logic [31:0] iss_r, cpl_r;

  assign issued    = iss_r;
  assign completed = cpl_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= TG_IDLE;
      idx <= '0;
      iss_r <= '0;
      cpl_r <= '0;
      cmd_valid <= 1'b0;
      cmd_op <= '0; cmd_lba <= '0; cmd_nsid <= '0; cmd_ruh <= '0;
      cmd_tc <= '0; cmd_tag <= '0; cmd_wdata <= '0;
    end else begin
      if (cpl_valid && cpl_ready) begin
        cpl_r <= cpl_r + 1'b1;
      end

      unique case (st)
        TG_IDLE: begin
          cmd_valid <= 1'b0;
          if (enable) begin
            idx <= '0;
            st  <= TG_ISSUE;
          end
        end
        TG_ISSUE: begin
          if (!enable) begin
            cmd_valid <= 1'b0;
            st <= TG_IDLE;
          end else if (idx < 5'd12) begin
            cmd_valid <= 1'b1;
            if (idx < 5'd4) begin
              // seed writes
              cmd_op <= 2'd1; cmd_tc <= 3'd2; cmd_ruh <= 8'd0;
              cmd_nsid <= 8'd1; cmd_lba <= {11'd0, idx[4:0]};
              cmd_tag <= {3'd0, idx}; cmd_wdata <= 32'hF000_0000 + idx;
            end else if (idx < 5'd8) begin
              // KV-like LAT_READ
              cmd_op <= 2'd0; cmd_tc <= 3'd0; cmd_ruh <= 8'd1;
              cmd_nsid <= 8'd1; cmd_lba <= {11'd0, idx[4:0] - 5'd4};
              cmd_tag <= {3'd0, idx}; cmd_wdata <= '0;
            end else begin
              // checkpoint writes RUH2
              cmd_op <= 2'd1; cmd_tc <= 3'd2; cmd_ruh <= 8'd2;
              cmd_nsid <= 8'd2; cmd_lba <= 16'd40 + (idx - 5'd8);
              cmd_tag <= {3'd0, idx}; cmd_wdata <= 32'hC100_0000 + idx;
            end
            if (cmd_ready) begin
              iss_r <= iss_r + 1'b1;
              idx   <= idx + 1'b1;
              cmd_valid <= 1'b0;
              st <= TG_WAIT;
            end
          end else begin
            cmd_valid <= 1'b0;
            st <= TG_DONE;
          end
        end
        TG_WAIT: begin
          cmd_valid <= 1'b0;
          st <= TG_ISSUE;
        end
        TG_DONE: begin
          cmd_valid <= 1'b0;
          if (!enable) st <= TG_IDLE;
        end
        default: st <= TG_IDLE;
      endcase
    end
  end
endmodule
