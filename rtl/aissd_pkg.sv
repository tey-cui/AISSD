// SPDX-License-Identifier: Apache-2.0
// Clean-room AISSD hardware-sim package (not derived from Cosmos+ RTL).
`timescale 1ns/1ps
`ifndef AISSD_PKG_SV
`define AISSD_PKG_SV

package aissd_pkg;
  typedef enum logic [1:0] {
    OP_READ  = 2'd0,
    OP_WRITE = 2'd1,
    OP_FLUSH = 2'd2,
    OP_DISC  = 2'd3
  } op_e;

  typedef enum logic [2:0] {
    TC_LAT_READ = 3'd0,
    TC_BW_READ  = 3'd1,
    TC_BW_WRITE = 3'd2,
    TC_META     = 3'd3,
    TC_BG       = 3'd4
  } tc_e;

  localparam int LBA_W   = 16;
  localparam int TAG_W   = 8;
  localparam int NSID_W  = 8;
  localparam int RUH_W   = 8;
  localparam int DATA_W  = 32;
  localparam int PBA_W   = 16;
  localparam int L2P_DEPTH = 256;
  localparam int SQ_DEPTH  = 16;
endpackage

`endif
