`timescale 1ns/1ps

module mem_frontend_top_tb;
  // Integration TB for the v0.75 memory subsystem.
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
  logic wipe_done_o;

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
    .wipe_done_o(wipe_done_o),
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

  task automatic prime_poly(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      pau_req           = 1'b1;
      pau_wr_en         = 4'b1111;
      pau_wr_poly_id    = POLY_W'(poly_id);
      pau_wr_idx[0]     = COEFF_W'(idx0);
      pau_wr_idx[1]     = COEFF_W'(idx1);
      pau_wr_idx[2]     = COEFF_W'(idx2);
      pau_wr_idx[3]     = COEFF_W'(idx3);
      pau_wr_data[0]    = d0;
      pau_wr_data[1]    = d1;
      pau_wr_data[2]    = d2;
      pau_wr_data[3]    = d3;
      tick();
      clear_poly_clients();
    end
  endtask

  task automatic check_pau_read(
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

  initial begin
    rst = 1'b1;
    clear_all();
    repeat (2) tick();
    rst = 1'b0;
    tick();

    // ------------------------------------------------------------------
    // Prime data used by later overlap checks.
    // ------------------------------------------------------------------
    prime_poly(2, 0, 1, 2, 3, 16'h1200, 16'h1201, 16'h1202, 16'h1203);
    prime_poly(6, 12, 13, 14, 15, 16'h6600, 16'h6601, 16'h6602, 16'h6603);

    // ------------------------------------------------------------------
    // 1) CWM-like overlap: PAU read-only + HSU write-only in same cycle.
    //    Both should be accepted because read uses Port A and write uses
    //    Port B on the shared banked polynomial memory.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_W'(2);
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;

    hsu_req           = 1'b1;
    hsu_wr_en         = 4'b1111;
    hsu_wr_poly_id    = POLY_W'(5);
    hsu_wr_idx[0]     = COEFF_W'(8);
    hsu_wr_idx[1]     = COEFF_W'(9);
    hsu_wr_idx[2]     = COEFF_W'(10);
    hsu_wr_idx[3]     = COEFF_W'(11);
    hsu_wr_data[0]    = 16'h5000;
    hsu_wr_data[1]    = 16'h5001;
    hsu_wr_data[2]    = 16'h5002;
    hsu_wr_data[3]    = 16'h5003;
    #1;

    if (pau_stall)
      $fatal(1, "PAU read-only request should not stall during HSU write overlap");
    if (hsu_stall)
      $fatal(1, "HSU write-only request should overlap with PAU read-only request");

    tick();

    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response during CWM-like overlap");
    if (pau_rd_data[0] !== 16'h1200 || pau_rd_data[1] !== 16'h1201 ||
        pau_rd_data[2] !== 16'h1202 || pau_rd_data[3] !== 16'h1203)
      $fatal(1, "PAU overlap read data mismatch");
    clear_poly_clients();

    check_pau_read(5, 8, 9, 10, 11, 16'h5000, 16'h5001, 16'h5002, 16'h5003);

    // ------------------------------------------------------------------
    // 2) Lower-priority overlap still works across planes:
    //    HSU read-only + Transcoder write-only in same cycle.
    // ------------------------------------------------------------------
    hsu_req           = 1'b1;
    hsu_rd_en         = 1'b1;
    hsu_rd_poly_id    = POLY_W'(6);
    hsu_rd_idx[0]     = COEFF_W'(12);
    hsu_rd_idx[1]     = COEFF_W'(13);
    hsu_rd_idx[2]     = COEFF_W'(14);
    hsu_rd_idx[3]     = COEFF_W'(15);
    hsu_rd_lane_valid = 4'b1111;

    tr_req            = 1'b1;
    tr_wr_en          = 4'b1111;
    tr_wr_poly_id     = POLY_W'(7);
    tr_wr_idx[0]      = COEFF_W'(4);
    tr_wr_idx[1]      = COEFF_W'(5);
    tr_wr_idx[2]      = COEFF_W'(6);
    tr_wr_idx[3]      = COEFF_W'(7);
    tr_wr_data[0]     = 16'h7000;
    tr_wr_data[1]     = 16'h7001;
    tr_wr_data[2]     = 16'h7002;
    tr_wr_data[3]     = 16'h7003;
    #1;

    if (hsu_stall)
      $fatal(1, "HSU read-only request should not stall during Transcoder write overlap");
    if (tr_stall)
      $fatal(1, "Transcoder write-only request should overlap with HSU read-only request");

    tick();

    if (!hsu_rd_valid)
      $fatal(1, "Expected HSU read response during overlap");
    if (hsu_rd_data[0] !== 16'h6600 || hsu_rd_data[1] !== 16'h6601 ||
        hsu_rd_data[2] !== 16'h6602 || hsu_rd_data[3] !== 16'h6603)
      $fatal(1, "HSU overlap read data mismatch");
    clear_poly_clients();

    check_pau_read(7, 4, 5, 6, 7, 16'h7000, 16'h7001, 16'h7002, 16'h7003);

    // ------------------------------------------------------------------
    // 3) NTT-like PAU combined request owns both planes.
    //    HSU write-only must stall even though the write plane exists,
    //    because the combined PAU request is treated atomically.
    // ------------------------------------------------------------------
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_W'(2);
    pau_rd_idx[0]     = COEFF_W'(0);
    pau_rd_idx[1]     = COEFF_W'(1);
    pau_rd_idx[2]     = COEFF_W'(2);
    pau_rd_idx[3]     = COEFF_W'(3);
    pau_rd_lane_valid = 4'b1111;
    pau_wr_en         = 4'b1111;
    pau_wr_poly_id    = POLY_W'(8);
    pau_wr_idx[0]     = COEFF_W'(16);
    pau_wr_idx[1]     = COEFF_W'(17);
    pau_wr_idx[2]     = COEFF_W'(18);
    pau_wr_idx[3]     = COEFF_W'(19);
    pau_wr_data[0]    = 16'h8A00;
    pau_wr_data[1]    = 16'h8A01;
    pau_wr_data[2]    = 16'h8A02;
    pau_wr_data[3]    = 16'h8A03;

    hsu_req           = 1'b1;
    hsu_wr_en         = 4'b1111;
    hsu_wr_poly_id    = POLY_W'(9);
    hsu_wr_idx[0]     = COEFF_W'(20);
    hsu_wr_idx[1]     = COEFF_W'(21);
    hsu_wr_idx[2]     = COEFF_W'(22);
    hsu_wr_idx[3]     = COEFF_W'(23);
    hsu_wr_data[0]    = 16'h9B00;
    hsu_wr_data[1]    = 16'h9B01;
    hsu_wr_data[2]    = 16'h9B02;
    hsu_wr_data[3]    = 16'h9B03;
    #1;

    if (pau_stall)
      $fatal(1, "PAU combined read/write request should own both planes");
    if (!hsu_stall)
      $fatal(1, "HSU must stall behind a combined PAU request");

    tick();

    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response during NTT-like combined request");
    clear_poly_clients();
    check_pau_read(8, 16, 17, 18, 19, 16'h8A00, 16'h8A01, 16'h8A02, 16'h8A03);

    // HSU retries after the PAU-owned cycle.
    hsu_req           = 1'b1;
    hsu_wr_en         = 4'b1111;
    hsu_wr_poly_id    = POLY_W'(9);
    hsu_wr_idx[0]     = COEFF_W'(20);
    hsu_wr_idx[1]     = COEFF_W'(21);
    hsu_wr_idx[2]     = COEFF_W'(22);
    hsu_wr_idx[3]     = COEFF_W'(23);
    hsu_wr_data[0]    = 16'h9B00;
    hsu_wr_data[1]    = 16'h9B01;
    hsu_wr_data[2]    = 16'h9B02;
    hsu_wr_data[3]    = 16'h9B03;
    tick();
    clear_poly_clients();

    check_pau_read(9, 20, 21, 22, 23, 16'h9B00, 16'h9B01, 16'h9B02, 16'h9B03);

    // ------------------------------------------------------------------
    // 4) Seed/protocol store: HSU and Transcoder can both use it in the same
    //    cycle because the store is now explicitly dual-port.
    // ------------------------------------------------------------------
    hsu_seed_req   = 1'b1;
    hsu_seed_we    = 1'b1;
    hsu_seed_addr  = SEED_AW'(12);
    hsu_seed_wdata = 64'h1122_3344_5566_7788;
    tr_seed_req    = 1'b1;
    tr_seed_we     = 1'b1;
    tr_seed_addr   = SEED_AW'(16);
    tr_seed_wdata  = 64'h99AA_BBCC_DDEE_FF00;
    #1;

    if (!hsu_seed_ready || !tr_seed_ready)
      $fatal(1, "Both seed ports should be ready outside wipe");

    tick();
    clear_seed_clients();

    hsu_seed_req  = 1'b1;
    hsu_seed_addr = SEED_AW'(12);
    tr_seed_req   = 1'b1;
    tr_seed_addr  = SEED_AW'(16);
    tick();
    clear_seed_clients();

    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h1122_3344_5566_7788)
      $fatal(1, "HSU seed-port readback mismatch");
    if (!tr_seed_rvalid || tr_seed_rdata !== 64'h99AA_BBCC_DDEE_FF00)
      $fatal(1, "Transcoder seed-port readback mismatch");

    // ------------------------------------------------------------------
    // 5) Wipe blocks all users and clears both poly + seed storage.
    // ------------------------------------------------------------------
    wipe_i = 1'b1;
    tick();
    wipe_i = 1'b0;

    if (hsu_seed_ready || tr_seed_ready)
      $fatal(1, "Seed ports must report not-ready during wipe");

    wait (wipe_done_o == 1'b1);
    tick();

    check_pau_read(5, 8, 9, 10, 11, 16'h0000, 16'h0000, 16'h0000, 16'h0000);

    hsu_seed_req  = 1'b1;
    hsu_seed_addr = SEED_AW'(12);
    tick();
    clear_seed_clients();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h0)
      $fatal(1, "Seed wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
