// SPDX-License-Identifier: Apache-2.0
// FDP RUH → region → bump-allocated PBA (cycle-approximate HW stub).
`timescale 1ns/1ps

module qos_fdp_place #(
  parameter int RUH_W = 8,
  parameter int PBA_W = 16
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             req_valid,
  output logic             req_ready,
  input  logic [RUH_W-1:0] ruh,
  input  logic             is_write,
  input  logic [PBA_W-1:0] fallback_pba,
  output logic             rsp_valid,
  input  logic             rsp_ready,
  output logic [PBA_W-1:0] pba_o,
  output logic [2:0]       region_o
);
  // Fixed clean-room map: RUH1→region1 base 64; RUH2→region2 base 128.
  localparam logic [PBA_W-1:0] REG1_BASE = 16'd64;
  localparam logic [PBA_W-1:0] REG2_BASE = 16'd128;
  localparam logic [PBA_W-1:0] REG1_SIZE = 16'd64;
  localparam logic [PBA_W-1:0] REG2_SIZE = 16'd64;

  logic [PBA_W-1:0] bump1, bump2;
  logic [PBA_W-1:0] pba_r;
  logic [2:0]       region_r;
  logic             pending;

  assign req_ready = !pending;
  assign rsp_valid = pending;
  assign pba_o     = pba_r;
  assign region_o  = region_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bump1   <= '0;
      bump2   <= '0;
      pba_r   <= '0;
      region_r<= '0;
      pending <= 1'b0;
    end else begin
      if (pending && rsp_ready) begin
        pending <= 1'b0;
      end
      if (req_valid && req_ready) begin
        pending <= 1'b1;
        if (!is_write || ruh == '0) begin
          region_r <= 3'd0;
          pba_r    <= fallback_pba;
        end else if (ruh == 8'd1 && bump1 < REG1_SIZE) begin
          region_r <= 3'd1;
          pba_r    <= REG1_BASE + bump1;
          bump1    <= bump1 + 1'b1;
        end else if (ruh == 8'd2 && bump2 < REG2_SIZE) begin
          region_r <= 3'd2;
          pba_r    <= REG2_BASE + bump2;
          bump2    <= bump2 + 1'b1;
        end else begin
          region_r <= 3'd0;
          pba_r    <= fallback_pba;
        end
      end
    end
  end
endmodule
