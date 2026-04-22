`timescale 1ns/1ps

import qrem_global_pkg::*;
import qrem_mem_map_pkg::*;
import qrem_seed_map_pkg::*;

module poly_mem_tb;

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 32;
  localparam int SEED_W     = 64;
  localparam int COEFF_DATA_W = 12;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_ADDR_W = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);
  localparam int SEED_IDX_W = $clog2(SEED_BEATS);

  logic clk, rst;
  logic wipe_i, wipe_busy_o, wipe_done_o;
  logic mem_fault_o;
  logic [2:0] mem_fault_code_o;

  logic                           pau_req;
  logic                           pau_rd_en;
  logic [POLY_W-1:0]              pau_rd_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]        pau_rd_idx;
  logic [3:0]                     pau_rd_lane_valid;
  logic [3:0]                     pau_wr_en;
  logic [POLY_W-1:0]              pau_wr_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]   pau_wr_idx;
  logic [3:0][COEFF_DATA_W-1:0]   pau_wr_data;
  logic                           pau_rd_valid;
  logic [POLY_W-1:0]              pau_rd_poly_id_o;
  logic [3:0][COEFF_ADDR_W-1:0]        pau_rd_idx_o;
  logic [3:0]                     pau_rd_lane_valid_o;
  logic [3:0][COEFF_DATA_W-1:0]   pau_rd_data;
  logic                           pau_stall;

  logic                           pau_aux_req;
  logic                           pau_aux_rd_en;
  logic [POLY_W-1:0]              pau_aux_rd_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]        pau_aux_rd_idx;
  logic [3:0]                     pau_aux_rd_lane_valid;
  logic [3:0]                     pau_aux_wr_en;
  logic [POLY_W-1:0]              pau_aux_wr_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]   pau_aux_wr_idx;
  logic [3:0][COEFF_DATA_W-1:0]   pau_aux_wr_data;
  logic                           pau_aux_rd_valid;
  logic [POLY_W-1:0]              pau_aux_rd_poly_id_o;
  logic [3:0][COEFF_ADDR_W-1:0]        pau_aux_rd_idx_o;
  logic [3:0]                     pau_aux_rd_lane_valid_o;
  logic [3:0][COEFF_DATA_W-1:0]   pau_aux_rd_data;

  logic                           hsu_hash_ek_read_en;

  logic                           hsu_req;
  logic                           hsu_rd_en;
  logic [POLY_W-1:0]              hsu_rd_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]        hsu_rd_idx;
  logic [3:0]                     hsu_rd_lane_valid;
  logic [3:0]                     hsu_wr_en;
  logic [POLY_W-1:0]              hsu_wr_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]   hsu_wr_idx;
  logic [3:0][COEFF_DATA_W-1:0]   hsu_wr_data;
  logic                           hsu_rd_valid;
  logic [POLY_W-1:0]              hsu_rd_poly_id_o;
  logic [3:0][COEFF_ADDR_W-1:0]        hsu_rd_idx_o;
  logic [3:0]                     hsu_rd_lane_valid_o;
  logic [3:0][COEFF_DATA_W-1:0]   hsu_rd_data;
  logic                           hsu_stall;

  logic                           tr_req;
  logic                           tr_rd_en;
  logic [POLY_W-1:0]              tr_rd_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]        tr_rd_idx;
  logic [3:0]                     tr_rd_lane_valid;
  logic [3:0]                     tr_wr_en;
  logic [POLY_W-1:0]              tr_wr_poly_id;
  logic [3:0][COEFF_ADDR_W-1:0]   tr_wr_idx;
  logic [3:0][COEFF_DATA_W-1:0]   tr_wr_data;
  logic                           tr_rd_valid;
  logic [POLY_W-1:0]              tr_rd_poly_id_o;
  logic [3:0][COEFF_ADDR_W-1:0]        tr_rd_idx_o;
  logic [3:0]                     tr_rd_lane_valid_o;
  logic [3:0][COEFF_DATA_W-1:0]   tr_rd_data;
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

      hsu_seed_req      = 1'b0;
      hsu_seed_we       = 1'b0;
      hsu_seed_id       = SEED_ID_D;
      hsu_seed_idx      = '0;
      hsu_seed_wdata    = '0;
      tr_seed_req       = 1'b0;
      tr_seed_we        = 1'b0;
      tr_seed_id        = SEED_ID_D;
      tr_seed_idx       = '0;
      tr_seed_wdata     = '0;
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

    // ------------------------------------------------------------------
    // Fixed max-k package slot sanity checks.
    // ------------------------------------------------------------------
    if (QREM_NUM_POLYS != 32 || QREM_MAX_K != 4)
      $fatal(1, "Unexpected poly memory package sizing constants");
    if (POLY_ID_S0 != 0 || POLY_ID_S3 != 3 || POLY_ID_EI != 4)
      $fatal(1, "Secret/error poly-id constants mismatch");
    if (POLY_ID_A0 != 5 || POLY_ID_A3 != 8)
      $fatal(1, "A row-buffer poly-id constants mismatch");
    if (POLY_ID_T0 != 9 || POLY_ID_T3 != 12)
      $fatal(1, "T result poly-id constants mismatch");
    if (POLY_ID_WORK_BASE != 13 || POLY_ID_WORK_COUNT != 19 ||
        POLY_ID_WORK0 != 13 || POLY_ID_WORK18 != 31)
      $fatal(1, "Work-region poly-id constants mismatch");

    if (qrem_seed_map_pkg::seed_base_addr(SEED_ID_D) != SEED_AW'(SEED_BASE_D) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_Z) != SEED_AW'(SEED_BASE_Z) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_M) != SEED_AW'(SEED_BASE_M) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_RHO) != SEED_AW'(SEED_BASE_RHO) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_SIGMA) != SEED_AW'(SEED_BASE_SIGMA) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_HEK) != SEED_AW'(SEED_BASE_HEK) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_SS) != SEED_AW'(SEED_BASE_SS) ||
        qrem_seed_map_pkg::seed_base_addr(SEED_ID_TMP) != SEED_AW'(SEED_BASE_TMP))
      $fatal(1, "Seed/protocol base helper mismatch");
    if (qrem_seed_map_pkg::seed_word_addr(SEED_ID_RHO, 2'd2) != SEED_AW'(SEED_BASE_RHO + 2) ||
        qrem_seed_map_pkg::seed_word_addr(SEED_ID_HEK, 2'd3) != SEED_AW'(SEED_BASE_HEK + 3))
      $fatal(1, "Seed/protocol word helper mismatch");

    // ------------------------------------------------------------------
    // Protocol-store smoke test using semantic object IDs and beat indices.
    // ------------------------------------------------------------------
    hsu_seed_req   = 1'b1;
    hsu_seed_we    = 1'b1;
    hsu_seed_id    = SEED_ID_RHO;
    hsu_seed_idx   = 2'd0;
    hsu_seed_wdata = 64'hCAFE_F00D_0000_0001;
    tr_seed_req    = 1'b1;
    tr_seed_we     = 1'b1;
    tr_seed_id     = SEED_ID_HEK;
    tr_seed_idx    = 2'd3;
    tr_seed_wdata  = 64'h55AA_1234_DEAD_BEEF;
    tick();
    clear_all();

    hsu_seed_req  = 1'b1;
    hsu_seed_id   = SEED_ID_RHO;
    hsu_seed_idx  = 2'd0;
    tr_seed_req   = 1'b1;
    tr_seed_id    = SEED_ID_HEK;
    tr_seed_idx   = 2'd3;
    tick();
    clear_all();

    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'hCAFE_F00D_0000_0001)
      $fatal(1, "RHO protocol-store readback mismatch");
    if (!tr_seed_rvalid || tr_seed_rdata !== 64'h55AA_1234_DEAD_BEEF)
      $fatal(1, "H(ek) protocol-store readback mismatch");

    // ------------------------------------------------------------------
    // Simple poly-memory smoke using semantic KeyGen slots.
    // ------------------------------------------------------------------
    hsu_req           = 1'b1;
    hsu_wr_en         = 4'b1111;
    hsu_wr_poly_id    = POLY_ID_S0;
    hsu_wr_idx[0]     = COEFF_ADDR_W'(0);
    hsu_wr_idx[1]     = COEFF_ADDR_W'(1);
    hsu_wr_idx[2]     = COEFF_ADDR_W'(2);
    hsu_wr_idx[3]     = COEFF_ADDR_W'(3);
    // Write 16-bit values to verify padding
    hsu_wr_data[0]    = 16'hFFFF;
    hsu_wr_data[1]    = 16'h1101;
    hsu_wr_data[2]    = 16'h1102;
    hsu_wr_data[3]    = 16'h1103;
    tick();
    clear_all();

    pau_req           = 1'b1;
    pau_rd_en         = 1'b1;
    pau_rd_poly_id    = POLY_ID_S0;
    pau_rd_idx[0]     = COEFF_ADDR_W'(0);
    pau_rd_idx[1]     = COEFF_ADDR_W'(1);
    pau_rd_idx[2]     = COEFF_ADDR_W'(2);
    pau_rd_idx[3]     = COEFF_ADDR_W'(3);
    pau_rd_lane_valid = 4'b1111;
    tick();
    if (!pau_rd_valid)
      $fatal(1, "Expected readback from semantic S slot");
    // Should be masked to 12-bit
    if (pau_rd_data[0] !== 12'hFFF || pau_rd_data[1] !== 12'h101 ||
        pau_rd_data[2] !== 12'h102 || pau_rd_data[3] !== 12'h103)
      $fatal(1, "Semantic S slot readback mismatch (expected 12-bit data)");
    clear_all();

    // ------------------------------------------------------------------
    // Wipe still clears both polynomial memory and protocol store.
    // ------------------------------------------------------------------
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
    pau_rd_poly_id    = POLY_ID_S0;
    pau_rd_idx[0]     = COEFF_ADDR_W'(0);
    pau_rd_idx[1]     = COEFF_ADDR_W'(1);
    pau_rd_idx[2]     = COEFF_ADDR_W'(2);
    pau_rd_idx[3]     = COEFF_ADDR_W'(3);
    pau_rd_lane_valid = 4'b1111;
    tick();
    if (!pau_rd_valid)
      $fatal(1, "Expected post-wipe read response");
    if (pau_rd_data[0] !== 16'h0000 || pau_rd_data[1] !== 16'h0000 ||
        pau_rd_data[2] !== 16'h0000 || pau_rd_data[3] !== 16'h0000)
      $fatal(1, "Polynomial wipe failed");
    clear_all();

    hsu_seed_req  = 1'b1;
    hsu_seed_id   = SEED_ID_RHO;
    hsu_seed_idx  = 2'd0;
    tick();
    clear_all();
    if (!hsu_seed_rvalid || hsu_seed_rdata !== 64'h0)
      $fatal(1, "Protocol-store wipe failed");

    if (mem_fault_o || mem_fault_code_o !== 3'b000)
      $fatal(1, "Unexpected memory fault during smoke test");

    $display("TB PASS");
    $finish;
  end

endmodule
