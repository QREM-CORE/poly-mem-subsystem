`timescale 1ns/1ps

import qrem_global_pkg::*;
import qrem_mem_map_pkg::*;
import qrem_seed_map_pkg::*;

module mem_frontend_top_tb;
  // Integration TB for the v0.9 memory subsystem.
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
  localparam int SEED_IDX_W = $clog2(SEED_BEATS);

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

  logic                           hsu_hash_ek_read_en;

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
  seed_id_e                       hsu_seed_id;
  logic [SEED_IDX_W-1:0]          hsu_seed_idx;
  logic [SEED_W-1:0]              hsu_seed_wdata;
  logic                           hsu_seed_ready;
  logic                           hsu_seed_rvalid;
  logic [SEED_W-1:0]              hsu_seed_rdata;

  logic                           tr_seed_req;
  logic                           tr_seed_we;
  seed_id_e                       tr_seed_id;
  logic [SEED_IDX_W-1:0]          tr_seed_idx;
  logic [SEED_W-1:0]              tr_seed_wdata;
  logic                           tr_seed_ready;
  logic                           tr_seed_rvalid;
  logic [SEED_W-1:0]              tr_seed_rdata;

  poly_mem_subsystem #(
    .NUM_POLYS  (NUM_POLYS),
    .NCOEFF     (NCOEFF),
    .W          (W),
    .COEFF_W    (W),
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
    .hsu_hash_ek_read_en(hsu_hash_ek_read_en),
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
    .hsu_seed_id(hsu_seed_id),
    .hsu_seed_idx(hsu_seed_idx),
    .hsu_seed_wdata(hsu_seed_wdata),
    .hsu_seed_ready(hsu_seed_ready),
    .hsu_seed_rvalid(hsu_seed_rvalid),
    .hsu_seed_rdata(hsu_seed_rdata),
    .tr_seed_req(tr_seed_req),
    .tr_seed_we(tr_seed_we),
    .tr_seed_id(tr_seed_id),
    .tr_seed_idx(tr_seed_idx),
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

      hsu_hash_ek_read_en = 1'b0;

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
      hsu_seed_id    = SEED_ID_D;
      hsu_seed_idx   = '0;
      hsu_seed_wdata = '0;
      tr_seed_req    = 1'b0;
      tr_seed_we     = 1'b0;
      tr_seed_id     = SEED_ID_D;
      tr_seed_idx    = '0;
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

  task automatic read_poly_with_hsu_hash_ek(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] e0, input logic [W-1:0] e1,
    input logic [W-1:0] e2, input logic [W-1:0] e3
  );
    begin
      hsu_hash_ek_read_en = 1'b1;
      hsu_req             = 1'b1;
      hsu_rd_en           = 1'b1;
      hsu_rd_poly_id      = POLY_W'(poly_id);
      hsu_rd_idx[0]       = COEFF_W'(idx0);
      hsu_rd_idx[1]       = COEFF_W'(idx1);
      hsu_rd_idx[2]       = COEFF_W'(idx2);
      hsu_rd_idx[3]       = COEFF_W'(idx3);
      hsu_rd_lane_valid   = 4'b1111;
      tick();
      if (!hsu_rd_valid)
        $fatal(1, "Expected authorized HSU hash-ek T-slot read response");
      if (hsu_rd_poly_id_o !== POLY_W'(poly_id))
        $fatal(1, "HSU hash-ek read tag mismatch");
      if (hsu_rd_data[0] !== e0 || hsu_rd_data[1] !== e1 ||
          hsu_rd_data[2] !== e2 || hsu_rd_data[3] !== e3)
        $fatal(1, "HSU hash-ek T-slot read mismatch");
      clear_poly_clients();
    end
  endtask

  task automatic expect_hsu_hash_ek_read_reject(
    input int poly_id
  );
    begin
      hsu_hash_ek_read_en = 1'b1;
      hsu_req             = 1'b1;
      hsu_rd_en           = 1'b1;
      hsu_rd_poly_id      = POLY_W'(poly_id);
      hsu_rd_idx[0]       = COEFF_W'(0);
      hsu_rd_idx[1]       = COEFF_W'(1);
      hsu_rd_idx[2]       = COEFF_W'(2);
      hsu_rd_idx[3]       = COEFF_W'(3);
      hsu_rd_lane_valid   = 4'b1111;
      #1;

      if (!hsu_stall)
        $fatal(1, "Expected unauthorized HSU hash-ek poly-id read to stall");
      tick();
      if (hsu_rd_valid || mem_fault_o)
        $fatal(1, "Rejected HSU hash-ek read should not return data or fault");
      clear_poly_clients();
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_all();
    repeat (2) tick();
    if (hsu_seed_ready || tr_seed_ready ||
        hsu_seed_rvalid || tr_seed_rvalid ||
        hsu_seed_rdata !== '0 || tr_seed_rdata !== '0)
      $fatal(1, "Seed ports must be not-ready and data-zero during reset");

    rst = 1'b0;
    tick();
    if (hsu_seed_rvalid || tr_seed_rvalid ||
        hsu_seed_rdata !== '0 || tr_seed_rdata !== '0)
      $fatal(1, "Seed read data should be zero when rvalid is low");

    $display("Scenario 0: Reset and Package Sanity Checks... DONE");

    // Prime data used by scheduler and overlap checks.
    prime_poly_with_pau(POLY_ID_S2, 0, 1, 2, 3, 16'h1200, 16'h1201, 16'h1202, 16'h1203);
    prime_poly_with_pau(POLY_ID_A1, 12, 13, 14, 15, 16'h6600, 16'h6601, 16'h6602, 16'h6603);

    // ------------------------------------------------------------------
    // 1) PAU-owned legal dual-read using primary + auxiliary descriptors.
    // ------------------------------------------------------------------
    $display("Scenario 1: PAU Primary + Aux Legal Dual-Read...");
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
    $display("Scenario 1: PAU Primary + Aux Legal Dual-Read... PASS");

    // ------------------------------------------------------------------
    // 2) PAU-owned legal dual-write using both internal ports.
    // ------------------------------------------------------------------
    $display("Scenario 2: PAU Primary + Aux Legal Dual-Write...");
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
    $display("Scenario 2: PAU Primary + Aux Legal Dual-Write... PASS");

    // ------------------------------------------------------------------
    // 3) PAU-owned legal read/write overlap.
    // ------------------------------------------------------------------
    $display("Scenario 3: PAU Primary-Read + Aux-Write Overlap...");
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
    $display("Scenario 3: PAU Primary-Read + Aux-Write Overlap... PASS");

    // ------------------------------------------------------------------
    // 4) PAU-owned same-address read/write is rejected before issue.
    // ------------------------------------------------------------------
    $display("Scenario 4: PAU Primary-Read + Aux-Write Conflict (Stall)...");
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
    $display("Scenario 4: PAU Primary-Read + Aux-Write Conflict (Stall)... PASS");

    // ------------------------------------------------------------------
    // 5) Legal dual-read scheduling with per-client response routing.
    //    General dual-read coverage uses PAU + Transcoder; the constrained
    //    HSU hash-ek T-slot read path is covered below.
    // ------------------------------------------------------------------
    $display("Scenario 5: PAU + TR Dual-Read Concurrent Issue...");
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
    $display("Scenario 5: PAU + TR Dual-Read Concurrent Issue... PASS");

    // ------------------------------------------------------------------
    // 6) HSU polynomial reads stall unless the hash-ek T-slot authorization
    //    is active.
    // ------------------------------------------------------------------
    $display("Scenario 6: HSU Poly-Read Blocking (Unauthorized)...");
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
      $fatal(1, "HSU polynomial reads should stall without hash-ek authorization");
    tick();
    if (hsu_rd_valid || mem_fault_o)
      $fatal(1, "Unauthorized HSU polynomial read should not return data or fault");
    clear_poly_clients();
    $display("Scenario 6: HSU Poly-Read Blocking (Unauthorized)... PASS");

    // ------------------------------------------------------------------
    // 7) KG_HSU_HASH_EK authorizes HSU/Gearbox reads from T0..T3 only.
    // ------------------------------------------------------------------
    $display("Scenario 7: HSU Hash-EK T-Slot Authorized Reads...");
    prime_poly_with_pau(POLY_ID_T0, 48, 49, 50, 51,
                        16'h9000, 16'h9001, 16'h9002, 16'h9003);
    prime_poly_with_pau(POLY_ID_T1, 52, 53, 54, 55,
                        16'h9100, 16'h9101, 16'h9102, 16'h9103);
    prime_poly_with_pau(POLY_ID_T2, 56, 57, 58, 59,
                        16'h9204, 16'h9205, 16'h9206, 16'h9207);
    prime_poly_with_pau(POLY_ID_T3, 60, 61, 62, 63,
                        16'h9300, 16'h9301, 16'h9302, 16'h9303);

    read_poly_with_hsu_hash_ek(POLY_ID_T0, 48, 49, 50, 51,
                               16'h9000, 16'h9001, 16'h9002, 16'h9003);
    read_poly_with_hsu_hash_ek(POLY_ID_T1, 52, 53, 54, 55,
                               16'h9100, 16'h9101, 16'h9102, 16'h9103);
    read_poly_with_hsu_hash_ek(POLY_ID_T2, 56, 57, 58, 59,
                               16'h9204, 16'h9205, 16'h9206, 16'h9207);
    read_poly_with_hsu_hash_ek(POLY_ID_T3, 60, 61, 62, 63,
                               16'h9300, 16'h9301, 16'h9302, 16'h9303);
    $display("Scenario 7: HSU Hash-EK T-Slot Authorized Reads... PASS");

    // ------------------------------------------------------------------
    // 8) Hash-ek authorization does not make HSU a general poly reader.
    // ------------------------------------------------------------------
    $display("Scenario 8: HSU Hash-EK Range Constraints...");
    expect_hsu_hash_ek_read_reject(POLY_ID_S2);
    expect_hsu_hash_ek_read_reject(POLY_ID_EI);
    expect_hsu_hash_ek_read_reject(POLY_ID_A0);
    expect_hsu_hash_ek_read_reject(POLY_ID_WORK0);
    $display("Scenario 8: HSU Hash-EK Range Constraints... PASS");

    // ------------------------------------------------------------------
    // 9) HSU read/write mixtures remain rejected during hash-ek readout.
    // ------------------------------------------------------------------
    $display("Scenario 9: HSU Hash-EK Combined R+W Rejection...");
    hsu_hash_ek_read_en = 1'b1;
    hsu_req             = 1'b1;
    hsu_rd_en           = 1'b1;
    hsu_rd_poly_id      = POLY_W'(POLY_ID_T0);
    hsu_rd_idx[0]       = COEFF_W'(48);
    hsu_rd_lane_valid   = 4'b0001;
    hsu_wr_en           = 4'b0001;
    hsu_wr_poly_id      = POLY_W'(POLY_ID_WORK0);
    hsu_wr_idx[0]       = COEFF_W'(64);
    hsu_wr_data[0]      = 16'hBAD1;
    #1;

    if (!hsu_stall)
      $fatal(1, "Expected mixed HSU hash-ek read/write request to stall");
    tick();
    if (hsu_rd_valid || mem_fault_o)
      $fatal(1, "Rejected mixed HSU hash-ek request should not return data or fault");
    clear_poly_clients();
    $display("Scenario 9: HSU Hash-EK Combined R+W Rejection... PASS");

    // ------------------------------------------------------------------
    // 10) Authorized HSU T-slot read can route as the second scheduled read.
    // ------------------------------------------------------------------
    $display("Scenario 10: PAU + HSU Hash-EK Dual-Read Issue...");
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;

    hsu_hash_ek_read_en = 1'b1;
    hsu_req             = 1'b1;
    hsu_rd_en           = 1'b1;
    hsu_rd_poly_id      = POLY_W'(POLY_ID_T0);
    hsu_rd_idx[0]       = COEFF_W'(48);
    hsu_rd_idx[1]       = COEFF_W'(49);
    hsu_rd_idx[2]       = COEFF_W'(50);
    hsu_rd_idx[3]       = COEFF_W'(51);
    hsu_rd_lane_valid   = 4'b1111;
    #1;

    if (pau_stall || hsu_stall)
      $fatal(1, "Expected legal PAU + authorized HSU dual-read issue");
    tick();
    if (!pau_rd_valid || !hsu_rd_valid)
      $fatal(1, "Expected PAU and authorized HSU read responses together");
    if (hsu_rd_poly_id_o !== POLY_W'(POLY_ID_T0) ||
        hsu_rd_data[0] !== 16'h9000 || hsu_rd_data[1] !== 16'h9001 ||
        hsu_rd_data[2] !== 16'h9002 || hsu_rd_data[3] !== 16'h9003)
      $fatal(1, "Authorized HSU p1 read routing mismatch");
    clear_poly_clients();
    $display("Scenario 10: PAU + HSU Hash-EK Dual-Read Issue... PASS");

    // ------------------------------------------------------------------
    // 11) HSU can fill the active A row buffer while PAU consumes older data.
    // ------------------------------------------------------------------
    $display("Scenario 11: PAU Read + HSU Write Overlap Issue...");
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
    $display("Scenario 11: PAU Read + HSU Write Overlap Issue... PASS");

    // ------------------------------------------------------------------
    // 12) Legal dual-write scheduling across two clients.
    // ------------------------------------------------------------------
    $display("Scenario 12: PAU + HSU Dual-Write Issue...");
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
    $display("Scenario 12: PAU + HSU Dual-Write Issue... PASS");

    // ------------------------------------------------------------------
    // 13) Legal read/write overlap remains allowed.
    //    HSU contributes as the polynomial writer while Transcoder reads.
    // ------------------------------------------------------------------
    $display("Scenario 13: TR Read + HSU Write Overlap Issue...");
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
    $display("Scenario 13: TR Read + HSU Write Overlap Issue... PASS");

    // ------------------------------------------------------------------
    // 14) Combined read+write requests still own both ports atomically.
    // ------------------------------------------------------------------
    $display("Scenario 14: PAU Atomic Combined R+W vs HSU...");
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

    tick();
    $display("Scenario 14: PAU Atomic Combined R+W vs HSU... PASS");

    // ------------------------------------------------------------------
    // 15) Illegal PAU primary combined read/write to the same address.
    //     This differs from test 4: primary+aux illegal pairings are
    //     scheduler-filtered before issue, but a primary combined request
    //     owns both wrapper ports atomically. The observed Memory behavior is
    //     PAU stall, no read response, and MEM_FAULT_RW_SAME_ADDR code 3'b001.
    // ------------------------------------------------------------------
    $display("Scenario 15: PAU Combined Same-Addr Fault (3'b001)...");
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S2;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_lane_valid = 4'b0001;
    pau_wr_en         = 4'b0001;
    pau_wr_poly_id    = POLY_ID_S2;
    pau_wr_idx[0]     = COEFF_W'(0);
    pau_wr_data[0]    = 16'hBAD2;
    #1;

    if (!pau_stall)
      $fatal(1, "Illegal PAU primary combined same-address request should stall");
    if (pau_rd_valid || pau_aux_rd_valid)
      $fatal(1, "Illegal PAU primary combined same-address request should not respond early");
    tick();
    if (pau_rd_valid || pau_aux_rd_valid)
      $fatal(1, "Illegal PAU primary combined same-address request should not return data");
    if (!mem_fault_o || mem_fault_code_o !== 3'b001)
      $fatal(1, "Expected PAU primary combined same-address fault code 3'b001");
    clear_poly_clients();
    tick();
    if (mem_fault_o || mem_fault_code_o !== 3'b000)
      $fatal(1, "PAU primary combined same-address fault should clear after request removal");

    read_poly_with_pau(POLY_ID_S2, 0, 1, 2, 3,
                       16'h1200, 16'h1201, 16'h1202, 16'h1203);
    $display("Scenario 15: PAU Combined Same-Addr Fault (3'b001)... PASS");

    // ------------------------------------------------------------------
    // 16) Semantic KeyGen placement: s[j] overwritten in place with s_hat[j].
    // ------------------------------------------------------------------
    $display("Scenario 16: Semantic S-Slot In-Place Overwrite...");
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
    $display("Scenario 16: Semantic S-Slot In-Place Overwrite... PASS");

    // ------------------------------------------------------------------
    // 17) Semantic KeyGen placement: e_i overwritten in place with e_hat_i.
    //    Final row commit lands in t[i].
    // ------------------------------------------------------------------
    $display("Scenario 17: Semantic E-Slot Overwrite + T-Slot Commit...");
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
    $display("Scenario 17: Semantic E-Slot Overwrite + T-Slot Commit... PASS");

    // ------------------------------------------------------------------
    // 18) Seed/protocol store uses semantic ID + beat mapping at Memory.
    // ------------------------------------------------------------------
    $display("Scenario 18: Seed/Protocol Store Dual-Port Concurrent Access...");
    hsu_seed_req   = 1'b1;
    hsu_seed_we    = 1'b1;
    hsu_seed_id    = SEED_ID_RHO;
    hsu_seed_idx   = 2'd1;
    hsu_seed_wdata = 64'h1122_3344_5566_7788;
    tr_seed_req    = 1'b1;
    tr_seed_we     = 1'b1;
    tr_seed_id     = SEED_ID_HEK;
    tr_seed_idx    = 2'd2;
    tr_seed_wdata  = 64'h99AA_BBCC_DDEE_FF00;
    #1;

    if (!hsu_seed_ready || !tr_seed_ready)
      $fatal(1, "Both protocol-store ports should be ready outside wipe");

    tick();
    clear_seed_clients();

    hsu_seed_req  = 1'b1;
    hsu_seed_id   = SEED_ID_RHO;
    hsu_seed_idx  = 2'd1;
    tr_seed_req   = 1'b1;
    tr_seed_id    = SEED_ID_HEK;
    tr_seed_idx   = 2'd2;
    tick();
    clear_seed_clients();

    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h1122_3344_5566_7788)
      $fatal(1, "RHO protocol-store readback mismatch");
    if (!tr_seed_rvalid || tr_seed_rdata !== 64'h99AA_BBCC_DDEE_FF00)
      $fatal(1, "H(ek) protocol-store readback mismatch");
    $display("Scenario 18: Seed/Protocol Store Dual-Port Concurrent Access... PASS");

    // ------------------------------------------------------------------
    // 19) Illegal cross-client same-address collisions are conservatively
    //    rejected by the scheduler before issue; the admitted request still
    //    completes deterministically without undefined memory semantics.
    // ------------------------------------------------------------------
    $display("Scenario 19: Inter-Client Collision Scheduler Filtering...");
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
    $display("Scenario 19: Inter-Client Collision Scheduler Filtering... PASS");

    // ------------------------------------------------------------------
    // 20) Wipe blocks all users and clears both poly + protocol storage.
    // ------------------------------------------------------------------
    $display("Scenario 20: Security Wipe Blocking & Clearance...");
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
    hsu_seed_id   = SEED_ID_RHO;
    hsu_seed_idx  = 2'd1;
    tick();
    clear_seed_clients();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h0)
      $fatal(1, "Protocol-store wipe failed");
    $display("Scenario 20: Security Wipe Blocking & Clearance... PASS");

    // ------------------------------------------------------------------
    // 21) Intra-request bank collision (Skewed Mapping).
    //     Indices 0 and 85 both hit Bank 0 under the bit-pair-sum mapping.
    //     A single vector request with these indices must stall.
    // ------------------------------------------------------------------
    $display("Scenario 21: Intra-Request Bank Collision (Skewed mapping: 0, 85)...");
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S0;
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(85); // binary 01010101 -> sum=4 -> bank 0
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;
    #1;

    if (!pau_stall)
      $fatal(1, "Expected single-vector bank conflict (0 vs 85) to stall");
    tick();
    if (pau_rd_valid || mem_fault_o)
      $fatal(1, "Rejected bank-conflict request should not return data or fault top-level");
    clear_poly_clients();
    $display("Scenario 21: Intra-Request Bank Collision (Skewed mapping: 0, 85)... PASS");

    $display("ALL TESTCASES PASSED");
    $finish;
  end

endmodule
