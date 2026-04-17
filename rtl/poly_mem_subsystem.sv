/*
 * Module Name: poly_mem_subsystem
 * Author(s): Mavra Muzmmal, Quardin Lyttle, Salwan Aldhahab
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Reference:
 *   "Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"
 *   H. Jung, Q. D. Truong, H. Lee — IEEE OJCAS 2025
 *
 * Description:
 *   Complete polynomial memory subsystem for the QREM core, matching the
 *   reference architecture's Memory Subsystem block:
 *
 *     ┌──────────────────────────────────────────────┐
 *     │              Memory Subsystem                │
 *     │  ┌────────────┐                              │
 *     │  │ Arbitrator │  PAU > HSU > Transcoder      │
 *     │  └─────┬──────┘                              │
 *     │        │                                     │
 *     │  ┌─────▼───────────────────────┐             │
 *     │  │ Poly Port A (read path)     │──┐          │
 *     │  │ Poly Port B (write path)    │──┤──4 RAMs  │
 *     │  └─────────────────────────────┘  │          │
 *     │                                   │          │
 *     │  ┌─────────────────────────────┐  │          │
 *     │  │ Seed Port                   │──┤          │
 *     │  │ Seed & Protocol Store       │──┘          │
 *     │  └─────────────────────────────┘             │
 *     └──────────────────────────────────────────────┘
 *
 * Clients:
 *   - PAU (Polynomial Arithmetic Unit): Highest priority. Drives 4-lane
 *     vector requests via the external CMI adapter for conflict-free
 *     NTT butterfly / CWM / ADD drain access patterns.
 *   - HSU (Hash Sampling Unit): Mid priority. Writes sampled coefficients
 *     in 4-coefficient groups via the Poly Stream Writer bridge.
 *   - Transcoder: Lowest priority. ByteEncode/Decode and Compress/Decompress
 *     operations require sequential polynomial memory access.
 *
 * Interface contract:
 *   - All three clients present 4-lane vector requests.
 *   - Only one client is granted access per cycle (strict priority).
 *   - Read responses are tagged and routed exclusively to the accepted
 *     read's originating client.
 *   - The seed port is independent from polynomial-memory arbitration.
 *   - Security wipe zeroes both polynomial and seed memory; all clients
 *     are stalled during wipe.
 */

module poly_mem_subsystem #(
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
  // ============================================================
  input  logic                               seed_req,
  input  logic                               seed_we,
  input  logic [$clog2(SEED_DEPTH)-1:0]      seed_addr,
  input  logic [SEED_W-1:0]                  seed_wdata,
  output logic                               seed_ready,
  output logic                               seed_rvalid,
  output logic [SEED_W-1:0]                  seed_rdata
);

  // ============================================================
  // Internal constants
  // ============================================================
  localparam int NUM_BANKS           = 4;
  localparam int COEFF_W             = $clog2(NCOEFF);
  localparam int ROWS_PER_POLY_BANK  = NCOEFF / NUM_BANKS;
  localparam int ROW_W               = $clog2(ROWS_PER_POLY_BANK);
  localparam int SEED_AW             = $clog2(SEED_DEPTH);

  // ============================================================
  // Read-response owner tracking
  // ============================================================
  typedef enum logic [1:0] {
    RD_OWNER_NONE = 2'd0,
    RD_OWNER_PAU  = 2'd1,
    RD_OWNER_HSU  = 2'd2,
    RD_OWNER_TR   = 2'd3
  } rd_owner_e;

  rd_owner_e rd_owner_q, rd_owner_d;

  // ============================================================
  // Wipe FSM state
  // ============================================================
  typedef enum logic [1:0] {
    WIPE_IDLE  = 2'd0,
    WIPE_POLY  = 2'd1,
    WIPE_SEED  = 2'd2,
    WIPE_DONE  = 2'd3
  } wipe_state_e;

  wipe_state_e wipe_state_q, wipe_state_d;
  logic [$clog2(NUM_POLYS)-1:0] wipe_poly_q, wipe_poly_d;
  logic [ROW_W-1:0]             wipe_row_q,  wipe_row_d;
  logic [SEED_AW-1:0]           wipe_seed_q, wipe_seed_d;

  // ============================================================
  // Arbitrator signals
  // ============================================================
  logic grant_pau, grant_hsu, grant_tr;
  logic pau_stall_arb, hsu_stall_arb, tr_stall_arb;

  // ============================================================
  // Internal memory-plane signals
  // ============================================================
  // Arbitrated (client-muxed) signals
  logic                               poly_req_arb;
  logic [$clog2(NUM_POLYS)-1:0]       poly_id_arb;
  logic                               poly_rd_en_arb;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_arb;
  logic [3:0]                         poly_rd_lane_valid_arb;
  logic [3:0]                         poly_wr_en_arb;
  logic [3:0][COEFF_W-1:0]            poly_wr_idx_arb;
  logic [3:0][W-1:0]                  poly_wr_data_arb;

  // Wipe-muxed signals driving the memory wrapper
  logic                               poly_req_mux;
  logic [$clog2(NUM_POLYS)-1:0]       poly_id_mux;
  logic                               poly_rd_en_mux;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_mux;
  logic [3:0]                         poly_rd_lane_valid_mux;
  logic [3:0]                         poly_wr_en_mux;
  logic [3:0][COEFF_W-1:0]            poly_wr_idx_mux;
  logic [3:0][W-1:0]                  poly_wr_data_mux;

  // Wrapper response signals
  logic                               poly_ready;
  logic                               poly_rd_valid;
  logic [$clog2(NUM_POLYS)-1:0]       poly_rd_poly_id;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_rsp;
  logic [3:0]                         poly_rd_lane_valid_rsp;
  logic [3:0][W-1:0]                  poly_rd_data_rsp;

  // Seed internal signals
  logic                               seed_we_mux;
  logic [SEED_AW-1:0]                 seed_addr_mux;
  logic [SEED_W-1:0]                  seed_wdata_mux;
  logic [SEED_W-1:0]                  seed_rdata_int;
  logic                               seed_read_fire;
  logic                               seed_read_fire_q;

  logic                               accepted_read_fire;
  logic                               wipe_active;
  logic [COEFF_W-1:0]                 wipe_base_idx;

  assign wipe_active   = (wipe_state_q != WIPE_IDLE);
  assign wipe_base_idx = COEFF_W'({wipe_row_q, 2'b00});

  // ============================================================
  // Arbitrator
  //
  // During wipe, client requests are gated so no grants are issued.
  // ============================================================
  logic pau_req_gated, hsu_req_gated, tr_req_gated;

  assign pau_req_gated = pau_req & ~wipe_active;
  assign hsu_req_gated = hsu_req & ~wipe_active;
  assign tr_req_gated  = tr_req  & ~wipe_active;

  mem_arbiter u_arbiter (
    .pau_req_i    (pau_req_gated),
    .hsu_req_i    (hsu_req_gated),
    .tr_req_i     (tr_req_gated),
    .mem_ready_i  (poly_ready),
    .grant_pau_o  (grant_pau),
    .grant_hsu_o  (grant_hsu),
    .grant_tr_o   (grant_tr),
    .pau_stall_o  (pau_stall_arb),
    .hsu_stall_o  (hsu_stall_arb),
    .tr_stall_o   (tr_stall_arb)
  );

  // Client stalls: arbiter stall during normal operation, forced stall
  // for any requesting client during wipe.
  assign pau_stall = wipe_active ? pau_req : pau_stall_arb;
  assign hsu_stall = wipe_active ? hsu_req : hsu_stall_arb;
  assign tr_stall  = wipe_active ? tr_req  : tr_stall_arb;

  // ============================================================
  // Request mux (winning client → arbitrated request)
  // ============================================================
  always_comb begin
    poly_req_arb           = 1'b0;
    poly_id_arb            = '0;
    poly_rd_en_arb         = 1'b0;
    poly_rd_idx_arb        = '0;
    poly_rd_lane_valid_arb = '0;
    poly_wr_en_arb         = '0;
    poly_wr_idx_arb        = '0;
    poly_wr_data_arb       = '0;

    if (grant_pau) begin
      poly_req_arb           = pau_req;
      poly_id_arb            = pau_poly_id;
      poly_rd_en_arb         = pau_rd_en;
      poly_rd_idx_arb        = pau_rd_idx;
      poly_rd_lane_valid_arb = pau_rd_lane_valid;
      poly_wr_en_arb         = pau_wr_en;
      poly_wr_idx_arb        = pau_wr_idx;
      poly_wr_data_arb       = pau_wr_data;
    end
    else if (grant_hsu) begin
      poly_req_arb           = hsu_req;
      poly_id_arb            = hsu_poly_id;
      poly_rd_en_arb         = hsu_rd_en;
      poly_rd_idx_arb        = hsu_rd_idx;
      poly_rd_lane_valid_arb = hsu_rd_lane_valid;
      poly_wr_en_arb         = hsu_wr_en;
      poly_wr_idx_arb        = hsu_wr_idx;
      poly_wr_data_arb       = hsu_wr_data;
    end
    else if (grant_tr) begin
      poly_req_arb           = tr_req;
      poly_id_arb            = tr_poly_id;
      poly_rd_en_arb         = tr_rd_en;
      poly_rd_idx_arb        = tr_rd_idx;
      poly_rd_lane_valid_arb = tr_rd_lane_valid;
      poly_wr_en_arb         = tr_wr_en;
      poly_wr_idx_arb        = tr_wr_idx;
      poly_wr_data_arb       = tr_wr_data;
    end
  end

  // ============================================================
  // Wipe / normal mux → signals to Poly Port A/B and Seed Port
  // ============================================================
  always_comb begin
    // Default: pass arbitrated client request
    poly_req_mux           = poly_req_arb;
    poly_id_mux            = poly_id_arb;
    poly_rd_en_mux         = poly_rd_en_arb;
    poly_rd_idx_mux        = poly_rd_idx_arb;
    poly_rd_lane_valid_mux = poly_rd_lane_valid_arb;
    poly_wr_en_mux         = poly_wr_en_arb;
    poly_wr_idx_mux        = poly_wr_idx_arb;
    poly_wr_data_mux       = poly_wr_data_arb;

    seed_we_mux            = seed_we;
    seed_addr_mux          = seed_addr;
    seed_wdata_mux         = seed_wdata;

    seed_ready             = 1'b1;
    wipe_done_o            = 1'b0;

    case (wipe_state_q)
      WIPE_IDLE: begin
        // Normal operation: arbitrated client owns the memory plane.
      end

      WIPE_POLY: begin
        // Wipe writes one full row (4 coeffs) of one polynomial per cycle.
        // Consecutive groups of 4 indices always map to distinct banks
        // under the CMI bit-pair-sum scheme, so no write conflict occurs.
        poly_req_mux           = 1'b1;
        poly_id_mux            = wipe_poly_q;
        poly_rd_en_mux         = 1'b0;
        poly_rd_idx_mux[0]     = wipe_base_idx + COEFF_W'(0);
        poly_rd_idx_mux[1]     = wipe_base_idx + COEFF_W'(1);
        poly_rd_idx_mux[2]     = wipe_base_idx + COEFF_W'(2);
        poly_rd_idx_mux[3]     = wipe_base_idx + COEFF_W'(3);
        poly_rd_lane_valid_mux = 4'b0000;
        poly_wr_en_mux         = 4'b1111;
        poly_wr_idx_mux        = poly_rd_idx_mux;
        poly_wr_data_mux       = '0;

        seed_ready             = 1'b0;
      end

      WIPE_SEED: begin
        poly_req_mux           = 1'b0;
        poly_rd_en_mux         = 1'b0;
        poly_rd_idx_mux        = '0;
        poly_rd_lane_valid_mux = '0;
        poly_wr_en_mux         = '0;
        poly_wr_idx_mux        = '0;
        poly_wr_data_mux       = '0;

        seed_we_mux            = 1'b1;
        seed_addr_mux          = wipe_seed_q;
        seed_wdata_mux         = '0;

        seed_ready             = 1'b0;
      end

      WIPE_DONE: begin
        poly_req_mux           = 1'b0;
        poly_rd_en_mux         = 1'b0;
        poly_rd_idx_mux        = '0;
        poly_rd_lane_valid_mux = '0;
        poly_wr_en_mux         = '0;
        poly_wr_idx_mux        = '0;
        poly_wr_data_mux       = '0;

        seed_we_mux            = 1'b0;
        seed_addr_mux          = '0;
        seed_wdata_mux         = '0;

        seed_ready             = 1'b0;
        wipe_done_o            = 1'b1;
      end

      default: begin
      end
    endcase
  end

  // ============================================================
  // Read-response owner tracking
  // ============================================================
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

  // ============================================================
  // Poly Port A (read) / Poly Port B (write) — 4 banked Poly RAMs
  //
  // The wrapper uses CMI bit-pair-sum bank mapping for conflict-free
  // NTT butterfly access, and routes reads to Port A / writes to
  // Port B of each dual-port bank.
  // ============================================================
  poly_mem_wrapper_4bank #(
    .N         (NCOEFF),
    .W         (W),
    .NUM_POLYS (NUM_POLYS)
  ) u_poly_mem (
    .clk             (clk),
    .rst_n           (rst_n),
    .poly_id_i       (poly_id_mux),
    .v_i             (poly_req_mux),
    .rd_en_i         (poly_rd_en_mux),
    .ready_o         (poly_ready),
    .rd_idx_i        (poly_rd_idx_mux),
    .rd_lane_valid_i (poly_rd_lane_valid_mux),
    .rd_valid_o      (poly_rd_valid),
    .rd_poly_id_o    (poly_rd_poly_id),
    .rd_idx_o        (poly_rd_idx_rsp),
    .rd_lane_valid_o (poly_rd_lane_valid_rsp),
    .rd_data_o       (poly_rd_data_rsp),
    .wr_en_i         (poly_wr_en_mux),
    .wr_idx_i        (poly_wr_idx_mux),
    .wr_data_i       (poly_wr_data_mux)
  );

  // ============================================================
  // Seed and Protocol Store
  // ============================================================
  assign seed_read_fire = (wipe_state_q == WIPE_IDLE) && seed_req && !seed_we;

  seed_ram #(
    .DEPTH  (SEED_DEPTH),
    .W      (SEED_W),
    .ADDR_W (SEED_AW)
  ) u_seed_ram (
    .clk   (clk),
    .rst_n (rst_n),
    .we    (seed_we_mux),
    .addr  (seed_addr_mux),
    .wdata (seed_wdata_mux),
    .rdata (seed_rdata_int)
  );

  assign seed_rdata  = seed_rdata_int;
  assign seed_rvalid = seed_read_fire_q;

  // ============================================================
  // Response routing — read data to the accepted read's originator
  // ============================================================
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

  // ============================================================
  // Wipe FSM
  //
  // Sequence: IDLE → WIPE_POLY (zero all polynomial slots) →
  //           WIPE_SEED (zero seed store) → DONE → IDLE
  // ============================================================
  always_comb begin
    wipe_state_d = wipe_state_q;
    wipe_poly_d  = wipe_poly_q;
    wipe_row_d   = wipe_row_q;
    wipe_seed_d  = wipe_seed_q;

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
        if (poly_ready) begin
          if ((wipe_poly_q == NUM_POLYS-1) && (wipe_row_q == ROWS_PER_POLY_BANK-1)) begin
            wipe_state_d = WIPE_SEED;
            wipe_seed_d  = '0;
          end else if (wipe_row_q == ROWS_PER_POLY_BANK-1) begin
            wipe_poly_d = wipe_poly_q + 1'b1;
            wipe_row_d  = '0;
          end else begin
            wipe_row_d = wipe_row_q + 1'b1;
          end
        end
      end

      WIPE_SEED: begin
        if (wipe_seed_q == SEED_DEPTH-1) begin
          wipe_state_d = WIPE_DONE;
        end else begin
          wipe_seed_d = wipe_seed_q + 1'b1;
        end
      end

      WIPE_DONE: begin
        wipe_state_d = WIPE_IDLE;
      end

      default: begin
        wipe_state_d = WIPE_IDLE;
        wipe_poly_d  = '0;
        wipe_row_d   = '0;
        wipe_seed_d  = '0;
      end
    endcase
  end

  // ============================================================
  // Sequential state
  // ============================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wipe_state_q     <= WIPE_IDLE;
      wipe_poly_q      <= '0;
      wipe_row_q       <= '0;
      wipe_seed_q      <= '0;
      rd_owner_q       <= RD_OWNER_NONE;
      seed_read_fire_q <= 1'b0;
    end else begin
      wipe_state_q     <= wipe_state_d;
      wipe_poly_q      <= wipe_poly_d;
      wipe_row_q       <= wipe_row_d;
      wipe_seed_q      <= wipe_seed_d;
      rd_owner_q       <= rd_owner_d;
      seed_read_fire_q <= seed_read_fire;
    end
  end

endmodule
