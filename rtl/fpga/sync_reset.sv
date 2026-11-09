// SPDX-License-Identifier: Apache-2.0
// Asynchronous assert, synchronous deassert reset synchronizer.
`timescale 1ns/1ps

module sync_reset #(
  parameter int STAGES = 3
) (
  input  logic clk,
  input  logic async_rst_n, // active-low, async
  output logic sync_rst_n
);
  logic [STAGES-1:0] shift;

  always_ff @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
      shift <= '0;
    end else begin
      shift <= {shift[STAGES-2:0], 1'b1};
    end
  end

  assign sync_rst_n = shift[STAGES-1];
endmodule
