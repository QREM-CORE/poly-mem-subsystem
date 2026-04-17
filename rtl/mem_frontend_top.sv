/*
 * Module Name: mem_frontend_top
 * Author(s): Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Top-level memory frontend for the QREM banked polynomial memory.
 *
 * Architectural intent (v0.7-aligned):
 *   - Centralize polynomial-memory arbitration.
 *   - Treat PAU, HSU/poly-writer, and Transcoder as peers on one shared
 *     vector request plane.
 *   - Keep the seed store separate from polynomial-memory banking.
 *   - Preserve strict PAU > HSU > Transcoder priority.
 *
 * Why this replaced the old version:
 *   The old frontend only modeled scalar coefficient requests for PAU/HSU and
 *   let the Transcoder bypass that logic through a different path. That was
 *   incompatible with the actual architecture:
 *     - PAU needs a 4-lane vector interface for NTT / ADD / CWM drain
 *     - HSU writes sampled coefficients in 4-coefficient groups
 *     - Transcoder is another shared memory client, not a bypass path
 *     - read responses must be explicitly owned/tagged, not broadcast
 */

module mem_frontend_top #(
  parameter int NUM_POLYS  = 32,
  parameter int NCOEFF     = 256,
  parameter int W          = 16,
  parameter int SEED_DEPTH = 16,
  parameter int SEED_W     = 64
)(
  input  logic clk,
  input  logic rst_n,

  // ------------------------------------------------------------
  // Security wipe
  // ------------------------------------------------------------
  input  logic wipe_i,
  output logic wipe_done_o,

  // ============================================================
  // PAU interface (vector request/response)
  // ============================================================
  input  logic                               pau_req,
  input  logic [$clog2(NUM_POLYS)-1:0]       pau_poly_id,
  input  logic                               pau_rd_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     pau_rd_idx,
  input  logic [3:0]                         pau_rd_lane_valid,
  input  logic [3:0]                         pau_wr_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     pau_wr_idx,
  input  logic [3:0][W-1:0]                  pau_wr_data,
  output logic                               pau_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       pau_rd_poly_id,
  output logic [3:0][$clog2(NCOEFF)-1:0]     pau_rd_idx_o,
  output logic [3:0]                         pau_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  pau_rd_data,
  output logic                               pau_stall,

  // ============================================================
  // HSU / Poly Memory Writer interface
  // ============================================================
  input  logic                               hsu_req,
  input  logic [$clog2(NUM_POLYS)-1:0]       hsu_poly_id,
  input  logic                               hsu_rd_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     hsu_rd_idx,
  input  logic [3:0]                         hsu_rd_lane_valid,
  input  logic [3:0]                         hsu_wr_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     hsu_wr_idx,
  input  logic [3:0][W-1:0]                  hsu_wr_data,
  output logic                               hsu_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       hsu_rd_poly_id,
  output logic [3:0][$clog2(NCOEFF)-1:0]     hsu_rd_idx_o,
  output logic [3:0]                         hsu_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  hsu_rd_data,
  output logic                               hsu_stall,

  // ============================================================
  // Transcoder interface
  // ============================================================
  input  logic                               tr_req,
  input  logic [$clog2(NUM_POLYS)-1:0]       tr_poly_id,
  input  logic                               tr_rd_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     tr_rd_idx,
  input  logic [3:0]                         tr_rd_lane_valid,
  input  logic [3:0]                         tr_wr_en,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     tr_wr_idx,
  input  logic [3:0][W-1:0]                  tr_wr_data,
  output logic                               tr_rd_valid,
  output logic [$clog2(NUM_POLYS)-1:0]       tr_rd_poly_id,
  output logic [3:0][$clog2(NCOEFF)-1:0]     tr_rd_idx_o,
  output logic [3:0]                         tr_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  tr_rd_data,
  output logic                               tr_stall,

  // ============================================================
  // Seed / protocol store port
  // ------------------------------------------------------------
  // This is intentionally independent from the polynomial-memory
  // arbitration path. The top-level seed reader/writer bridge can sit
  // above this port and multiplex HSU / Transcoder / controller traffic.
  // ============================================================
  input  logic                               seed_req,
  input  logic                               seed_we,
  input  logic [$clog2(SEED_DEPTH)-1:0]      seed_addr,
  input  logic [SEED_W-1:0]                  seed_wdata,
  output logic                               seed_ready,
  output logic                               seed_rvalid,
  output logic [SEED_W-1:0]                  seed_rdata
);

  typedef enum logic [1:0] {
    RD_OWNER_NONE = 2'd0,
    RD_OWNER_PAU  = 2'd1,
    RD_OWNER_HSU  = 2'd2,
    RD_OWNER_TR   = 2'd3
  } rd_owner_e;

  logic                               grant_pau;
  logic                               grant_hsu;
  logic                               grant_tr;

  logic                               poly_req_mux;
  logic [$clog2(NUM_POLYS)-1:0]       poly_id_mux;
  logic                               poly_rd_en_mux;
  logic [3:0][$clog2(NCOEFF)-1:0]     poly_rd_idx_mux;
  logic [3:0]                         poly_rd_lane_valid_mux;
  logic [3:0]                         poly_wr_en_mux;
  logic [3:0][$clog2(NCOEFF)-1:0]     poly_wr_idx_mux;
  logic [3:0][W-1:0]                  poly_wr_data_mux;

  logic                               poly_ready;
  logic                               poly_rd_valid;
  logic [$clog2(NUM_POLYS)-1:0]       poly_rd_poly_id;
  logic [3:0][$clog2(NCOEFF)-1:0]     poly_rd_idx_rsp;
  logic [3:0]                         poly_rd_lane_valid_rsp;
  logic [3:0][W-1:0]                  poly_rd_data_rsp;

  logic                               accepted_read_fire;
  rd_owner_e                          rd_owner_q, rd_owner_d;

  // ------------------------------------------------------------
  // Shared owner selection
  // ------------------------------------------------------------
  mem_arbiter u_arbiter (
    .pau_req_i    (pau_req),
    .hsu_req_i    (hsu_req),
    .tr_req_i     (tr_req),
    .mem_ready_i  (poly_ready),
    .grant_pau_o  (grant_pau),
    .grant_hsu_o  (grant_hsu),
    .grant_tr_o   (grant_tr),
    .pau_stall_o  (pau_stall),
    .hsu_stall_o  (hsu_stall),
    .tr_stall_o   (tr_stall)
  );

  // ------------------------------------------------------------
  // Request mux
  // ------------------------------------------------------------
  always_comb begin
    poly_req_mux           = 1'b0;
    poly_id_mux            = '0;
    poly_rd_en_mux         = 1'b0;
    poly_rd_idx_mux        = '0;
    poly_rd_lane_valid_mux = '0;
    poly_wr_en_mux         = '0;
    poly_wr_idx_mux        = '0;
    poly_wr_data_mux       = '0;

    if (grant_pau) begin
      poly_req_mux           = pau_req;
      poly_id_mux            = pau_poly_id;
      poly_rd_en_mux         = pau_rd_en;
      poly_rd_idx_mux        = pau_rd_idx;
      poly_rd_lane_valid_mux = pau_rd_lane_valid;
      poly_wr_en_mux         = pau_wr_en;
      poly_wr_idx_mux        = pau_wr_idx;
      poly_wr_data_mux       = pau_wr_data;
    end
    else if (grant_hsu) begin
      poly_req_mux           = hsu_req;
      poly_id_mux            = hsu_poly_id;
      poly_rd_en_mux         = hsu_rd_en;
      poly_rd_idx_mux        = hsu_rd_idx;
      poly_rd_lane_valid_mux = hsu_rd_lane_valid;
      poly_wr_en_mux         = hsu_wr_en;
      poly_wr_idx_mux        = hsu_wr_idx;
      poly_wr_data_mux       = hsu_wr_data;
    end
    else if (grant_tr) begin
      poly_req_mux           = tr_req;
      poly_id_mux            = tr_poly_id;
      poly_rd_en_mux         = tr_rd_en;
      poly_rd_idx_mux        = tr_rd_idx;
      poly_rd_lane_valid_mux = tr_rd_lane_valid;
      poly_wr_en_mux         = tr_wr_en;
      poly_wr_idx_mux        = tr_wr_idx;
      poly_wr_data_mux       = tr_wr_data;
    end
  end

  assign accepted_read_fire = poly_req_mux && poly_rd_en_mux && poly_ready;

  always_comb begin
    rd_owner_d = rd_owner_q;

    if (accepted_read_fire) begin
      if (grant_pau)      rd_owner_d = RD_OWNER_PAU;
      else if (grant_hsu) rd_owner_d = RD_OWNER_HSU;
      else if (grant_tr)  rd_owner_d = RD_OWNER_TR;
      else                rd_owner_d = RD_OWNER_NONE;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_owner_q <= RD_OWNER_NONE;
    end else begin
      rd_owner_q <= rd_owner_d;
    end
  end

  // ------------------------------------------------------------
  // Memory core
  // ------------------------------------------------------------
  poly_mem_subsystem #(
    .NUM_POLYS  (NUM_POLYS),
    .NCOEFF     (NCOEFF),
    .W          (W),
    .SEED_DEPTH (SEED_DEPTH),
    .SEED_W     (SEED_W)
  ) u_mem (
    .clk                (clk),
    .rst_n              (rst_n),
    .wipe_i             (wipe_i),
    .wipe_done_o        (wipe_done_o),
    .poly_req_i         (poly_req_mux),
    .poly_id_i          (poly_id_mux),
    .poly_rd_en_i       (poly_rd_en_mux),
    .poly_ready_o       (poly_ready),
    .poly_rd_idx_i      (poly_rd_idx_mux),
    .poly_rd_lane_valid_i(poly_rd_lane_valid_mux),
    .poly_rd_valid_o    (poly_rd_valid),
    .poly_rd_poly_id_o  (poly_rd_poly_id),
    .poly_rd_idx_o      (poly_rd_idx_rsp),
    .poly_rd_lane_valid_o(poly_rd_lane_valid_rsp),
    .poly_rd_data_o     (poly_rd_data_rsp),
    .poly_wr_en_i       (poly_wr_en_mux),
    .poly_wr_idx_i      (poly_wr_idx_mux),
    .poly_wr_data_i     (poly_wr_data_mux),
    .seed_req_i         (seed_req),
    .seed_we_i          (seed_we),
    .seed_addr_i        (seed_addr),
    .seed_wdata_i       (seed_wdata),
    .seed_ready_o       (seed_ready),
    .seed_rvalid_o      (seed_rvalid),
    .seed_rdata_o       (seed_rdata)
  );

  // ------------------------------------------------------------
  // Response routing
  // ------------------------------------------------------------
  always_comb begin
    pau_rd_valid        = 1'b0;
    pau_rd_poly_id      = '0;
    pau_rd_idx_o        = '0;
    pau_rd_lane_valid_o = '0;
    pau_rd_data         = '0;

    hsu_rd_valid        = 1'b0;
    hsu_rd_poly_id      = '0;
    hsu_rd_idx_o        = '0;
    hsu_rd_lane_valid_o = '0;
    hsu_rd_data         = '0;

    tr_rd_valid         = 1'b0;
    tr_rd_poly_id       = '0;
    tr_rd_idx_o         = '0;
    tr_rd_lane_valid_o  = '0;
    tr_rd_data          = '0;

    if (poly_rd_valid) begin
      unique case (rd_owner_q)
        RD_OWNER_PAU: begin
          pau_rd_valid        = 1'b1;
          pau_rd_poly_id      = poly_rd_poly_id;
          pau_rd_idx_o        = poly_rd_idx_rsp;
          pau_rd_lane_valid_o = poly_rd_lane_valid_rsp;
          pau_rd_data         = poly_rd_data_rsp;
        end

        RD_OWNER_HSU: begin
          hsu_rd_valid        = 1'b1;
          hsu_rd_poly_id      = poly_rd_poly_id;
          hsu_rd_idx_o        = poly_rd_idx_rsp;
          hsu_rd_lane_valid_o = poly_rd_lane_valid_rsp;
          hsu_rd_data         = poly_rd_data_rsp;
        end

        RD_OWNER_TR: begin
          tr_rd_valid         = 1'b1;
          tr_rd_poly_id       = poly_rd_poly_id;
          tr_rd_idx_o         = poly_rd_idx_rsp;
          tr_rd_lane_valid_o  = poly_rd_lane_valid_rsp;
          tr_rd_data          = poly_rd_data_rsp;
        end

        default: begin
        end
      endcase
    end
  end

endmodule
