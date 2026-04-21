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
 *   - Polynomial memory now schedules onto two internal generic ports, allowing
 *     two legal client requests per cycle when hazards permit.
 *   - If any client presents a combined read+write request, that client owns
 *     both internal ports atomically for the cycle.
 *   - HSU polynomial access is write-only in this repo phase; `hsu_rd_*`
 *     signals are kept only for top-level interface stability.
 *   - The seed / protocol store remains independent from polynomial
 *     arbitration and exposes one dedicated HSU-side port and one dedicated
 *     Transcoder-side port.
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
  input  logic                               tr_seed_req,
  input  logic                               tr_seed_we,
  input  logic [$clog2(SEED_DEPTH)-1:0]      tr_seed_addr,
  input  logic [SEED_W-1:0]                  tr_seed_wdata,
  output logic                               tr_seed_ready,
  output logic                               tr_seed_rvalid,
  output logic [SEED_W-1:0]                  tr_seed_rdata
);

  localparam int POLY_W             = $clog2(NUM_POLYS);
  localparam int COEFF_W            = $clog2(NCOEFF);
  localparam int ROWS_PER_POLY_BANK = NCOEFF / 4;
  localparam int ROW_W              = $clog2(ROWS_PER_POLY_BANK);
  localparam int SEED_AW            = $clog2(SEED_DEPTH);
  localparam int BANK_AW            = $clog2(NUM_POLYS * ROWS_PER_POLY_BANK);

  typedef enum logic [1:0] {
    OWNER_NONE = 2'd0,
    OWNER_PAU  = 2'd1,
    OWNER_HSU  = 2'd2,
    OWNER_TR   = 2'd3
  } client_owner_e;

  typedef enum logic [1:0] {
    REQ_NONE  = 2'd0,
    REQ_READ  = 2'd1,
    REQ_WRITE = 2'd2
  } req_kind_e;

  typedef enum logic [1:0] {
    WIPE_IDLE = 2'd0,
    WIPE_POLY = 2'd1,
    WIPE_SEED = 2'd2,
    WIPE_DONE = 2'd3
  } wipe_state_e;

  wipe_state_e   wipe_state_q, wipe_state_d;
  logic [POLY_W-1:0] wipe_poly_q, wipe_poly_d;
  logic [ROW_W-1:0]  wipe_row_q,  wipe_row_d;
  logic [SEED_AW-1:0] wipe_seed_q, wipe_seed_d;

  client_owner_e p0_rd_owner_q, p1_rd_owner_q;
  logic          mem_fault_q;
  logic [2:0]    mem_fault_code_q;

  logic          poly_fault;
  logic [2:0]    poly_fault_code;

  // --------------------------------------------------------------------------
  // Local CMI decode helpers used only for scheduling preview.
  // The wrapper remains authoritative for the actual bank/row access.
  // --------------------------------------------------------------------------
  function automatic [1:0] cmi_bank_idx(
    input logic [COEFF_W-1:0] order
  );
    logic [3:0] sum;
    begin
      sum = order[1:0] + order[3:2] + order[5:4] + order[7:6];
      cmi_bank_idx = sum[1:0];
    end
  endfunction

  function automatic [BANK_AW-1:0] cmi_bank_addr(
    input logic [POLY_W-1:0] pid,
    input logic [COEFF_W-1:0] order
  );
    logic [ROW_W-1:0] row;
    begin
      row = order >> 2;
      cmi_bank_addr = pid * ROWS_PER_POLY_BANK + row;
    end
  endfunction

  function automatic logic req_has_conflict(
    input logic [POLY_W-1:0]        poly_id,
    input logic [3:0][COEFF_W-1:0] idx,
    input logic [3:0]              lane_mask
  );
    logic [3:0][1:0]         bank;
    integer ii, jj;
    begin
      req_has_conflict = 1'b0;

      for (ii = 0; ii < 4; ii++) begin
        bank[ii] = cmi_bank_idx(idx[ii]);
      end

      for (ii = 0; ii < 4; ii++) begin
        for (jj = ii + 1; jj < 4; jj++) begin
          if (lane_mask[ii] && lane_mask[jj] && (bank[ii] == bank[jj]))
            req_has_conflict = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic req_pair_legal(
    input logic                     a_is_wr,
    input logic [POLY_W-1:0]        a_poly_id,
    input logic [3:0][COEFF_W-1:0] a_idx,
    input logic [3:0]              a_lane_mask,
    input logic                     b_is_wr,
    input logic [POLY_W-1:0]        b_poly_id,
    input logic [3:0][COEFF_W-1:0] b_idx,
    input logic [3:0]              b_lane_mask
  );
    logic [3:0][1:0]         a_bank, b_bank;
    logic [3:0][BANK_AW-1:0] a_baddr, b_baddr;
    integer ii, jj;
    begin
      req_pair_legal = 1'b1;

      if (!a_is_wr && !b_is_wr) begin
        req_pair_legal = 1'b1;
      end else begin
        for (ii = 0; ii < 4; ii++) begin
          a_bank[ii]  = cmi_bank_idx(a_idx[ii]);
          a_baddr[ii] = cmi_bank_addr(a_poly_id, a_idx[ii]);
          b_bank[ii]  = cmi_bank_idx(b_idx[ii]);
          b_baddr[ii] = cmi_bank_addr(b_poly_id, b_idx[ii]);
        end

        for (ii = 0; ii < 4; ii++) begin
          for (jj = 0; jj < 4; jj++) begin
            if (a_lane_mask[ii] && b_lane_mask[jj] &&
                (a_bank[ii] == b_bank[jj]) &&
                (a_baddr[ii] == b_baddr[jj]) &&
                (a_is_wr || b_is_wr))
              req_pair_legal = 1'b0;
          end
        end
      end
    end
  endfunction

  // --------------------------------------------------------------------------
  // Per-client request classification
  // --------------------------------------------------------------------------
  logic pau_rd_req, pau_wr_req, pau_both_req, pau_single_req;
  logic hsu_rd_req, hsu_wr_req, hsu_both_req, hsu_single_req;
  logic tr_rd_req, tr_wr_req, tr_both_req, tr_single_req;
  logic hsu_poly_rd_unsupported;

  assign pau_rd_req    = pau_req && pau_rd_en && (|pau_rd_lane_valid);
  assign pau_wr_req    = pau_req && (|pau_wr_en);
  assign pau_both_req  = pau_rd_req && pau_wr_req;
  assign pau_single_req = (pau_rd_req || pau_wr_req) && ~pau_both_req;

  // HSU consumes polynomial memory only as a writer. Any asserted poly-read
  // request is treated as unsupported and must retry as a seed/protocol read.
  assign hsu_poly_rd_unsupported = hsu_req && hsu_rd_en && (|hsu_rd_lane_valid);
  assign hsu_rd_req    = 1'b0;
  assign hsu_wr_req    = hsu_req && ~hsu_poly_rd_unsupported && (|hsu_wr_en);
  assign hsu_both_req  = hsu_rd_req && hsu_wr_req;
  assign hsu_single_req = (hsu_rd_req || hsu_wr_req) && ~hsu_both_req;

  assign tr_rd_req     = tr_req && tr_rd_en && (|tr_rd_lane_valid);
  assign tr_wr_req     = tr_req && (|tr_wr_en);
  assign tr_both_req   = tr_rd_req && tr_wr_req;
  assign tr_single_req = (tr_rd_req || tr_wr_req) && ~tr_both_req;

  logic wipe_active;
  logic [COEFF_W-1:0] wipe_base_idx;
  assign wipe_active     = (wipe_state_q != WIPE_IDLE);
  assign wipe_base_idx   = COEFF_W'({wipe_row_q, 2'b00});
  assign wipe_busy_o     = wipe_active;
  assign mem_fault_o     = mem_fault_q;
  assign mem_fault_code_o = mem_fault_code_q;

  // --------------------------------------------------------------------------
  // Combined-owner detection
  // --------------------------------------------------------------------------
  logic combo_pau, combo_hsu, combo_tr, combo_any;
  client_owner_e combo_owner;

  assign combo_pau = ~wipe_active && pau_both_req;
  assign combo_hsu = ~combo_pau && ~wipe_active && hsu_both_req;
  assign combo_tr  = ~combo_pau && ~combo_hsu && ~wipe_active && tr_both_req;
  assign combo_any = combo_pau || combo_hsu || combo_tr;

  always_comb begin
    combo_owner = OWNER_NONE;
    if (combo_pau) combo_owner = OWNER_PAU;
    else if (combo_hsu) combo_owner = OWNER_HSU;
    else if (combo_tr) combo_owner = OWNER_TR;
  end

  // --------------------------------------------------------------------------
  // Normalized one-sided request views used by the 2-port scheduler
  // --------------------------------------------------------------------------
  logic        pau_is_wr_req, hsu_is_wr_req, tr_is_wr_req;
  logic [POLY_W-1:0]        pau_poly_id_req, hsu_poly_id_req, tr_poly_id_req;
  logic [3:0][COEFF_W-1:0] pau_idx_req, hsu_idx_req, tr_idx_req;
  logic [3:0]              pau_lane_mask_req, hsu_lane_mask_req, tr_lane_mask_req;
  logic [3:0][W-1:0]       pau_data_req, hsu_data_req, tr_data_req;
  logic                    pau_conflict_req, hsu_conflict_req, tr_conflict_req;

  assign pau_is_wr_req       = pau_wr_req;
  assign hsu_is_wr_req       = hsu_wr_req;
  assign tr_is_wr_req        = tr_wr_req;

  assign pau_poly_id_req     = pau_wr_req ? pau_wr_poly_id : pau_rd_poly_id;
  assign hsu_poly_id_req     = hsu_wr_req ? hsu_wr_poly_id : hsu_rd_poly_id;
  assign tr_poly_id_req      = tr_wr_req  ? tr_wr_poly_id  : tr_rd_poly_id;

  assign pau_idx_req         = pau_wr_req ? pau_wr_idx : pau_rd_idx;
  assign hsu_idx_req         = hsu_wr_req ? hsu_wr_idx : hsu_rd_idx;
  assign tr_idx_req          = tr_wr_req  ? tr_wr_idx  : tr_rd_idx;

  assign pau_lane_mask_req   = pau_wr_req ? pau_wr_en : pau_rd_lane_valid;
  assign hsu_lane_mask_req   = hsu_wr_req ? hsu_wr_en : hsu_rd_lane_valid;
  assign tr_lane_mask_req    = tr_wr_req  ? tr_wr_en  : tr_rd_lane_valid;

  assign pau_data_req        = pau_wr_data;
  assign hsu_data_req        = hsu_wr_data;
  assign tr_data_req         = tr_wr_data;

  assign pau_conflict_req    = req_has_conflict(pau_poly_id_req, pau_idx_req, pau_lane_mask_req);
  assign hsu_conflict_req    = req_has_conflict(hsu_poly_id_req, hsu_idx_req, hsu_lane_mask_req);
  assign tr_conflict_req     = req_has_conflict(tr_poly_id_req,  tr_idx_req,  tr_lane_mask_req);

  // --------------------------------------------------------------------------
  // Deterministic 2-port request scheduler
  // --------------------------------------------------------------------------
  client_owner_e p0_sel_owner, p1_sel_owner;
  req_kind_e     p0_sel_kind,  p1_sel_kind;
  logic [POLY_W-1:0]        p0_sel_poly_id, p1_sel_poly_id;
  logic [3:0][COEFF_W-1:0] p0_sel_idx,     p1_sel_idx;
  logic [3:0]              p0_sel_lane_mask, p1_sel_lane_mask;
  logic [3:0][W-1:0]       p0_sel_data,    p1_sel_data;
  logic                    p0_sel_conflict;

  always_comb begin
    p0_sel_owner     = OWNER_NONE;
    p0_sel_kind      = REQ_NONE;
    p0_sel_poly_id   = '0;
    p0_sel_idx       = '0;
    p0_sel_lane_mask = '0;
    p0_sel_data      = '0;
    p0_sel_conflict  = 1'b0;

    p1_sel_owner     = OWNER_NONE;
    p1_sel_kind      = REQ_NONE;
    p1_sel_poly_id   = '0;
    p1_sel_idx       = '0;
    p1_sel_lane_mask = '0;
    p1_sel_data      = '0;

    if (!wipe_active && !combo_any) begin
      if (pau_single_req) begin
        p0_sel_owner     = OWNER_PAU;
        if (pau_is_wr_req)
          p0_sel_kind = REQ_WRITE;
        else
          p0_sel_kind = REQ_READ;
        p0_sel_poly_id   = pau_poly_id_req;
        p0_sel_idx       = pau_idx_req;
        p0_sel_lane_mask = pau_lane_mask_req;
        p0_sel_data      = pau_data_req;
        p0_sel_conflict  = pau_conflict_req;
      end else if (hsu_single_req) begin
        p0_sel_owner     = OWNER_HSU;
        if (hsu_is_wr_req)
          p0_sel_kind = REQ_WRITE;
        else
          p0_sel_kind = REQ_READ;
        p0_sel_poly_id   = hsu_poly_id_req;
        p0_sel_idx       = hsu_idx_req;
        p0_sel_lane_mask = hsu_lane_mask_req;
        p0_sel_data      = hsu_data_req;
        p0_sel_conflict  = hsu_conflict_req;
      end else if (tr_single_req) begin
        p0_sel_owner     = OWNER_TR;
        if (tr_is_wr_req)
          p0_sel_kind = REQ_WRITE;
        else
          p0_sel_kind = REQ_READ;
        p0_sel_poly_id   = tr_poly_id_req;
        p0_sel_idx       = tr_idx_req;
        p0_sel_lane_mask = tr_lane_mask_req;
        p0_sel_data      = tr_data_req;
        p0_sel_conflict  = tr_conflict_req;
      end

      if ((p0_sel_owner != OWNER_NONE) && !p0_sel_conflict) begin
        if ((p0_sel_owner != OWNER_PAU) && pau_single_req && !pau_conflict_req &&
            req_pair_legal(
              (p0_sel_kind == REQ_WRITE), p0_sel_poly_id, p0_sel_idx, p0_sel_lane_mask,
              pau_is_wr_req, pau_poly_id_req, pau_idx_req, pau_lane_mask_req
            )) begin
          p1_sel_owner     = OWNER_PAU;
          if (pau_is_wr_req)
            p1_sel_kind = REQ_WRITE;
          else
            p1_sel_kind = REQ_READ;
          p1_sel_poly_id   = pau_poly_id_req;
          p1_sel_idx       = pau_idx_req;
          p1_sel_lane_mask = pau_lane_mask_req;
          p1_sel_data      = pau_data_req;
        end else if ((p0_sel_owner != OWNER_HSU) && hsu_single_req && !hsu_conflict_req &&
                     req_pair_legal(
                       (p0_sel_kind == REQ_WRITE), p0_sel_poly_id, p0_sel_idx, p0_sel_lane_mask,
                       hsu_is_wr_req, hsu_poly_id_req, hsu_idx_req, hsu_lane_mask_req
                     )) begin
          p1_sel_owner     = OWNER_HSU;
          if (hsu_is_wr_req)
            p1_sel_kind = REQ_WRITE;
          else
            p1_sel_kind = REQ_READ;
          p1_sel_poly_id   = hsu_poly_id_req;
          p1_sel_idx       = hsu_idx_req;
          p1_sel_lane_mask = hsu_lane_mask_req;
          p1_sel_data      = hsu_data_req;
        end else if ((p0_sel_owner != OWNER_TR) && tr_single_req && !tr_conflict_req &&
                     req_pair_legal(
                       (p0_sel_kind == REQ_WRITE), p0_sel_poly_id, p0_sel_idx, p0_sel_lane_mask,
                       tr_is_wr_req, tr_poly_id_req, tr_idx_req, tr_lane_mask_req
                     )) begin
          p1_sel_owner     = OWNER_TR;
          if (tr_is_wr_req)
            p1_sel_kind = REQ_WRITE;
          else
            p1_sel_kind = REQ_READ;
          p1_sel_poly_id   = tr_poly_id_req;
          p1_sel_idx       = tr_idx_req;
          p1_sel_lane_mask = tr_lane_mask_req;
          p1_sel_data      = tr_data_req;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Muxed generic wrapper ports
  // --------------------------------------------------------------------------
  logic [POLY_W-1:0]        p0_poly_id_mux, p1_poly_id_mux;
  logic                     p0_v_mux,       p1_v_mux;
  logic [3:0]               p0_wr_en_mux,   p1_wr_en_mux;
  logic [3:0][COEFF_W-1:0] p0_idx_mux,     p1_idx_mux;
  logic [3:0]               p0_lane_valid_mux, p1_lane_valid_mux;
  logic [3:0][W-1:0]        p0_data_mux,    p1_data_mux;

  client_owner_e            p0_read_owner_sel, p1_read_owner_sel;

  always_comb begin
    p0_poly_id_mux    = '0;
    p0_v_mux          = 1'b0;
    p0_wr_en_mux      = '0;
    p0_idx_mux        = '0;
    p0_lane_valid_mux = '0;
    p0_data_mux       = '0;

    p1_poly_id_mux    = '0;
    p1_v_mux          = 1'b0;
    p1_wr_en_mux      = '0;
    p1_idx_mux        = '0;
    p1_lane_valid_mux = '0;
    p1_data_mux       = '0;

    p0_read_owner_sel = OWNER_NONE;
    p1_read_owner_sel = OWNER_NONE;

    if (wipe_state_q == WIPE_POLY) begin
      p0_poly_id_mux    = wipe_poly_q;
      p0_v_mux          = 1'b1;
      p0_wr_en_mux      = 4'b1111;
      p0_idx_mux[0]     = wipe_base_idx + COEFF_W'(0);
      p0_idx_mux[1]     = wipe_base_idx + COEFF_W'(1);
      p0_idx_mux[2]     = wipe_base_idx + COEFF_W'(2);
      p0_idx_mux[3]     = wipe_base_idx + COEFF_W'(3);
      p0_data_mux       = '0;
    end else if (combo_any) begin
      p0_v_mux          = 1'b1;
      p1_v_mux          = 1'b1;
      p0_read_owner_sel = combo_owner;

      unique case (combo_owner)
        OWNER_PAU: begin
          p0_poly_id_mux    = pau_rd_poly_id;
          p0_idx_mux        = pau_rd_idx;
          p0_lane_valid_mux = pau_rd_lane_valid;
          p1_poly_id_mux    = pau_wr_poly_id;
          p1_wr_en_mux      = pau_wr_en;
          p1_idx_mux        = pau_wr_idx;
          p1_data_mux       = pau_wr_data;
        end
        OWNER_HSU: begin
          p0_poly_id_mux    = hsu_rd_poly_id;
          p0_idx_mux        = hsu_rd_idx;
          p0_lane_valid_mux = hsu_rd_lane_valid;
          p1_poly_id_mux    = hsu_wr_poly_id;
          p1_wr_en_mux      = hsu_wr_en;
          p1_idx_mux        = hsu_wr_idx;
          p1_data_mux       = hsu_wr_data;
        end
        OWNER_TR: begin
          p0_poly_id_mux    = tr_rd_poly_id;
          p0_idx_mux        = tr_rd_idx;
          p0_lane_valid_mux = tr_rd_lane_valid;
          p1_poly_id_mux    = tr_wr_poly_id;
          p1_wr_en_mux      = tr_wr_en;
          p1_idx_mux        = tr_wr_idx;
          p1_data_mux       = tr_wr_data;
        end
        default: begin
        end
      endcase
    end else begin
      unique case (p0_sel_owner)
        OWNER_PAU: begin
          p0_poly_id_mux = p0_sel_poly_id;
          p0_idx_mux     = p0_sel_idx;
          p0_v_mux       = 1'b1;
          if (p0_sel_kind == REQ_READ) begin
            p0_lane_valid_mux = p0_sel_lane_mask;
            p0_read_owner_sel = OWNER_PAU;
          end else if (p0_sel_kind == REQ_WRITE) begin
            p0_wr_en_mux = p0_sel_lane_mask;
            p0_data_mux  = p0_sel_data;
          end
        end
        OWNER_HSU: begin
          p0_poly_id_mux = p0_sel_poly_id;
          p0_idx_mux     = p0_sel_idx;
          p0_v_mux       = 1'b1;
          if (p0_sel_kind == REQ_READ) begin
            p0_lane_valid_mux = p0_sel_lane_mask;
            p0_read_owner_sel = OWNER_HSU;
          end else if (p0_sel_kind == REQ_WRITE) begin
            p0_wr_en_mux = p0_sel_lane_mask;
            p0_data_mux  = p0_sel_data;
          end
        end
        OWNER_TR: begin
          p0_poly_id_mux = p0_sel_poly_id;
          p0_idx_mux     = p0_sel_idx;
          p0_v_mux       = 1'b1;
          if (p0_sel_kind == REQ_READ) begin
            p0_lane_valid_mux = p0_sel_lane_mask;
            p0_read_owner_sel = OWNER_TR;
          end else if (p0_sel_kind == REQ_WRITE) begin
            p0_wr_en_mux = p0_sel_lane_mask;
            p0_data_mux  = p0_sel_data;
          end
        end
        default: begin
        end
      endcase

      unique case (p1_sel_owner)
        OWNER_PAU: begin
          p1_poly_id_mux = p1_sel_poly_id;
          p1_idx_mux     = p1_sel_idx;
          p1_v_mux       = 1'b1;
          if (p1_sel_kind == REQ_READ) begin
            p1_lane_valid_mux = p1_sel_lane_mask;
            p1_read_owner_sel = OWNER_PAU;
          end else if (p1_sel_kind == REQ_WRITE) begin
            p1_wr_en_mux = p1_sel_lane_mask;
            p1_data_mux  = p1_sel_data;
          end
        end
        OWNER_HSU: begin
          p1_poly_id_mux = p1_sel_poly_id;
          p1_idx_mux     = p1_sel_idx;
          p1_v_mux       = 1'b1;
          if (p1_sel_kind == REQ_READ) begin
            p1_lane_valid_mux = p1_sel_lane_mask;
            p1_read_owner_sel = OWNER_HSU;
          end else if (p1_sel_kind == REQ_WRITE) begin
            p1_wr_en_mux = p1_sel_lane_mask;
            p1_data_mux  = p1_sel_data;
          end
        end
        OWNER_TR: begin
          p1_poly_id_mux = p1_sel_poly_id;
          p1_idx_mux     = p1_sel_idx;
          p1_v_mux       = 1'b1;
          if (p1_sel_kind == REQ_READ) begin
            p1_lane_valid_mux = p1_sel_lane_mask;
            p1_read_owner_sel = OWNER_TR;
          end else if (p1_sel_kind == REQ_WRITE) begin
            p1_wr_en_mux = p1_sel_lane_mask;
            p1_data_mux  = p1_sel_data;
          end
        end
        default: begin
        end
      endcase
    end
  end

  logic p0_ready, p1_ready;
  logic p0_rd_valid_int, p1_rd_valid_int;
  logic [POLY_W-1:0]        p0_rd_poly_id_int, p1_rd_poly_id_int;
  logic [3:0][COEFF_W-1:0] p0_rd_idx_int,     p1_rd_idx_int;
  logic [3:0]               p0_rd_lane_valid_int, p1_rd_lane_valid_int;
  logic [3:0][W-1:0]        p0_rd_data_int,    p1_rd_data_int;

  poly_mem_wrapper_4bank #(
    .N         (NCOEFF),
    .W         (W),
    .NUM_POLYS (NUM_POLYS)
  ) u_poly_mem (
    .clk             (clk),
    .rst             (rst),
    .p0_poly_id_i    (p0_poly_id_mux),
    .p0_v_i          (p0_v_mux),
    .p0_wr_en_i      (p0_wr_en_mux),
    .p0_idx_i        (p0_idx_mux),
    .p0_lane_valid_i (p0_lane_valid_mux),
    .p0_data_i       (p0_data_mux),
    .p0_ready_o      (p0_ready),
    .p0_rd_valid_o   (p0_rd_valid_int),
    .p0_rd_poly_id_o (p0_rd_poly_id_int),
    .p0_rd_idx_o     (p0_rd_idx_int),
    .p0_rd_lane_valid_o(p0_rd_lane_valid_int),
    .p0_rd_data_o    (p0_rd_data_int),
    .p1_poly_id_i    (p1_poly_id_mux),
    .p1_v_i          (p1_v_mux),
    .p1_wr_en_i      (p1_wr_en_mux),
    .p1_idx_i        (p1_idx_mux),
    .p1_lane_valid_i (p1_lane_valid_mux),
    .p1_data_i       (p1_data_mux),
    .p1_ready_o      (p1_ready),
    .p1_rd_valid_o   (p1_rd_valid_int),
    .p1_rd_poly_id_o (p1_rd_poly_id_int),
    .p1_rd_idx_o     (p1_rd_idx_int),
    .p1_rd_lane_valid_o(p1_rd_lane_valid_int),
    .p1_rd_data_o    (p1_rd_data_int),
    .fault_o         (poly_fault),
    .fault_code_o    (poly_fault_code)
  );

  logic p0_read_fire, p1_read_fire;
  assign p0_read_fire = p0_v_mux && p0_ready && (|p0_lane_valid_mux) && ~(|p0_wr_en_mux);
  assign p1_read_fire = p1_v_mux && p1_ready && (|p1_lane_valid_mux) && ~(|p1_wr_en_mux);

  // --------------------------------------------------------------------------
  // Dual-port seed / protocol store
  // --------------------------------------------------------------------------
  logic [SEED_W-1:0] hsu_seed_rdata_int, tr_seed_rdata_int;
  logic              hsu_seed_read_fire, tr_seed_read_fire;
  logic              hsu_seed_read_fire_q, tr_seed_read_fire_q;

  logic               seed_a_we_mux, seed_b_we_mux;
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

  assign hsu_seed_ready     = ~wipe_active;
  assign tr_seed_ready      = ~wipe_active;
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
  // Final stall generation
  // --------------------------------------------------------------------------
  logic combo_can_fire;
  assign combo_can_fire = p0_ready && p1_ready;

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
      if (pau_single_req) begin
        if (p0_sel_owner == OWNER_PAU) pau_stall = ~p0_ready;
        else if (p1_sel_owner == OWNER_PAU) pau_stall = ~p1_ready;
        else pau_stall = 1'b1;
      end

      if (hsu_poly_rd_unsupported) begin
        hsu_stall = 1'b1;
      end else if (hsu_single_req) begin
        if (p0_sel_owner == OWNER_HSU) hsu_stall = ~p0_ready;
        else if (p1_sel_owner == OWNER_HSU) hsu_stall = ~p1_ready;
        else hsu_stall = 1'b1;
      end

      if (tr_single_req) begin
        if (p0_sel_owner == OWNER_TR) tr_stall = ~p0_ready;
        else if (p1_sel_owner == OWNER_TR) tr_stall = ~p1_ready;
        else tr_stall = 1'b1;
      end
    end
  end

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

    if (p0_rd_valid_int) begin
      unique case (p0_rd_owner_q)
        OWNER_PAU: begin
          pau_rd_valid        = 1'b1;
          pau_rd_poly_id_o    = p0_rd_poly_id_int;
          pau_rd_idx_o        = p0_rd_idx_int;
          pau_rd_lane_valid_o = p0_rd_lane_valid_int;
          pau_rd_data         = p0_rd_data_int;
        end
        OWNER_HSU: begin
          hsu_rd_valid        = 1'b1;
          hsu_rd_poly_id_o    = p0_rd_poly_id_int;
          hsu_rd_idx_o        = p0_rd_idx_int;
          hsu_rd_lane_valid_o = p0_rd_lane_valid_int;
          hsu_rd_data         = p0_rd_data_int;
        end
        OWNER_TR: begin
          tr_rd_valid         = 1'b1;
          tr_rd_poly_id_o     = p0_rd_poly_id_int;
          tr_rd_idx_o         = p0_rd_idx_int;
          tr_rd_lane_valid_o  = p0_rd_lane_valid_int;
          tr_rd_data          = p0_rd_data_int;
        end
        default: begin
        end
      endcase
    end

    if (p1_rd_valid_int) begin
      unique case (p1_rd_owner_q)
        OWNER_PAU: begin
          pau_rd_valid        = 1'b1;
          pau_rd_poly_id_o    = p1_rd_poly_id_int;
          pau_rd_idx_o        = p1_rd_idx_int;
          pau_rd_lane_valid_o = p1_rd_lane_valid_int;
          pau_rd_data         = p1_rd_data_int;
        end
        OWNER_HSU: begin
          hsu_rd_valid        = 1'b1;
          hsu_rd_poly_id_o    = p1_rd_poly_id_int;
          hsu_rd_idx_o        = p1_rd_idx_int;
          hsu_rd_lane_valid_o = p1_rd_lane_valid_int;
          hsu_rd_data         = p1_rd_data_int;
        end
        OWNER_TR: begin
          tr_rd_valid         = 1'b1;
          tr_rd_poly_id_o     = p1_rd_poly_id_int;
          tr_rd_idx_o         = p1_rd_idx_int;
          tr_rd_lane_valid_o  = p1_rd_lane_valid_int;
          tr_rd_data          = p1_rd_data_int;
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
        if (p0_ready) begin
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
      wipe_state_q        <= WIPE_IDLE;
      wipe_poly_q         <= '0;
      wipe_row_q          <= '0;
      wipe_seed_q         <= '0;
      p0_rd_owner_q       <= OWNER_NONE;
      p1_rd_owner_q       <= OWNER_NONE;
      hsu_seed_read_fire_q <= 1'b0;
      tr_seed_read_fire_q  <= 1'b0;
      mem_fault_q         <= 1'b0;
      mem_fault_code_q    <= 3'b000;
    end else begin
      wipe_state_q        <= wipe_state_d;
      wipe_poly_q         <= wipe_poly_d;
      wipe_row_q          <= wipe_row_d;
      wipe_seed_q         <= wipe_seed_d;

      if (p0_read_fire) p0_rd_owner_q <= p0_read_owner_sel;
      if (p1_read_fire) p1_rd_owner_q <= p1_read_owner_sel;

      hsu_seed_read_fire_q <= hsu_seed_read_fire;
      tr_seed_read_fire_q  <= tr_seed_read_fire;
      mem_fault_q         <= poly_fault;
      mem_fault_code_q    <= poly_fault ? poly_fault_code : 3'b000;
    end
  end

endmodule
