// SPDX-License-Identifier: Apache-2.0
// Host command submission queue (valid/ready FIFO) for HW sim.
`timescale 1ns/1ps

module host_cmd_queue #(
  parameter int DEPTH  = 16,
  parameter int DATA_W = 80
) (
  input  logic clk,
  input  logic rst_n,
  input  logic                  in_valid,
  output logic                  in_ready,
  input  logic [DATA_W-1:0]     in_data,
  output logic                  out_valid,
  input  logic                  out_ready,
  output logic [DATA_W-1:0]     out_data,
  output logic [$clog2(DEPTH):0] count_o
);
  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
  logic [$clog2(DEPTH):0] count;

  assign count_o  = count;
  assign in_ready = (count < DEPTH[$clog2(DEPTH):0]);
  assign out_valid = (count != 0);
  assign out_data = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      unique case ({in_valid && in_ready, out_valid && out_ready})
        2'b10: begin
          mem[wr_ptr] <= in_data;
          wr_ptr <= wr_ptr + 1'b1;
          count  <= count + 1'b1;
        end
        2'b01: begin
          rd_ptr <= rd_ptr + 1'b1;
          count  <= count - 1'b1;
        end
        2'b11: begin
          mem[wr_ptr] <= in_data;
          wr_ptr <= wr_ptr + 1'b1;
          rd_ptr <= rd_ptr + 1'b1;
        end
        default: ;
      endcase
    end
  end
endmodule
