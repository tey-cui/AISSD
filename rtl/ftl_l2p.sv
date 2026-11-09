// SPDX-License-Identifier: Apache-2.0
// Simple page L2P + GC-suspend-on-LAT_READ flag for HW sim.
`timescale 1ns/1ps

module ftl_l2p #(
  parameter int LBA_W = 16,
  parameter int PBA_W = 16,
  parameter int DEPTH = 256
) (
  input  logic             clk,
  input  logic             rst_n,
  // Lookup
  input  logic             lookup_valid,
  output logic             lookup_ready,
  input  logic [LBA_W-1:0] lookup_lba,
  output logic             lookup_rsp_valid,
  input  logic             lookup_rsp_ready,
  output logic [PBA_W-1:0] lookup_pba,
  output logic             lookup_hit,
  // Update
  input  logic             upd_valid,
  output logic             upd_ready,
  input  logic [LBA_W-1:0] upd_lba,
  input  logic [PBA_W-1:0] upd_pba,
  // GC policy hooks
  input  logic             lat_read_pulse,
  input  logic             gc_resume,
  output logic             gc_may_run,
  output logic [31:0]      gc_suspend_count
);
  logic [PBA_W-1:0] map [0:DEPTH-1];
  logic             valid_bits [0:DEPTH-1];
  logic             gc_suspended;
  logic [31:0]      suspends;
  integer i;

  logic             lu_pend;
  logic [PBA_W-1:0] lu_pba_r;
  logic             lu_hit_r;

  assign gc_may_run        = !gc_suspended;
  assign gc_suspend_count  = suspends;
  assign lookup_ready      = !lu_pend;
  assign lookup_rsp_valid  = lu_pend;
  assign lookup_pba        = lu_pba_r;
  assign lookup_hit        = lu_hit_r;
  assign upd_ready         = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < DEPTH; i++) begin
        map[i]        = i[PBA_W-1:0]; // identity (blocking OK in reset init)
        valid_bits[i] = 1'b1;
      end
      gc_suspended <= 1'b0;
      suspends     <= '0;
      lu_pend      <= 1'b0;
      lu_pba_r     <= '0;
      lu_hit_r     <= 1'b0;
    end else begin
      if (lat_read_pulse) begin
        if (!gc_suspended) begin
          suspends <= suspends + 1'b1;
        end
        gc_suspended <= 1'b1;
      end else if (gc_resume) begin
        gc_suspended <= 1'b0;
      end

      if (lu_pend && lookup_rsp_ready) begin
        lu_pend <= 1'b0;
      end
      if (lookup_valid && lookup_ready) begin
        lu_pend <= 1'b1;
        if (lookup_lba < DEPTH[LBA_W-1:0] && valid_bits[lookup_lba[$clog2(DEPTH)-1:0]]) begin
          lu_hit_r <= 1'b1;
          lu_pba_r <= map[lookup_lba[$clog2(DEPTH)-1:0]];
        end else begin
          lu_hit_r <= 1'b0;
          lu_pba_r <= lookup_lba[PBA_W-1:0];
        end
      end

      if (upd_valid && upd_ready && upd_lba < DEPTH[LBA_W-1:0]) begin
        map[upd_lba[$clog2(DEPTH)-1:0]]        <= upd_pba;
        valid_bits[upd_lba[$clog2(DEPTH)-1:0]] <= 1'b1;
      end
    end
  end
endmodule
