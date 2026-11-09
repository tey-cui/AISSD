// SPDX-License-Identifier: Apache-2.0
// Cycle-approximate NAND timing model (bus-functional; not ONFI PHY).
`timescale 1ns/1ps

module nand_timing_model #(
  parameter int PBA_W       = 16,
  parameter int DATA_W      = 32,
  parameter int PAGES       = 256,
  parameter int READ_CYC    = 4,
  parameter int PROG_CYC    = 8,
  parameter int ERASE_CYC   = 12
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             req_valid,
  output logic             req_ready,
  input  logic             req_is_write,
  input  logic             req_is_erase,
  input  logic [PBA_W-1:0] req_pba,
  input  logic [DATA_W-1:0] req_wdata,
  output logic             rsp_valid,
  input  logic             rsp_ready,
  output logic [DATA_W-1:0] rsp_rdata,
  output logic             rsp_err,
  output logic [31:0]      stat_reads,
  output logic [31:0]      stat_writes,
  output logic [31:0]      stat_busy_cycles
);
  typedef enum logic [1:0] {ST_IDLE, ST_BUSY, ST_DONE} state_e;
  state_e state;

  logic [DATA_W-1:0] mem [0:PAGES-1];
  logic              programmed [0:PAGES-1];
  logic [15:0]       busy_left;
  logic [DATA_W-1:0] rdata_r;
  logic              err_r;
  logic              is_wr_r;
  logic [31:0]       reads_r, writes_r, busy_r;
  integer i;

  assign req_ready        = (state == ST_IDLE);
  assign rsp_valid        = (state == ST_DONE);
  assign rsp_rdata        = rdata_r;
  assign rsp_err          = err_r;
  assign stat_reads       = reads_r;
  assign stat_writes      = writes_r;
  assign stat_busy_cycles = busy_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      busy_left<= '0;
      rdata_r  <= '0;
      err_r    <= 1'b0;
      is_wr_r  <= 1'b0;
      reads_r  <= '0;
      writes_r <= '0;
      busy_r   <= '0;
      for (i = 0; i < PAGES; i++) begin
        mem[i]        = '0; // blocking OK in reset init (Verilator)
        programmed[i] = 1'b0;
      end
    end else begin
      unique case (state)
        ST_IDLE: begin
          if (req_valid && req_ready) begin
            if (req_pba >= PAGES[PBA_W-1:0]) begin
              err_r    <= 1'b1;
              rdata_r  <= '0;
              busy_left<= 16'd1;
              is_wr_r  <= 1'b0;
              state    <= ST_BUSY;
            end else if (req_is_erase) begin
              programmed[req_pba] <= 1'b0;
              mem[req_pba]        <= '0;
              err_r               <= 1'b0;
              busy_left           <= ERASE_CYC[15:0];
              is_wr_r             <= 1'b0;
              state               <= ST_BUSY;
            end else if (req_is_write) begin
              mem[req_pba]        <= req_wdata;
              programmed[req_pba] <= 1'b1;
              writes_r            <= writes_r + 1'b1;
              err_r               <= 1'b0;
              busy_left           <= PROG_CYC[15:0];
              is_wr_r             <= 1'b1;
              state               <= ST_BUSY;
            end else begin
              rdata_r  <= programmed[req_pba] ? mem[req_pba] : '0;
              reads_r  <= reads_r + 1'b1;
              err_r    <= 1'b0;
              busy_left<= READ_CYC[15:0];
              is_wr_r  <= 1'b0;
              state    <= ST_BUSY;
            end
          end
        end
        ST_BUSY: begin
          busy_r <= busy_r + 1'b1;
          if (busy_left <= 16'd1) begin
            state <= ST_DONE;
          end else begin
            busy_left <= busy_left - 1'b1;
          end
        end
        ST_DONE: begin
          if (rsp_ready) begin
            state <= ST_IDLE;
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
