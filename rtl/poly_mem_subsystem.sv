/*
 * Module Name: poly_mem_subsystem
 * Author(s): Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Vectorized polynomial-memory subsystem for the QREM core.
 *
 * Architectural role:
 *   - Owns the banked polynomial memory and the lightweight seed store.
 *   - Exposes a single 4-lane polynomial-memory request port.
 *   - Performs security wipe of both polynomial memory and seed memory.
 *
 * Why this file changed:
 *   The older subsystem modeled separate scalar "NTT / PM / PU" paths with
 *   Port-A / Port-B ownership rules baked into the interface. That no longer
 *   matches the v0.7 architecture, where:
 *     - PAU drives a vector CMI-style request stream
 *     - HSU reaches memory through a poly-memory writer bridge
 *     - Transcoder is another shared client
 *     - arbitration is strict and centralized before the memory core
 *
 * New contract:
 *   One accepted vector transaction per cycle enters the polynomial memory
 *   wrapper. The wrapper itself still checks lane-level bank conflicts and
 *   returns a 1-cycle read response with aligned metadata.
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

  // ------------------------------------------------------------
  // Shared polynomial-memory request plane
  // ------------------------------------------------------------
  input  logic                               poly_req_i,
  input  logic [$clog2(NUM_POLYS)-1:0]       poly_id_i,
  input  logic                               poly_rd_en_i,
  output logic                               poly_ready_o,

  input  logic [3:0][$clog2(NCOEFF)-1:0]     poly_rd_idx_i,
  input  logic [3:0]                         poly_rd_lane_valid_i,

  output logic                               poly_rd_valid_o,
  output logic [$clog2(NUM_POLYS)-1:0]       poly_rd_poly_id_o,
  output logic [3:0][$clog2(NCOEFF)-1:0]     poly_rd_idx_o,
  output logic [3:0]                         poly_rd_lane_valid_o,
  output logic [3:0][W-1:0]                  poly_rd_data_o,

  input  logic [3:0]                         poly_wr_en_i,
  input  logic [3:0][$clog2(NCOEFF)-1:0]     poly_wr_idx_i,
  input  logic [3:0][W-1:0]                  poly_wr_data_i,

  // ------------------------------------------------------------
  // Seed / protocol store
  // ------------------------------------------------------------
  input  logic                               seed_req_i,
  input  logic                               seed_we_i,
  input  logic [$clog2(SEED_DEPTH)-1:0]      seed_addr_i,
  input  logic [SEED_W-1:0]                  seed_wdata_i,
  output logic                               seed_ready_o,
  output logic                               seed_rvalid_o,
  output logic [SEED_W-1:0]                  seed_rdata_o
);

  localparam int NUM_BANKS           = 4;
  localparam int COEFF_W             = $clog2(NCOEFF);
  localparam int ROWS_PER_POLY_BANK  = NCOEFF / NUM_BANKS;
  localparam int ROW_W               = $clog2(ROWS_PER_POLY_BANK);
  localparam int SEED_AW             = $clog2(SEED_DEPTH);

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

  logic                               poly_req_mux;
  logic [$clog2(NUM_POLYS)-1:0]       poly_id_mux;
  logic                               poly_rd_en_mux;
  logic                               poly_ready_int;
  logic [3:0][COEFF_W-1:0]            poly_rd_idx_mux;
  logic [3:0]                         poly_rd_lane_valid_mux;
  logic [3:0]                         poly_wr_en_mux;
  logic [3:0][COEFF_W-1:0]            poly_wr_idx_mux;
  logic [3:0][W-1:0]                  poly_wr_data_mux;

  logic                               seed_we_mux;
  logic [SEED_AW-1:0]                 seed_addr_mux;
  logic [SEED_W-1:0]                  seed_wdata_mux;
  logic [SEED_W-1:0]                  seed_rdata_int;
  logic                               seed_read_fire;
  logic                               seed_read_fire_q;

  logic [COEFF_W-1:0] wipe_base_idx;

  assign wipe_base_idx = COEFF_W'({wipe_row_q, 2'b00});

  // ------------------------------------------------------------
  // Request muxing
  // ------------------------------------------------------------
  always_comb begin
    poly_req_mux           = poly_req_i;
    poly_id_mux            = poly_id_i;
    poly_rd_en_mux         = poly_rd_en_i;
    poly_rd_idx_mux        = poly_rd_idx_i;
    poly_rd_lane_valid_mux = poly_rd_lane_valid_i;
    poly_wr_en_mux         = poly_wr_en_i;
    poly_wr_idx_mux        = poly_wr_idx_i;
    poly_wr_data_mux       = poly_wr_data_i;

    seed_we_mux            = seed_we_i;
    seed_addr_mux          = seed_addr_i;
    seed_wdata_mux         = seed_wdata_i;

    poly_ready_o           = poly_ready_int;
    seed_ready_o           = 1'b1;
    wipe_done_o            = 1'b0;

    case (wipe_state_q)
      WIPE_IDLE: begin
        // Pass-through mode: clients own the memory plane.
      end

      WIPE_POLY: begin
        // Wipe writes one full row (4 coeffs) of one polynomial per cycle.
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

        seed_ready_o           = 1'b0;
        poly_ready_o           = 1'b0;
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

        seed_ready_o           = 1'b0;
        poly_ready_o           = 1'b0;
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

        seed_ready_o           = 1'b0;
        poly_ready_o           = 1'b0;
        wipe_done_o            = 1'b1;
      end

      default: begin
      end
    endcase
  end

  // ------------------------------------------------------------
  // Polynomial memory wrapper
  // ------------------------------------------------------------
  poly_mem_wrapper_4bank #(
    .N         (NCOEFF),
    .W         (W),
    .NUM_POLYS (NUM_POLYS)
  ) u_poly_mem_wrapper (
    .clk             (clk),
    .rst_n           (rst_n),
    .poly_id_i       (poly_id_mux),
    .v_i             (poly_req_mux),
    .rd_en_i         (poly_rd_en_mux),
    .ready_o         (poly_ready_int),
    .rd_idx_i        (poly_rd_idx_mux),
    .rd_lane_valid_i (poly_rd_lane_valid_mux),
    .rd_valid_o      (poly_rd_valid_o),
    .rd_poly_id_o    (poly_rd_poly_id_o),
    .rd_idx_o        (poly_rd_idx_o),
    .rd_lane_valid_o (poly_rd_lane_valid_o),
    .rd_data_o       (poly_rd_data_o),
    .wr_en_i         (poly_wr_en_mux),
    .wr_idx_i        (poly_wr_idx_mux),
    .wr_data_i       (poly_wr_data_mux)
  );

  // ------------------------------------------------------------
  // Seed / protocol store
  // ------------------------------------------------------------
  // The seed store is lightweight and independent of the polynomial-memory
  // banking. For now it exposes one direct request port; multi-client seed
  // arbitration can sit above this module in a dedicated bridge if needed.
  assign seed_read_fire = (wipe_state_q == WIPE_IDLE) && seed_req_i && !seed_we_i;

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

  assign seed_rdata_o = seed_rdata_int;
  assign seed_rvalid_o = seed_read_fire_q;

  // ------------------------------------------------------------
  // Wipe FSM
  // ------------------------------------------------------------
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
        if (poly_ready_int) begin
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wipe_state_q    <= WIPE_IDLE;
      wipe_poly_q     <= '0;
      wipe_row_q      <= '0;
      wipe_seed_q     <= '0;
      seed_read_fire_q <= 1'b0;
    end else begin
      wipe_state_q    <= wipe_state_d;
      wipe_poly_q     <= wipe_poly_d;
      wipe_row_q      <= wipe_row_d;
      wipe_seed_q     <= wipe_seed_d;
      seed_read_fire_q <= seed_read_fire;
    end
  end

endmodule
