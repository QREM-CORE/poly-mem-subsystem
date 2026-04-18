/*
 * Module Name: poly_mem_subsystem
 * Author(s): Mavra Muzmmal, Quardin Lyttle, Salwan Aldhahab
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Top-level polynomial / seed memory subsystem for QREM Core v0.75.
 *
 * Key architectural rules implemented here:
 *   - Strict client priority remains PAU > HSU > Transcoder.
 *   - The polynomial banks actively exploit true dual-port behavior:
 *       * one READ owner may use Port A in a cycle
 *       * one WRITE owner may use Port B in the same cycle
 *   - If any client presents a combined read+write request, that client owns
 *     both planes for the cycle to preserve request atomicity.
 *   - The seed / protocol store is independent from polynomial arbitration and
 *     exposes one dedicated port for HSU-side access and one for
 *     Transcoder-side access.
 *
 * Notes:
 *   - Reset is active-high and synchronous.
 *   - During wipe, all polynomial clients stall and both seed ports report
 *     not-ready.
 *   - Memory exposes a small internal-only control/status sideband for the
 *     Main Controller: wipe_busy, wipe_done, and memory fault reporting.
 */

import qrem_seed_map_pkg::*;

module poly_mem_subsystem #(
  parameter int NUM_POLYS  = 32,
  parameter int NCOEFF     = 256,
  parameter int W          = 16,
  parameter int SEED_DEPTH = QREM_SEED_DEPTH,
  parameter int SEED_W     = QREM_SEED_W
)(
  input  logic clk,
  input  logic rst,

  // --------------------------------------------------------------------------
  // Security wipe
  // --------------------------------------------------------------------------
  input  logic wipe_i,
  output logic wipe_busy_o,
  output logic wipe_done_o,
  output logic mem_fault_o,
  output logic [2:0] mem_fault_code_o,

  // ==========================================================================
  // PAU polynomial-memory interface
  // ==========================================================================
  input  logic                               pau_req,
  input  logic                               pau_rd_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       pau_rd_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     pau_rd_idx,
  input  logic [3:0]                         pau_rd_lane_valid,
  input  logic [3:0]                         pau_wr_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       pau_wr_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     pau_wr_idx,
  input  logic [3:0][W-1:0]                  pau_wr_data,
  output logic                               pau_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       pau_rd_poly_id_o,
  output logic [3:0][$clog2(NCOEFF)-1:0]     pau_rd_idx_o,
  output logic [3:0]                         pau_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  pau_rd_data,
  output logic                               pau_stall,

  // ==========================================================================
  // HSU / Poly Memory Writer polynomial-memory interface
  // ==========================================================================
  input  logic                               hsu_req,
  input  logic                               hsu_rd_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       hsu_rd_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     hsu_rd_idx,
  input  logic [3:0]                         hsu_rd_lane_valid,
  input  logic [3:0]                         hsu_wr_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       hsu_wr_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     hsu_wr_idx,
  input  logic [3:0][W-1:0]                  hsu_wr_data,
  output logic                               hsu_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       hsu_rd_poly_id_o,
  output logic [3:0][$clog2(NCOEFF)-1:0]     hsu_rd_idx_o,
  output logic [3:0]                         hsu_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  hsu_rd_data,
  output logic                               hsu_stall,

  // ==========================================================================
  // Transcoder polynomial-memory interface
  // ==========================================================================
  input  logic                               tr_req,
  input  logic                               tr_rd_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       tr_rd_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     tr_rd_idx,
  input  logic [3:0]                         tr_rd_lane_valid,
  input  logic [3:0]                         tr_wr_en,
  input  logic [$clog2(NUM_POLYS)-1:0]       tr_wr_poly_id,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     tr_wr_idx,
  input  logic [3:0][W-1:0]                  tr_wr_data,
  output logic                               tr_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       tr_rd_poly_id_o,
  output logic [3:0][$clog2(NCOEFF)-1:0]     tr_rd_idx_o,
  output logic [3:0]                         tr_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  tr_rd_data,
  output logic                               tr_stall,

  // ==========================================================================
  // HSU seed / protocol port
  // ==========================================================================
  // This remains a raw address-based RAM port at the memory boundary.
  // The bridge-facing "seed_id + beat_idx" abstraction is built one level
  // above this module using qrem_seed_map_pkg::seed_base_addr(...).
  input  logic                               hsu_seed_req,
  input  logic                               hsu_seed_we,
  input  logic [$clog2(SEED_DEPTH)-1:0]      hsu_seed_addr,
  input  logic [SEED_W-1:0]                  hsu_seed_wdata,
  output logic                               hsu_seed_ready,
  output logic                               hsu_seed_rvalid,
  output logic [SEED_W-1:0]                  hsu_seed_rdata,

  // ==========================================================================
  // Transcoder seed / protocol port
  // ==========================================================================
  // Like the HSU seed port, this is the physical address-based port into the
  // dual-port Seed / Protocol Store. Semantic IDs are translated above memory.
  input  logic                               tr_seed_req,
  input  logic                               tr_seed_we,
  input  logic [$clog2(SEED_DEPTH)-1:0]      tr_seed_addr,
  input  logic [SEED_W-1:0]                  tr_seed_wdata,
  output logic                               tr_seed_ready,
  output logic                               tr_seed_rvalid,
  output logic [SEED_W-1:0]                  tr_seed_rdata
);

  localparam int COEFF_W            = $clog2(NCOEFF);
  localparam int ROWS_PER_POLY_BANK = NCOEFF / 4;
  localparam int ROW_W              = $clog2(ROWS_PER_POLY_BANK);
  localparam int SEED_AW            = $clog2(SEED_DEPTH);

  typedef enum logic [1:0] {
    RD_OWNER_NONE = 2'd0,
    RD_OWNER_PAU  = 2'd1,
    RD_OWNER_HSU  = 2'd2,
    RD_OWNER_TR   = 2'd3
  } rd_owner_e;

  typedef enum logic [1:0] {
    WIPE_IDLE = 2'd0,
    WIPE_POLY = 2'd1,
    WIPE_SEED = 2'd2,
    WIPE_DONE = 2'd3
  } wipe_state_e;

  rd_owner_e   rd_owner_q, rd_owner_d;
  wipe_state_e wipe_state_q, wipe_state_d;
  logic [$clog2(NUM_POLYS)-1:0] wipe_poly_q, wipe_poly_d;
  logic [ROW_W-1:0]             wipe_row_q, wipe_row_d;
  logic [SEED_AW-1:0]           wipe_seed_q, wipe_seed_d;
  logic                         poly_fault;
  logic [2:0]                   poly_fault_code;
  logic                         mem_fault_q;
  logic [2:0]                   mem_fault_code_q;

  // --------------------------------------------------------------------------
  // Per-client request classification
  // --------------------------------------------------------------------------
  logic pau_rd_req, pau_wr_req, pau_both_req;
  logic hsu_rd_req, hsu_wr_req, hsu_both_req;
  logic tr_rd_req, tr_wr_req, tr_both_req;

  assign pau_rd_req   = pau_req && pau_rd_en && (|pau_rd_lane_valid);
  assign pau_wr_req   = pau_req && (|pau_wr_en);
  assign pau_both_req = pau_rd_req && pau_wr_req;

  assign hsu_rd_req   = hsu_req && hsu_rd_en && (|hsu_rd_lane_valid);
  assign hsu_wr_req   = hsu_req && (|hsu_wr_en);
  assign hsu_both_req = hsu_rd_req && hsu_wr_req;

  assign tr_rd_req    = tr_req && tr_rd_en && (|tr_rd_lane_valid);
  assign tr_wr_req    = tr_req && (|tr_wr_en);
  assign tr_both_req  = tr_rd_req && tr_wr_req;

  logic wipe_active;
  logic [COEFF_W-1:0] wipe_base_idx;
  assign wipe_active   = (wipe_state_q != WIPE_IDLE);
  assign wipe_base_idx = COEFF_W'({wipe_row_q, 2'b00});
  assign wipe_busy_o   = wipe_active;
  assign mem_fault_o   = mem_fault_q;
  assign mem_fault_code_o = mem_fault_code_q;

  // --------------------------------------------------------------------------
  // Combined-owner detection
  // --------------------------------------------------------------------------
  logic combo_pau, combo_hsu, combo_tr, combo_any;
  assign combo_pau = ~wipe_active && pau_both_req;
  assign combo_hsu = ~combo_pau && ~wipe_active && hsu_both_req;
  assign combo_tr  = ~combo_pau && ~combo_hsu && ~wipe_active && tr_both_req;
  assign combo_any = combo_pau || combo_hsu || combo_tr;

  // --------------------------------------------------------------------------
  // Independent read / write arbiters for disjoint-plane access
  // --------------------------------------------------------------------------
  logic grant_pau_rd, grant_hsu_rd, grant_tr_rd;
  logic grant_pau_wr, grant_hsu_wr, grant_tr_wr;
  logic unused_pau_rd_stall, unused_hsu_rd_stall, unused_tr_rd_stall;
  logic unused_pau_wr_stall, unused_hsu_wr_stall, unused_tr_wr_stall;

  logic poly_rd_ready, poly_wr_ready;

  mem_arbiter u_rd_arbiter (
    .pau_req_i   (pau_rd_req && ~combo_any && ~wipe_active),
    .hsu_req_i   (hsu_rd_req && ~combo_any && ~wipe_active),
    .tr_req_i    (tr_rd_req  && ~combo_any && ~wipe_active),
    .mem_ready_i (poly_rd_ready),
    .grant_pau_o (grant_pau_rd),
    .grant_hsu_o (grant_hsu_rd),
    .grant_tr_o  (grant_tr_rd),
    .pau_stall_o (unused_pau_rd_stall),
    .hsu_stall_o (unused_hsu_rd_stall),
    .tr_stall_o  (unused_tr_rd_stall)
  );

  mem_arbiter u_wr_arbiter (
    .pau_req_i   (pau_wr_req && ~combo_any && ~wipe_active),
    .hsu_req_i   (hsu_wr_req && ~combo_any && ~wipe_active),
    .tr_req_i    (tr_wr_req  && ~combo_any && ~wipe_active),
    .mem_ready_i (poly_wr_ready),
    .grant_pau_o (grant_pau_wr),
    .grant_hsu_o (grant_hsu_wr),
    .grant_tr_o  (grant_tr_wr),
    .pau_stall_o (unused_pau_wr_stall),
    .hsu_stall_o (unused_hsu_wr_stall),
    .tr_stall_o  (unused_tr_wr_stall)
  );

  // --------------------------------------------------------------------------
  // Muxed polynomial memory planes
  // --------------------------------------------------------------------------
  logic                               poly_rd_v_mux;
  logic [$clog2(NUM_POLYS)-1:0]       poly_rd_poly_id_mux;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_mux;
  logic [3:0]                         poly_rd_lane_valid_mux;

  logic                               poly_wr_v_mux;
  logic [$clog2(NUM_POLYS)-1:0]       poly_wr_poly_id_mux;
  logic [3:0]                         poly_wr_en_mux;
  logic [3:0][COEFF_W-1:0]            poly_wr_idx_mux;
  logic [3:0][W-1:0]                  poly_wr_data_mux;

  logic                               accepted_read_fire;
  logic                               rd_combo_can_fire;
  logic                               wr_combo_can_fire;
  logic                               combo_can_fire;

  always_comb begin
    poly_rd_v_mux           = 1'b0;
    poly_rd_poly_id_mux     = '0;
    poly_rd_idx_mux         = '0;
    poly_rd_lane_valid_mux  = '0;

    poly_wr_v_mux           = 1'b0;
    poly_wr_poly_id_mux     = '0;
    poly_wr_en_mux          = '0;
    poly_wr_idx_mux         = '0;
    poly_wr_data_mux        = '0;

    rd_combo_can_fire       = 1'b1;
    wr_combo_can_fire       = 1'b1;

    if (combo_pau) begin
      rd_combo_can_fire      = ~pau_rd_req | poly_rd_ready;
      wr_combo_can_fire      = ~pau_wr_req | poly_wr_ready;
      poly_rd_poly_id_mux    = pau_rd_poly_id;
      poly_rd_idx_mux        = pau_rd_idx;
      poly_rd_lane_valid_mux = pau_rd_lane_valid;
      poly_wr_poly_id_mux    = pau_wr_poly_id;
      poly_wr_en_mux         = pau_wr_en;
      poly_wr_idx_mux        = pau_wr_idx;
      poly_wr_data_mux       = pau_wr_data;
    end else if (combo_hsu) begin
      rd_combo_can_fire      = ~hsu_rd_req | poly_rd_ready;
      wr_combo_can_fire      = ~hsu_wr_req | poly_wr_ready;
      poly_rd_poly_id_mux    = hsu_rd_poly_id;
      poly_rd_idx_mux        = hsu_rd_idx;
      poly_rd_lane_valid_mux = hsu_rd_lane_valid;
      poly_wr_poly_id_mux    = hsu_wr_poly_id;
      poly_wr_en_mux         = hsu_wr_en;
      poly_wr_idx_mux        = hsu_wr_idx;
      poly_wr_data_mux       = hsu_wr_data;
    end else if (combo_tr) begin
      rd_combo_can_fire      = ~tr_rd_req | poly_rd_ready;
      wr_combo_can_fire      = ~tr_wr_req | poly_wr_ready;
      poly_rd_poly_id_mux    = tr_rd_poly_id;
      poly_rd_idx_mux        = tr_rd_idx;
      poly_rd_lane_valid_mux = tr_rd_lane_valid;
      poly_wr_poly_id_mux    = tr_wr_poly_id;
      poly_wr_en_mux         = tr_wr_en;
      poly_wr_idx_mux        = tr_wr_idx;
      poly_wr_data_mux       = tr_wr_data;
    end else if (grant_pau_rd) begin
      poly_rd_poly_id_mux    = pau_rd_poly_id;
      poly_rd_idx_mux        = pau_rd_idx;
      poly_rd_lane_valid_mux = pau_rd_lane_valid;
    end else if (grant_hsu_rd) begin
      poly_rd_poly_id_mux    = hsu_rd_poly_id;
      poly_rd_idx_mux        = hsu_rd_idx;
      poly_rd_lane_valid_mux = hsu_rd_lane_valid;
    end else if (grant_tr_rd) begin
      poly_rd_poly_id_mux    = tr_rd_poly_id;
      poly_rd_idx_mux        = tr_rd_idx;
      poly_rd_lane_valid_mux = tr_rd_lane_valid;
    end

    if (!combo_any) begin
      if (grant_pau_wr) begin
        poly_wr_poly_id_mux = pau_wr_poly_id;
        poly_wr_en_mux      = pau_wr_en;
        poly_wr_idx_mux     = pau_wr_idx;
        poly_wr_data_mux    = pau_wr_data;
      end else if (grant_hsu_wr) begin
        poly_wr_poly_id_mux = hsu_wr_poly_id;
        poly_wr_en_mux      = hsu_wr_en;
        poly_wr_idx_mux     = hsu_wr_idx;
        poly_wr_data_mux    = hsu_wr_data;
      end else if (grant_tr_wr) begin
        poly_wr_poly_id_mux = tr_wr_poly_id;
        poly_wr_en_mux      = tr_wr_en;
        poly_wr_idx_mux     = tr_wr_idx;
        poly_wr_data_mux    = tr_wr_data;
      end
    end

    combo_can_fire = rd_combo_can_fire && wr_combo_can_fire;

    if (wipe_state_q == WIPE_POLY) begin
      poly_rd_v_mux           = 1'b0;
      poly_rd_poly_id_mux     = '0;
      poly_rd_idx_mux         = '0;
      poly_rd_lane_valid_mux  = '0;
      poly_wr_v_mux           = 1'b1;
      poly_wr_poly_id_mux     = wipe_poly_q;
      poly_wr_en_mux          = 4'b1111;
      poly_wr_idx_mux[0]      = wipe_base_idx + COEFF_W'(0);
      poly_wr_idx_mux[1]      = wipe_base_idx + COEFF_W'(1);
      poly_wr_idx_mux[2]      = wipe_base_idx + COEFF_W'(2);
      poly_wr_idx_mux[3]      = wipe_base_idx + COEFF_W'(3);
      poly_wr_data_mux        = '0;
    end else if (combo_any) begin
      poly_rd_v_mux = combo_can_fire &&
                      ((combo_pau && pau_rd_req) || (combo_hsu && hsu_rd_req) || (combo_tr && tr_rd_req));
      poly_wr_v_mux = combo_can_fire &&
                      ((combo_pau && pau_wr_req) || (combo_hsu && hsu_wr_req) || (combo_tr && tr_wr_req));
    end else begin
      poly_rd_v_mux = grant_pau_rd || grant_hsu_rd || grant_tr_rd;
      poly_wr_v_mux = grant_pau_wr || grant_hsu_wr || grant_tr_wr;
    end
  end

  assign accepted_read_fire = poly_rd_v_mux && poly_rd_ready;

  // --------------------------------------------------------------------------
  // Final stall generation
  // --------------------------------------------------------------------------
  always_comb begin
    pau_stall = 1'b0;
    hsu_stall = 1'b0;
    tr_stall  = 1'b0;

    if (wipe_active) begin
      pau_stall = pau_req;
      hsu_stall = hsu_req;
      tr_stall  = tr_req;
    end else if (combo_any) begin
      pau_stall = pau_req && (~combo_pau || ~combo_can_fire);
      hsu_stall = hsu_req && (~combo_hsu || ~combo_can_fire);
      tr_stall  = tr_req  && (~combo_tr  || ~combo_can_fire);
    end else begin
      pau_stall = (pau_rd_req && (~grant_pau_rd || ~poly_rd_ready)) ||
                  (pau_wr_req && (~grant_pau_wr || ~poly_wr_ready));
      hsu_stall = (hsu_rd_req && (~grant_hsu_rd || ~poly_rd_ready)) ||
                  (hsu_wr_req && (~grant_hsu_wr || ~poly_wr_ready));
      tr_stall  = (tr_rd_req  && (~grant_tr_rd  || ~poly_rd_ready)) ||
                  (tr_wr_req  && (~grant_tr_wr  || ~poly_wr_ready));
    end
  end

  // --------------------------------------------------------------------------
  // Read owner tagging
  // --------------------------------------------------------------------------
  always_comb begin
    rd_owner_d = rd_owner_q;

    if (accepted_read_fire) begin
      if (combo_pau || grant_pau_rd) rd_owner_d = RD_OWNER_PAU;
      else if (combo_hsu || grant_hsu_rd) rd_owner_d = RD_OWNER_HSU;
      else if (combo_tr || grant_tr_rd) rd_owner_d = RD_OWNER_TR;
      else rd_owner_d = RD_OWNER_NONE;
    end
  end

  // --------------------------------------------------------------------------
  // Polynomial memory wrapper
  // --------------------------------------------------------------------------
  logic                               poly_rd_valid;
  logic [$clog2(NUM_POLYS)-1:0]       poly_rd_poly_id;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_rsp;
  logic [3:0]                         poly_rd_lane_valid_rsp;
  logic [3:0][W-1:0]                  poly_rd_data_rsp;

  poly_mem_wrapper_4bank #(
    .N         (NCOEFF),
    .W         (W),
    .NUM_POLYS (NUM_POLYS)
  ) u_poly_mem (
    .clk             (clk),
    .rst             (rst),
    .rd_poly_id_i    (poly_rd_poly_id_mux),
    .rd_v_i          (poly_rd_v_mux),
    .rd_idx_i        (poly_rd_idx_mux),
    .rd_lane_valid_i (poly_rd_lane_valid_mux),
    .rd_ready_o      (poly_rd_ready),
    .rd_valid_o      (poly_rd_valid),
    .rd_poly_id_o    (poly_rd_poly_id),
    .rd_idx_o        (poly_rd_idx_rsp),
    .rd_lane_valid_o (poly_rd_lane_valid_rsp),
    .rd_data_o       (poly_rd_data_rsp),
    .wr_poly_id_i    (poly_wr_poly_id_mux),
    .wr_v_i          (poly_wr_v_mux),
    .wr_en_i         (poly_wr_en_mux),
    .wr_idx_i        (poly_wr_idx_mux),
    .wr_data_i       (poly_wr_data_mux),
    .wr_ready_o      (poly_wr_ready),
    .fault_o         (poly_fault),
    .fault_code_o    (poly_fault_code)
  );

  // --------------------------------------------------------------------------
  // Dual-port seed / protocol store
  // --------------------------------------------------------------------------
  logic [SEED_W-1:0] hsu_seed_rdata_int, tr_seed_rdata_int;
  logic              hsu_seed_read_fire, tr_seed_read_fire;
  logic              hsu_seed_read_fire_q, tr_seed_read_fire_q;

  logic              seed_a_we_mux, seed_b_we_mux;
  logic [SEED_AW-1:0] seed_a_addr_mux, seed_b_addr_mux;
  logic [SEED_W-1:0]  seed_a_wdata_mux, seed_b_wdata_mux;

  always_comb begin
    seed_a_we_mux    = hsu_seed_we && hsu_seed_req && ~wipe_active;
    seed_a_addr_mux  = hsu_seed_addr;
    seed_a_wdata_mux = hsu_seed_wdata;

    seed_b_we_mux    = tr_seed_we && tr_seed_req && ~wipe_active;
    seed_b_addr_mux  = tr_seed_addr;
    seed_b_wdata_mux = tr_seed_wdata;

    if (wipe_state_q == WIPE_SEED) begin
      seed_a_we_mux    = 1'b1;
      seed_a_addr_mux  = wipe_seed_q;
      seed_a_wdata_mux = '0;

      seed_b_we_mux    = 1'b0;
      seed_b_addr_mux  = '0;
      seed_b_wdata_mux = '0;
    end
  end

  assign hsu_seed_ready    = ~wipe_active;
  assign tr_seed_ready     = ~wipe_active;
  assign hsu_seed_read_fire = ~wipe_active && hsu_seed_req && ~hsu_seed_we;
  assign tr_seed_read_fire  = ~wipe_active && tr_seed_req  && ~tr_seed_we;

  seed_ram #(
    .DEPTH  (SEED_DEPTH),
    .W      (SEED_W),
    .ADDR_W (SEED_AW)
  ) u_seed_ram (
    .clk    (clk),
    .rst    (rst),
    .a_we   (seed_a_we_mux),
    .a_addr (seed_a_addr_mux),
    .a_wdata(seed_a_wdata_mux),
    .a_rdata(hsu_seed_rdata_int),
    .b_we   (seed_b_we_mux),
    .b_addr (seed_b_addr_mux),
    .b_wdata(seed_b_wdata_mux),
    .b_rdata(tr_seed_rdata_int)
  );

  assign hsu_seed_rdata  = hsu_seed_rdata_int;
  assign tr_seed_rdata   = tr_seed_rdata_int;
  assign hsu_seed_rvalid = hsu_seed_read_fire_q;
  assign tr_seed_rvalid  = tr_seed_read_fire_q;

  // --------------------------------------------------------------------------
  // Read response routing
  // --------------------------------------------------------------------------
  always_comb begin
    pau_rd_valid        = 1'b0;
    pau_rd_poly_id_o    = '0;
    pau_rd_idx_o        = '0;
    pau_rd_lane_valid_o = '0;
    pau_rd_data         = '0;

    hsu_rd_valid        = 1'b0;
    hsu_rd_poly_id_o    = '0;
    hsu_rd_idx_o        = '0;
    hsu_rd_lane_valid_o = '0;
    hsu_rd_data         = '0;

    tr_rd_valid         = 1'b0;
    tr_rd_poly_id_o     = '0;
    tr_rd_idx_o         = '0;
    tr_rd_lane_valid_o  = '0;
    tr_rd_data          = '0;

    if (poly_rd_valid) begin
      unique case (rd_owner_q)
        RD_OWNER_PAU: begin
          pau_rd_valid        = 1'b1;
          pau_rd_poly_id_o    = poly_rd_poly_id;
          pau_rd_idx_o        = poly_rd_idx_rsp;
          pau_rd_lane_valid_o = poly_rd_lane_valid_rsp;
          pau_rd_data         = poly_rd_data_rsp;
        end
        RD_OWNER_HSU: begin
          hsu_rd_valid        = 1'b1;
          hsu_rd_poly_id_o    = poly_rd_poly_id;
          hsu_rd_idx_o        = poly_rd_idx_rsp;
          hsu_rd_lane_valid_o = poly_rd_lane_valid_rsp;
          hsu_rd_data         = poly_rd_data_rsp;
        end
        RD_OWNER_TR: begin
          tr_rd_valid         = 1'b1;
          tr_rd_poly_id_o     = poly_rd_poly_id;
          tr_rd_idx_o         = poly_rd_idx_rsp;
          tr_rd_lane_valid_o  = poly_rd_lane_valid_rsp;
          tr_rd_data          = poly_rd_data_rsp;
        end
        default: begin
        end
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Wipe FSM
  // --------------------------------------------------------------------------
  always_comb begin
    wipe_state_d = wipe_state_q;
    wipe_poly_d  = wipe_poly_q;
    wipe_row_d   = wipe_row_q;
    wipe_seed_d  = wipe_seed_q;
    wipe_done_o  = 1'b0;

    unique case (wipe_state_q)
      WIPE_IDLE: begin
        if (wipe_i) begin
          wipe_state_d = WIPE_POLY;
          wipe_poly_d  = '0;
          wipe_row_d   = '0;
          wipe_seed_d  = '0;
        end
      end

      WIPE_POLY: begin
        if (poly_wr_ready) begin
          if (wipe_row_q == ROWS_PER_POLY_BANK-1) begin
            wipe_row_d = '0;
            if (wipe_poly_q == NUM_POLYS-1) begin
              wipe_poly_d  = '0;
              wipe_state_d = WIPE_SEED;
            end else begin
              wipe_poly_d = wipe_poly_q + 1'b1;
            end
          end else begin
            wipe_row_d = wipe_row_q + 1'b1;
          end
        end
      end

      WIPE_SEED: begin
        if (wipe_seed_q == SEED_DEPTH-1) begin
          wipe_seed_d  = '0;
          wipe_state_d = WIPE_DONE;
        end else begin
          wipe_seed_d = wipe_seed_q + 1'b1;
        end
      end

      WIPE_DONE: begin
        wipe_done_o  = 1'b1;
        wipe_state_d = WIPE_IDLE;
      end

      default: begin
        wipe_state_d = WIPE_IDLE;
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // Sequential state
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      wipe_state_q       <= WIPE_IDLE;
      wipe_poly_q        <= '0;
      wipe_row_q         <= '0;
      wipe_seed_q        <= '0;
      rd_owner_q         <= RD_OWNER_NONE;
      hsu_seed_read_fire_q <= 1'b0;
      tr_seed_read_fire_q  <= 1'b0;
      mem_fault_q        <= 1'b0;
      mem_fault_code_q   <= 3'b000;
    end else begin
      wipe_state_q       <= wipe_state_d;
      wipe_poly_q        <= wipe_poly_d;
      wipe_row_q         <= wipe_row_d;
      wipe_seed_q        <= wipe_seed_d;
      rd_owner_q         <= rd_owner_d;
      hsu_seed_read_fire_q <= hsu_seed_read_fire;
      tr_seed_read_fire_q  <= tr_seed_read_fire;
      mem_fault_q        <= poly_fault;
      mem_fault_code_q   <= poly_fault ? poly_fault_code : 3'b000;
    end
  end

endmodule
