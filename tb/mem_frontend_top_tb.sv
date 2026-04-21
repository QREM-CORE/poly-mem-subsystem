`timescale 1ns/1ps

import qrem_mem_map_pkg::*;
import qrem_seed_map_pkg::*;

module mem_frontend_top_tb;
  // Integration TB for the v0.85 memory subsystem.
  // The old mem_frontend_top block was merged into poly_mem_subsystem, but
  // this filename is kept so existing build flows still have a stable target.

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 32;
  localparam int SEED_W     = 64;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_W    = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);

  logic clk;
  logic rst;
  logic wipe_i;
  logic wipe_busy_o;
  logic wipe_done_o;
  logic mem_fault_o;
  logic [2:0] mem_fault_code_o;

  logic                           pau_req;
  logic                           pau_rd_en;
  logic [POLY_W-1:0]              pau_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        pau_rd_idx;
  logic [3:0]                     pau_rd_lane_valid;
  logic [3:0]                     pau_wr_en;
  logic [POLY_W-1:0]              pau_wr_poly_id;
  logic [3:0][COEFF_W-1:0]        pau_wr_idx;
  logic [3:0][W-1:0]              pau_wr_data;
  logic                           pau_rd_valid;
  logic [POLY_W-1:0]              pau_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0]        pau_rd_idx_o;
  logic [3:0]                     pau_rd_lane_valid_o;
  logic [3:0][W-1:0]              pau_rd_data;
  logic                           pau_stall;

  logic                           pau_aux_req;
  logic                           pau_aux_rd_en;
  logic [POLY_W-1:0]              pau_aux_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        pau_aux_rd_idx;
  logic [3:0]                     pau_aux_rd_lane_valid;
  logic [3:0]                     pau_aux_wr_en;
  logic [POLY_W-1:0]              pau_aux_wr_poly_id;
  logic [3:0][COEFF_W-1:0]        pau_aux_wr_idx;
  logic [3:0][W-1:0]              pau_aux_wr_data;
  logic                           pau_aux_rd_valid;
  logic [POLY_W-1:0]              pau_aux_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0]        pau_aux_rd_idx_o;
  logic [3:0]                     pau_aux_rd_lane_valid_o;
  logic [3:0][W-1:0]              pau_aux_rd_data;

  logic                           hsu_req;
  logic                           hsu_rd_en;
  logic [POLY_W-1:0]              hsu_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        hsu_rd_idx;
  logic [3:0]                     hsu_rd_lane_valid;
  logic [3:0]                     hsu_wr_en;
  logic [POLY_W-1:0]              hsu_wr_poly_id;
  logic [3:0][COEFF_W-1:0]        hsu_wr_idx;
  logic [3:0][W-1:0]              hsu_wr_data;
  logic                           hsu_rd_valid;
  logic [POLY_W-1:0]              hsu_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0]        hsu_rd_idx_o;
  logic [3:0]                     hsu_rd_lane_valid_o;
  logic [3:0][W-1:0]              hsu_rd_data;
  logic                           hsu_stall;

  logic                           tr_req;
  logic                           tr_rd_en;
  logic [POLY_W-1:0]              tr_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        tr_rd_idx;
  logic [3:0]                     tr_rd_lane_valid;
  logic [3:0]                     tr_wr_en;
  logic [POLY_W-1:0]              tr_wr_poly_id;
  logic [3:0][COEFF_W-1:0]        tr_wr_idx;
  logic [3:0][W-1:0]              tr_wr_data;
  logic                           tr_rd_valid;
  logic [POLY_W-1:0]              tr_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0]        tr_rd_idx_o;
  logic [3:0]                     tr_rd_lane_valid_o;
  logic [3:0][W-1:0]              tr_rd_data;
  logic                           tr_stall;

  logic                           hsu_seed_req;
  logic                           hsu_seed_we;
  logic [SEED_AW-1:0]             hsu_seed_addr;
  logic [SEED_W-1:0]              hsu_seed_wdata;
  logic                           hsu_seed_ready;
  logic                           hsu_seed_rvalid;
  logic [SEED_W-1:0]              hsu_seed_rdata;

  logic                           tr_seed_req;
  logic                           tr_seed_we;
  logic [SEED_AW-1:0]             tr_seed_addr;
  logic [SEED_W-1:0]              tr_seed_wdata;
  logic                           tr_seed_ready;
  logic                           tr_seed_rvalid;
  logic [SEED_W-1:0]              tr_seed_rdata;

  poly_mem_subsystem #(
    .NUM_POLYS  (NUM_POLYS),
    .NCOEFF     (NCOEFF),
    .W          (W),
    .SEED_DEPTH (SEED_DEPTH),
    .SEED_W     (SEED_W)
  ) dut (
    .clk(clk),
    .rst(rst),
    .wipe_i(wipe_i),
    .wipe_busy_o(wipe_busy_o),
    .wipe_done_o(wipe_done_o),
    .mem_fault_o(mem_fault_o),
    .mem_fault_code_o(mem_fault_code_o),
    .pau_req(pau_req),
    .pau_rd_en(pau_rd_en),
    .pau_rd_poly_id(pau_rd_poly_id),
    .pau_rd_idx(pau_rd_idx),
    .pau_rd_lane_valid(pau_rd_lane_valid),
    .pau_wr_en(pau_wr_en),
    .pau_wr_poly_id(pau_wr_poly_id),
    .pau_wr_idx(pau_wr_idx),
    .pau_wr_data(pau_wr_data),
    .pau_rd_valid(pau_rd_valid),
    .pau_rd_poly_id_o(pau_rd_poly_id_o),
    .pau_rd_idx_o(pau_rd_idx_o),
    .pau_rd_lane_valid_o(pau_rd_lane_valid_o),
    .pau_rd_data(pau_rd_data),
    .pau_stall(pau_stall),
    .pau_aux_req(pau_aux_req),
    .pau_aux_rd_en(pau_aux_rd_en),
    .pau_aux_rd_poly_id(pau_aux_rd_poly_id),
    .pau_aux_rd_idx(pau_aux_rd_idx),
    .pau_aux_rd_lane_valid(pau_aux_rd_lane_valid),
    .pau_aux_wr_en(pau_aux_wr_en),
    .pau_aux_wr_poly_id(pau_aux_wr_poly_id),
    .pau_aux_wr_idx(pau_aux_wr_idx),
    .pau_aux_wr_data(pau_aux_wr_data),
    .pau_aux_rd_valid(pau_aux_rd_valid),
    .pau_aux_rd_poly_id_o(pau_aux_rd_poly_id_o),
    .pau_aux_rd_idx_o(pau_aux_rd_idx_o),
    .pau_aux_rd_lane_valid_o(pau_aux_rd_lane_valid_o),
    .pau_aux_rd_data(pau_aux_rd_data),
    .hsu_req(hsu_req),
    .hsu_rd_en(hsu_rd_en),
    .hsu_rd_poly_id(hsu_rd_poly_id),
    .hsu_rd_idx(hsu_rd_idx),
    .hsu_rd_lane_valid(hsu_rd_lane_valid),
    .hsu_wr_en(hsu_wr_en),
    .hsu_wr_poly_id(hsu_wr_poly_id),
    .hsu_wr_idx(hsu_wr_idx),
    .hsu_wr_data(hsu_wr_data),
    .hsu_rd_valid(hsu_rd_valid),
    .hsu_rd_poly_id_o(hsu_rd_poly_id_o),
    .hsu_rd_idx_o(hsu_rd_idx_o),
    .hsu_rd_lane_valid_o(hsu_rd_lane_valid_o),
    .hsu_rd_data(hsu_rd_data),
    .hsu_stall(hsu_stall),
    .tr_req(tr_req),
    .tr_rd_en(tr_rd_en),
    .tr_rd_poly_id(tr_rd_poly_id),
    .tr_rd_idx(tr_rd_idx),
    .tr_rd_lane_valid(tr_rd_lane_valid),
    .tr_wr_en(tr_wr_en),
    .tr_wr_poly_id(tr_wr_poly_id),
    .tr_wr_idx(tr_wr_idx),
    .tr_wr_data(tr_wr_data),
    .tr_rd_valid(tr_rd_valid),
    .tr_rd_poly_id_o(tr_rd_poly_id_o),
    .tr_rd_idx_o(tr_rd_idx_o),
    .tr_rd_lane_valid_o(tr_rd_lane_valid_o),
    .tr_rd_data(tr_rd_data),
    .tr_stall(tr_stall),
    .hsu_seed_req(hsu_seed_req),
    .hsu_seed_we(hsu_seed_we),
    .hsu_seed_addr(hsu_seed_addr),
    .hsu_seed_wdata(hsu_seed_wdata),
    .hsu_seed_ready(hsu_seed_ready),
    .hsu_seed_rvalid(hsu_seed_rvalid),
    .hsu_seed_rdata(hsu_seed_rdata),
    .tr_seed_req(tr_seed_req),
    .tr_seed_we(tr_seed_we),
    .tr_seed_addr(tr_seed_addr),
    .tr_seed_wdata(tr_seed_wdata),
    .tr_seed_ready(tr_seed_ready),
    .tr_seed_rvalid(tr_seed_rvalid),
    .tr_seed_rdata(tr_seed_rdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic clear_poly_clients;
    begin
      pau_req           = 1'b0;
      pau_rd_en         = 1'b0;
      pau_rd_poly_id    = '0;
      pau_rd_idx        = '0;
      pau_rd_lane_valid = '0;
      pau_wr_en         = '0;
      pau_wr_poly_id    = '0;
      pau_wr_idx        = '0;
      pau_wr_data       = '0;

      pau_aux_req           = 1'b0;
      pau_aux_rd_en         = 1'b0;
      pau_aux_rd_poly_id    = '0;
      pau_aux_rd_idx        = '0;
      pau_aux_rd_lane_valid = '0;
      pau_aux_wr_en         = '0;
      pau_aux_wr_poly_id    = '0;
      pau_aux_wr_idx        = '0;
      pau_aux_wr_data       = '0;

      hsu_req           = 1'b0;
      hsu_rd_en         = 1'b0;
      hsu_rd_poly_id    = '0;
      hsu_rd_idx        = '0;
      hsu_rd_lane_valid = '0;
      hsu_wr_en         = '0;
      hsu_wr_poly_id    = '0;
      hsu_wr_idx        = '0;
      hsu_wr_data       = '0;

      tr_req            = 1'b0;
      tr_rd_en          = 1'b0;
      tr_rd_poly_id     = '0;
      tr_rd_idx         = '0;
      tr_rd_lane_valid  = '0;
      tr_wr_en          = '0;
      tr_wr_poly_id     = '0;
      tr_wr_idx         = '0;
      tr_wr_data        = '0;
    end
  endtask

  task automatic clear_seed_clients;
    begin
      hsu_seed_req   = 1'b0;
      hsu_seed_we    = 1'b0;
      hsu_seed_addr  = '0;
      hsu_seed_wdata = '0;
      tr_seed_req    = 1'b0;
      tr_seed_we     = 1'b0;
      tr_seed_addr   = '0;
      tr_seed_wdata  = '0;
    end
  endtask

  task automatic clear_all;
    begin
      wipe_i = 1'b0;
      clear_poly_clients();
      clear_seed_clients();
    end
  endtask

  task automatic prime_poly_with_pau(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      pau_req        = 1'b1;
      pau_wr_en      = 4'b1111;
      pau_wr_poly_id = POLY_W'(poly_id);
      pau_wr_idx[0]  = COEFF_W'(idx0);
      pau_wr_idx[1]  = COEFF_W'(idx1);
      pau_wr_idx[2]  = COEFF_W'(idx2);
      pau_wr_idx[3]  = COEFF_W'(idx3);
      pau_wr_data[0] = d0;
      pau_wr_data[1] = d1;
      pau_wr_data[2] = d2;
      pau_wr_data[3] = d3;
      tick();
      clear_poly_clients();
    end
  endtask

  task automatic read_poly_with_pau(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] e0, input logic [W-1:0] e1,
    input logic [W-1:0] e2, input logic [W-1:0] e3
  );
    begin
      pau_req           = 1'b1;
      pau_rd_en         = 1'b1;
      pau_rd_poly_id    = POLY_W'(poly_id);
      pau_rd_idx[0]     = COEFF_W'(idx0);
      pau_rd_idx[1]     = COEFF_W'(idx1);
      pau_rd_idx[2]     = COEFF_W'(idx2);
      pau_rd_idx[3]     = COEFF_W'(idx3);
      pau_rd_lane_valid = 4'b1111;
      tick();
      if (!pau_rd_valid)
        $fatal(1, "Expected PAU read response");
      if (pau_rd_data[0] !== e0 || pau_rd_data[1] !== e1 ||
          pau_rd_data[2] !== e2 || pau_rd_data[3] !== e3)
        $fatal(1, "PAU read mismatch");
      clear_poly_clients();
    end
  endtask

  task automatic read_poly_with_tr(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] e0, input logic [W-1:0] e1,
    input logic [W-1:0] e2, input logic [W-1:0] e3
  );
    begin
      tr_req           = 1'b1;
      tr_rd_en         = 1'b1;
      tr_rd_poly_id    = POLY_W'(poly_id);
      tr_rd_idx[0]     = COEFF_W'(idx0);
      tr_rd_idx[1]     = COEFF_W'(idx1);
      tr_rd_idx[2]     = COEFF_W'(idx2);
      tr_rd_idx[3]     = COEFF_W'(idx3);
      tr_rd_lane_valid = 4'b1111;
      tick();
      if (!tr_rd_valid)
        $fatal(1, "Expected Transcoder read response");
      if (tr_rd_data[0] !== e0 || tr_rd_data[1] !== e1 ||
          tr_rd_data[2] !== e2 || tr_rd_data[3] !== e3)
        $fatal(1, "Transcoder read mismatch");
      clear_poly_clients();
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_all();
    repeat (2) tick();
    rst = 1'b0;
    tick();

    if (POLY_ID_S0 != 0 || POLY_ID_S3 != 3 || POLY_ID_EI != 4 ||
        POLY_ID_A0 != 5 || POLY_ID_A3 != 8 ||
        POLY_ID_T0 != 9 || POLY_ID_T3 != 12 ||
        POLY_ID_WORK0 != 13 || POLY_ID_WORK18 != 31)
      $fatal(1, "Unexpected fixed v0.85 poly-id slot layout");

    // Prime data used by scheduler and overlap checks.
    prime_poly_with_pau(POLY_ID_S2, 0, 1, 2, 3, 16'h1200, 16'h1201, 16'h1202, 16'h1203);
    prime_poly_with_pau(POLY_ID_A1, 12, 13, 14, 15, 16'h6600, 16'h6601, 16'h6602, 16'h6603);

    // ------------------------------------------------------------------
    // 1) PAU-owned legal dual-read using primary + auxiliary descriptors.
    // ------------------------------------------------------------------
    pau_req               = 1'b1;
    pau_rd_en             = 1'b1;
    pau_rd_poly_id        = POLY_ID_S2;
    pau_rd_idx[0]         = COEFF_W'(0);
    pau_rd_idx[1]         = COEFF_W'(1);
    pau_rd_idx[2]         = COEFF_W'(2);
    pau_rd_idx[3]         = COEFF_W'(3);
    pau_rd_lane_valid     = 4'b1111;

    pau_aux_req           = 1'b1;
    pau_aux_rd_en         = 1'b1;
    pau_aux_rd_poly_id    = POLY_ID_A1;
    pau_aux_rd_idx[0]     = COEFF_W'(12);
    pau_aux_rd_idx[1]     = COEFF_W'(13);
    pau_aux_rd_idx[2]     = COEFF_W'(14);
    pau_aux_rd_idx[3]     = COEFF_W'(15);
    pau_aux_rd_lane_valid = 4'b1111;
    #1;

    if (pau_stall)
      $fatal(1, "Expected legal PAU primary+aux dual-read issue");
    tick();

    if (!pau_rd_valid || !pau_aux_rd_valid)
      $fatal(1, "Expected both PAU read response channels");
    if (pau_rd_poly_id_o !== POLY_W'(POLY_ID_S2) ||
        pau_aux_rd_poly_id_o !== POLY_W'(POLY_ID_A1))
      $fatal(1, "PAU auxiliary read tags mismatch");
    if (pau_rd_data[0] !== 16'h1200 || pau_rd_data[1] !== 16'h1201 ||
        pau_rd_data[2] !== 16'h1202 || pau_rd_data[3] !== 16'h1203)
      $fatal(1, "PAU primary dual-read data mismatch");
    if (pau_aux_rd_data[0] !== 16'h6600 || pau_aux_rd_data[1] !== 16'h6601 ||
        pau_aux_rd_data[2] !== 16'h6602 || pau_aux_rd_data[3] !== 16'h6603)
      $fatal(1, "PAU auxiliary dual-read data mismatch");
    clear_poly_clients();

    // ------------------------------------------------------------------
    // 2) PAU-owned legal dual-write using both internal ports.
    // ------------------------------------------------------------------
    pau_req            = 1'b1;
    pau_wr_en          = 4'b1111;
    pau_wr_poly_id     = POLY_ID_WORK5;
    pau_wr_idx[0]      = COEFF_W'(32);
    pau_wr_idx[1]      = COEFF_W'(33);
    pau_wr_idx[2]      = COEFF_W'(34);
    pau_wr_idx[3]      = COEFF_W'(35);
    pau_wr_data[0]     = 16'hA500;
    pau_wr_data[1]     = 16'hA501;
    pau_wr_data[2]     = 16'hA502;
    pau_wr_data[3]     = 16'hA503;

    pau_aux_req        = 1'b1;
    pau_aux_wr_en      = 4'b1111;
    pau_aux_wr_poly_id = POLY_ID_WORK6;
    pau_aux_wr_idx[0]  = COEFF_W'(36);
    pau_aux_wr_idx[1]  = COEFF_W'(37);
    pau_aux_wr_idx[2]  = COEFF_W'(38);
    pau_aux_wr_idx[3]  = COEFF_W'(39);
    pau_aux_wr_data[0] = 16'hA600;
    pau_aux_wr_data[1] = 16'hA601;
    pau_aux_wr_data[2] = 16'hA602;
    pau_aux_wr_data[3] = 16'hA603;
    #1;

    if (pau_stall)
      $fatal(1, "Expected legal PAU primary+aux dual-write issue");
    tick();
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK5, 32, 33, 34, 35,
                       16'hA500, 16'hA501, 16'hA502, 16'hA503);
    read_poly_with_pau(POLY_ID_WORK6, 36, 37, 38, 39,
                       16'hA600, 16'hA601, 16'hA602, 16'hA603);

    // ------------------------------------------------------------------
    // 3) PAU-owned legal read/write overlap.
    // ------------------------------------------------------------------
    pau_req               = 1'b1;
    pau_rd_en             = 1'b1;
    pau_rd_poly_id        = POLY_ID_S2;
    pau_rd_idx[0]         = COEFF_W'(0);
    pau_rd_idx[1]         = COEFF_W'(1);
    pau_rd_idx[2]         = COEFF_W'(2);
    pau_rd_idx[3]         = COEFF_W'(3);
    pau_rd_lane_valid     = 4'b1111;

    pau_aux_req           = 1'b1;
    pau_aux_wr_en         = 4'b1111;
    pau_aux_wr_poly_id    = POLY_ID_WORK7;
    pau_aux_wr_idx[0]     = COEFF_W'(40);
    pau_aux_wr_idx[1]     = COEFF_W'(41);
    pau_aux_wr_idx[2]     = COEFF_W'(42);
    pau_aux_wr_idx[3]     = COEFF_W'(43);
    pau_aux_wr_data[0]    = 16'hA700;
    pau_aux_wr_data[1]    = 16'hA701;
    pau_aux_wr_data[2]    = 16'hA702;
    pau_aux_wr_data[3]    = 16'hA703;
    #1;

    if (pau_stall)
      $fatal(1, "Expected legal PAU primary-read + aux-write issue");
    tick();
    if (!pau_rd_valid || pau_aux_rd_valid)
      $fatal(1, "Expected PAU primary read response only for read/write overlap");
    if (pau_rd_data[0] !== 16'h1200 || pau_rd_data[1] !== 16'h1201 ||
        pau_rd_data[2] !== 16'h1202 || pau_rd_data[3] !== 16'h1203)
      $fatal(1, "PAU read/write overlap data mismatch");
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK7, 40, 41, 42, 43,
                       16'hA700, 16'hA701, 16'hA702, 16'hA703);

    // ------------------------------------------------------------------
    // 4) PAU-owned same-address read/write is rejected before issue.
    // ------------------------------------------------------------------
    pau_req               = 1'b1;
    pau_rd_en             = 1'b1;
    pau_rd_poly_id        = POLY_ID_S2;
    pau_rd_idx[0]         = COEFF_W'(0);
    pau_rd_lane_valid     = 4'b0001;

    pau_aux_req           = 1'b1;
    pau_aux_wr_en         = 4'b0001;
    pau_aux_wr_poly_id    = POLY_ID_S2;
    pau_aux_wr_idx[0]     = COEFF_W'(0);
    pau_aux_wr_data[0]    = 16'hBAD0;
    #1;

    if (!pau_stall)
      $fatal(1, "Expected PAU same-address read/write to stall");
    tick();
    if (pau_rd_valid || pau_aux_rd_valid || mem_fault_o)
      $fatal(1, "Illegal PAU auxiliary pairing should not issue or fault");
    clear_poly_clients();

    // ------------------------------------------------------------------
    // 5) Legal dual-read scheduling with per-client response routing.
    //    HSU is not a polynomial-memory reader, so this coverage uses
    //    PAU + Transcoder.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;

    tr_req            = 1'b1;
    tr_rd_en          = 1'b1;
    tr_rd_poly_id     = POLY_ID_A1;
    tr_rd_idx[0]      = COEFF_W'(12);
    tr_rd_idx[1]      = COEFF_W'(13);
    tr_rd_idx[2]      = COEFF_W'(14);
    tr_rd_idx[3]      = COEFF_W'(15);
    tr_rd_lane_valid  = 4'b1111;
    #1;

    if (pau_stall || hsu_stall || tr_stall)
      $fatal(1, "Expected legal dual-read issue without stalls");
    tick();

    if (!pau_rd_valid || !tr_rd_valid || hsu_rd_valid)
      $fatal(1, "Expected PAU and Transcoder read responses in the same cycle");
    if (pau_rd_poly_id_o !== POLY_W'(POLY_ID_S2) ||
        tr_rd_poly_id_o !== POLY_W'(POLY_ID_A1))
      $fatal(1, "Dual-read response routing tagged the wrong client");
    if (pau_rd_data[0] !== 16'h1200 || pau_rd_data[1] !== 16'h1201 ||
        pau_rd_data[2] !== 16'h1202 || pau_rd_data[3] !== 16'h1203)
      $fatal(1, "PAU dual-read data mismatch");
    if (tr_rd_data[0] !== 16'h6600 || tr_rd_data[1] !== 16'h6601 ||
        tr_rd_data[2] !== 16'h6602 || tr_rd_data[3] !== 16'h6603)
      $fatal(1, "Transcoder dual-read data mismatch");
    clear_poly_clients();

    // ------------------------------------------------------------------
    // 6) HSU polynomial reads are unsupported and should stall cleanly.
    // ------------------------------------------------------------------
    hsu_req           = 1'b1;
    hsu_rd_en         = 1'b1;
    hsu_rd_poly_id    = POLY_ID_S2;
    hsu_rd_idx[0]     = COEFF_W'(0);
    hsu_rd_idx[1]     = COEFF_W'(1);
    hsu_rd_idx[2]     = COEFF_W'(2);
    hsu_rd_idx[3]     = COEFF_W'(3);
    hsu_rd_lane_valid = 4'b1111;
    #1;

    if (!hsu_stall)
      $fatal(1, "HSU polynomial reads should stall; HSU reads seeds, not polynomial memory");
    tick();
    if (hsu_rd_valid || mem_fault_o)
      $fatal(1, "Unsupported HSU polynomial read should not return data or raise a memory hazard fault");
    clear_poly_clients();

    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // 7) HSU can fill the active A row buffer while PAU consumes older data.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_A0;
    hsu_wr_idx[0]  = COEFF_W'(44);
    hsu_wr_idx[1]  = COEFF_W'(45);
    hsu_wr_idx[2]  = COEFF_W'(46);
    hsu_wr_idx[3]  = COEFF_W'(47);
    hsu_wr_data[0] = 16'hA000;
    hsu_wr_data[1] = 16'hA001;
    hsu_wr_data[2] = 16'hA002;
    hsu_wr_data[3] = 16'hA003;
    #1;

    if (pau_stall || hsu_stall)
      $fatal(1, "Expected HSU A-row write to overlap legal PAU read");
    tick();
    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response during HSU row-buffer fill");
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_A0, 44, 45, 46, 47,
                       16'hA000, 16'hA001, 16'hA002, 16'hA003);

    // ------------------------------------------------------------------
    // 8) Legal dual-write scheduling across two clients.
    // ------------------------------------------------------------------
    pau_req        = 1'b1;
    pau_wr_en      = 4'b1111;
    pau_wr_poly_id = POLY_ID_WORK0;
    pau_wr_idx[0]  = COEFF_W'(8);
    pau_wr_idx[1]  = COEFF_W'(9);
    pau_wr_idx[2]  = COEFF_W'(10);
    pau_wr_idx[3]  = COEFF_W'(11);
    pau_wr_data[0] = 16'hA100;
    pau_wr_data[1] = 16'hA101;
    pau_wr_data[2] = 16'hA102;
    pau_wr_data[3] = 16'hA103;

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_WORK1;
    hsu_wr_idx[0]  = COEFF_W'(16);
    hsu_wr_idx[1]  = COEFF_W'(17);
    hsu_wr_idx[2]  = COEFF_W'(18);
    hsu_wr_idx[3]  = COEFF_W'(19);
    hsu_wr_data[0] = 16'hB200;
    hsu_wr_data[1] = 16'hB201;
    hsu_wr_data[2] = 16'hB202;
    hsu_wr_data[3] = 16'hB203;
    #1;

    if (pau_stall || hsu_stall)
      $fatal(1, "Expected legal dual-write issue without stalls");
    tick();
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK0, 8, 9, 10, 11,
                       16'hA100, 16'hA101, 16'hA102, 16'hA103);
    read_poly_with_pau(POLY_ID_WORK1, 16, 17, 18, 19,
                       16'hB200, 16'hB201, 16'hB202, 16'hB203);

    // ------------------------------------------------------------------
    // 9) Legal read/write overlap remains allowed.
    //    HSU contributes as the polynomial writer while Transcoder reads.
    // ------------------------------------------------------------------
    tr_req            = 1'b1;
    tr_rd_en          = 1'b1;
    tr_rd_poly_id     = POLY_ID_S2;
    tr_rd_idx[0]      = COEFF_W'(0);
    tr_rd_idx[1]      = COEFF_W'(1);
    tr_rd_idx[2]      = COEFF_W'(2);
    tr_rd_idx[3]      = COEFF_W'(3);
    tr_rd_lane_valid  = 4'b1111;

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_WORK2;
    hsu_wr_idx[0]  = COEFF_W'(20);
    hsu_wr_idx[1]  = COEFF_W'(21);
    hsu_wr_idx[2]  = COEFF_W'(22);
    hsu_wr_idx[3]  = COEFF_W'(23);
    hsu_wr_data[0] = 16'hC300;
    hsu_wr_data[1] = 16'hC301;
    hsu_wr_data[2] = 16'hC302;
    hsu_wr_data[3] = 16'hC303;
    #1;

    if (hsu_stall || tr_stall)
      $fatal(1, "Expected legal read/write overlap without stalls");
    tick();
    if (!tr_rd_valid)
      $fatal(1, "Expected Transcoder read response during read/write overlap");
    if (tr_rd_data[0] !== 16'h1200 || tr_rd_data[1] !== 16'h1201 ||
        tr_rd_data[2] !== 16'h1202 || tr_rd_data[3] !== 16'h1203)
      $fatal(1, "Transcoder overlap read data mismatch");
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK2, 20, 21, 22, 23,
                       16'hC300, 16'hC301, 16'hC302, 16'hC303);

    // ------------------------------------------------------------------
    // 10) Combined read+write requests still own both ports atomically.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;
    pau_wr_en         = 4'b1111;
    pau_wr_poly_id    = POLY_ID_WORK3;
    pau_wr_idx[0]     = COEFF_W'(24);
    pau_wr_idx[1]     = COEFF_W'(25);
    pau_wr_idx[2]     = COEFF_W'(26);
    pau_wr_idx[3]     = COEFF_W'(27);
    pau_wr_data[0]    = 16'hD400;
    pau_wr_data[1]    = 16'hD401;
    pau_wr_data[2]    = 16'hD402;
    pau_wr_data[3]    = 16'hD403;

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_WORK4;
    hsu_wr_idx[0]  = COEFF_W'(28);
    hsu_wr_idx[1]  = COEFF_W'(29);
    hsu_wr_idx[2]  = COEFF_W'(30);
    hsu_wr_idx[3]  = COEFF_W'(31);
    hsu_wr_data[0] = 16'hE500;
    hsu_wr_data[1] = 16'hE501;
    hsu_wr_data[2] = 16'hE502;
    hsu_wr_data[3] = 16'hE503;
    #1;

    if (pau_stall)
      $fatal(1, "Combined PAU request should own both ports");
    if (!hsu_stall)
      $fatal(1, "HSU must stall behind a combined PAU request");
    tick();
    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response for atomic combined request");
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK3, 24, 25, 26, 27,
                       16'hD400, 16'hD401, 16'hD402, 16'hD403);

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_WORK4;
    hsu_wr_idx[0]  = COEFF_W'(28);
    hsu_wr_idx[1]  = COEFF_W'(29);
    hsu_wr_idx[2]  = COEFF_W'(30);
    hsu_wr_idx[3]  = COEFF_W'(31);
    hsu_wr_data[0] = 16'hE500;
    hsu_wr_data[1] = 16'hE501;
    hsu_wr_data[2] = 16'hE502;
    hsu_wr_data[3] = 16'hE503;
    tick();
    clear_poly_clients();

    read_poly_with_pau(POLY_ID_WORK4, 28, 29, 30, 31,
                       16'hE500, 16'hE501, 16'hE502, 16'hE503);

    // ------------------------------------------------------------------
    // 11) Semantic KeyGen placement: s[j] overwritten in place with s_hat[j].
    // ------------------------------------------------------------------
    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_S1;
    hsu_wr_idx[0]  = COEFF_W'(0);
    hsu_wr_idx[1]  = COEFF_W'(1);
    hsu_wr_idx[2]  = COEFF_W'(2);
    hsu_wr_idx[3]  = COEFF_W'(3);
    hsu_wr_data[0] = 16'h5100;
    hsu_wr_data[1] = 16'h5101;
    hsu_wr_data[2] = 16'h5102;
    hsu_wr_data[3] = 16'h5103;
    tick();
    clear_poly_clients();

    pau_req        = 1'b1;
    pau_wr_en      = 4'b1111;
    pau_wr_poly_id = POLY_ID_S1;
    pau_wr_idx[0]  = COEFF_W'(0);
    pau_wr_idx[1]  = COEFF_W'(1);
    pau_wr_idx[2]  = COEFF_W'(2);
    pau_wr_idx[3]  = COEFF_W'(3);
    pau_wr_data[0] = 16'h6100;
    pau_wr_data[1] = 16'h6101;
    pau_wr_data[2] = 16'h6102;
    pau_wr_data[3] = 16'h6103;
    tick();
    clear_poly_clients();

    read_poly_with_tr(POLY_ID_S1, 0, 1, 2, 3,
                      16'h6100, 16'h6101, 16'h6102, 16'h6103);

    // ------------------------------------------------------------------
    // 12) Semantic KeyGen placement: e_i overwritten in place with e_hat_i.
    //    Final row commit lands in t[i].
    // ------------------------------------------------------------------
    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b1111;
    hsu_wr_poly_id = POLY_ID_EI;
    hsu_wr_idx[0]  = COEFF_W'(4);
    hsu_wr_idx[1]  = COEFF_W'(5);
    hsu_wr_idx[2]  = COEFF_W'(6);
    hsu_wr_idx[3]  = COEFF_W'(7);
    hsu_wr_data[0] = 16'h7200;
    hsu_wr_data[1] = 16'h7201;
    hsu_wr_data[2] = 16'h7202;
    hsu_wr_data[3] = 16'h7203;
    tick();
    clear_poly_clients();

    pau_req        = 1'b1;
    pau_wr_en      = 4'b1111;
    pau_wr_poly_id = POLY_ID_EI;
    pau_wr_idx[0]  = COEFF_W'(4);
    pau_wr_idx[1]  = COEFF_W'(5);
    pau_wr_idx[2]  = COEFF_W'(6);
    pau_wr_idx[3]  = COEFF_W'(7);
    pau_wr_data[0] = 16'h8200;
    pau_wr_data[1] = 16'h8201;
    pau_wr_data[2] = 16'h8202;
    pau_wr_data[3] = 16'h8203;
    tick();
    clear_poly_clients();

    pau_req        = 1'b1;
    pau_wr_en      = 4'b1111;
    pau_wr_poly_id = POLY_ID_T2;
    pau_wr_idx[0]  = COEFF_W'(8);
    pau_wr_idx[1]  = COEFF_W'(9);
    pau_wr_idx[2]  = COEFF_W'(10);
    pau_wr_idx[3]  = COEFF_W'(11);
    pau_wr_data[0] = 16'h9200;
    pau_wr_data[1] = 16'h9201;
    pau_wr_data[2] = 16'h9202;
    pau_wr_data[3] = 16'h9203;
    tick();
    clear_poly_clients();

    read_poly_with_tr(POLY_ID_EI, 4, 5, 6, 7,
                      16'h8200, 16'h8201, 16'h8202, 16'h8203);
    read_poly_with_tr(POLY_ID_T2, 8, 9, 10, 11,
                      16'h9200, 16'h9201, 16'h9202, 16'h9203);

    // ------------------------------------------------------------------
    // 13) Seed/protocol store uses semantic ID + beat mapping above Memory.
    // ------------------------------------------------------------------
    hsu_seed_req   = 1'b1;
    hsu_seed_we    = 1'b1;
    hsu_seed_addr  = qrem_seed_map_pkg::seed_word_addr(SEED_ID_RHO, 2'd1);
    hsu_seed_wdata = 64'h1122_3344_5566_7788;
    tr_seed_req    = 1'b1;
    tr_seed_we     = 1'b1;
    tr_seed_addr   = qrem_seed_map_pkg::seed_word_addr(SEED_ID_HEK, 2'd2);
    tr_seed_wdata  = 64'h99AA_BBCC_DDEE_FF00;
    #1;

    if (!hsu_seed_ready || !tr_seed_ready)
      $fatal(1, "Both protocol-store ports should be ready outside wipe");

    tick();
    clear_seed_clients();

    hsu_seed_req  = 1'b1;
    hsu_seed_addr = qrem_seed_map_pkg::seed_word_addr(SEED_ID_RHO, 2'd1);
    tr_seed_req   = 1'b1;
    tr_seed_addr  = qrem_seed_map_pkg::seed_word_addr(SEED_ID_HEK, 2'd2);
    tick();
    clear_seed_clients();

    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h1122_3344_5566_7788)
      $fatal(1, "RHO protocol-store readback mismatch");
    if (!tr_seed_rvalid || tr_seed_rdata !== 64'h99AA_BBCC_DDEE_FF00)
      $fatal(1, "H(ek) protocol-store readback mismatch");

    // ------------------------------------------------------------------
    // 14) Illegal cross-client same-address collisions are conservatively
    //    rejected by the scheduler before issue; the admitted request still
    //    completes deterministically without undefined memory semantics.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_lane_valid = 4'b0001;

    hsu_req        = 1'b1;
    hsu_wr_en      = 4'b0001;
    hsu_wr_poly_id = POLY_ID_S2;
    hsu_wr_idx[0]  = COEFF_W'(0);
    hsu_wr_data[0] = 16'hFACE;
    #1;

    if (pau_stall)
      $fatal(1, "Highest-priority legal request should still issue");
    if (!hsu_stall)
      $fatal(1, "Lower-priority same-address request should be filtered and stalled");
    tick();
    if (!pau_rd_valid || pau_rd_data[0] !== 16'h1200)
      $fatal(1, "Scheduler-filtered collision should preserve the winning read");
    if (mem_fault_o)
      $fatal(1, "Top-level scheduler should filter illegal pairings before wrapper faulting");
    clear_poly_clients();

    // ------------------------------------------------------------------
    // 15) Wipe blocks all users and clears both poly + protocol storage.
    // ------------------------------------------------------------------
    wipe_i = 1'b1;
    tick();
    wipe_i = 1'b0;

    if (!wipe_busy_o)
      $fatal(1, "wipe_busy_o should assert while wipe is active");
    if (hsu_seed_ready || tr_seed_ready)
      $fatal(1, "Protocol-store ports must report not-ready during wipe");

    wait (wipe_done_o == 1'b1);
    tick();
    if (wipe_busy_o)
      $fatal(1, "wipe_busy_o should deassert after wipe completes");

    read_poly_with_pau(POLY_ID_S1, 0, 1, 2, 3,
                       16'h0000, 16'h0000, 16'h0000, 16'h0000);
    read_poly_with_pau(POLY_ID_EI, 4, 5, 6, 7,
                       16'h0000, 16'h0000, 16'h0000, 16'h0000);
    read_poly_with_pau(POLY_ID_T2, 8, 9, 10, 11,
                       16'h0000, 16'h0000, 16'h0000, 16'h0000);

    hsu_seed_req  = 1'b1;
    hsu_seed_addr = qrem_seed_map_pkg::seed_word_addr(SEED_ID_RHO, 2'd1);
    tick();
    clear_seed_clients();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h0)
      $fatal(1, "Protocol-store wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
