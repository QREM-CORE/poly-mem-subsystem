`timescale 1ns/1ps

module poly_mem_tb;

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 32;
  localparam int SEED_W     = 64;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_W    = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);

  logic clk, rst;
  logic wipe_i, wipe_busy_o, wipe_done_o;
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

  task automatic clear_all;
    begin
      wipe_i            = 1'b0;
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
      hsu_seed_req      = 1'b0;
      hsu_seed_we       = 1'b0;
      hsu_seed_addr     = '0;
      hsu_seed_wdata    = '0;
      tr_seed_req       = 1'b0;
      tr_seed_we        = 1'b0;
      tr_seed_addr      = '0;
      tr_seed_wdata     = '0;
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_all();
    repeat (2) tick();
    rst = 1'b0;
    tick();

    // 1) PAU write one vector row
    pau_req           = 1'b1;
    pau_wr_en         = 4'b1111;
    pau_wr_poly_id    = POLY_W'(3);
    pau_wr_idx[0]     = COEFF_W'(8);
    pau_wr_idx[1]     = COEFF_W'(9);
    pau_wr_idx[2]     = COEFF_W'(10);
    pau_wr_idx[3]     = COEFF_W'(11);
    pau_wr_data[0]    = 16'h3000;
    pau_wr_data[1]    = 16'h3001;
    pau_wr_data[2]    = 16'h3002;
    pau_wr_data[3]    = 16'h3003;
    tick();
    clear_all();

    // 2) PAU read back vector row
    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_W'(3);
    pau_rd_idx[0]     = COEFF_W'(8);
    pau_rd_idx[1]     = COEFF_W'(9);
    pau_rd_idx[2]     = COEFF_W'(10);
    pau_rd_idx[3]     = COEFF_W'(11);
    pau_rd_lane_valid = 4'b1111;
    tick();

    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response from poly_mem_subsystem");
    if (pau_rd_data[0] !== 16'h3000 || pau_rd_data[1] !== 16'h3001 ||
        pau_rd_data[2] !== 16'h3002 || pau_rd_data[3] !== 16'h3003)
      $fatal(1, "PAU vector readback mismatch");
    clear_all();

    // 3) Dual-port seed store smoke test
    hsu_seed_req   = 1'b1;
    hsu_seed_we    = 1'b1;
    hsu_seed_addr  = SEED_AW'(2);
    hsu_seed_wdata = 64'hFACE_CAFE_1234_5678;
    tr_seed_req    = 1'b1;
    tr_seed_we     = 1'b1;
    tr_seed_addr   = SEED_AW'(5);
    tr_seed_wdata  = 64'h0123_4567_89AB_CDEF;
    tick();
    clear_all();

    hsu_seed_req   = 1'b1;
    hsu_seed_addr  = SEED_AW'(2);
    tr_seed_req    = 1'b1;
    tr_seed_addr   = SEED_AW'(5);
    tick();
    clear_all();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'hFACE_CAFE_1234_5678)
      $fatal(1, "HSU seed readback mismatch");
    if (!tr_seed_rvalid || tr_seed_rdata !== 64'h0123_4567_89AB_CDEF)
      $fatal(1, "Transcoder seed readback mismatch");

    // 4) Wipe clears both memories
    wipe_i = 1'b1;
    tick();
    wipe_i = 1'b0;
    if (!wipe_busy_o)
      $fatal(1, "Expected wipe_busy_o to assert during wipe");
    wait (wipe_done_o == 1'b1);
    tick();
    if (wipe_busy_o)
      $fatal(1, "Expected wipe_busy_o to drop after wipe completion");

    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_W'(3);
    pau_rd_idx[0]     = COEFF_W'(8);
    pau_rd_idx[1]     = COEFF_W'(9);
    pau_rd_idx[2]     = COEFF_W'(10);
    pau_rd_idx[3]     = COEFF_W'(11);
    pau_rd_lane_valid = 4'b1111;
    tick();

    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response after wipe");
    if (pau_rd_data[0] !== 16'h0000 || pau_rd_data[1] !== 16'h0000 ||
        pau_rd_data[2] !== 16'h0000 || pau_rd_data[3] !== 16'h0000)
      $fatal(1, "Polynomial wipe failed");
    clear_all();

    hsu_seed_req  = 1'b1;
    hsu_seed_addr = SEED_AW'(2);
    tick();
    clear_all();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h0)
      $fatal(1, "Seed wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
