/*
 * Module Name: poly_mem_subsystem
 * Author(s): Mavra Muzmmal
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 * Description:
 *   Memory subsystem for polynomial storage.
 *
 *   Features:
 *     - 4 banked dual-port RAMs
 *     - Port A shared by NTT / PolyMul write / Pack-Unpack
 *     - Port B used by PolyMul reads
 *     - Synchronous read steering fix using delayed accepted bank tags
 *     - Security wipe FSM that zeroes all banks
 *
 *   Notes:
 *     - N = rows per bank
 *     - For 32 polynomial slots:
 *         256 coeff/poly / 4 banks = 64 rows/poly/bank
 *         32 polys * 64 rows = 2048 rows per bank
 */

module poly_mem_subsystem #(
  parameter int NUM_BANKS = 4,
  parameter int N         = 2048,
  parameter int W         = 16,
  parameter int ADDR_W    = $clog2(N)
)(
  input  logic clk,
  input  logic rst_n,

  // -----------------------------
  // Security wipe
  // -----------------------------
  input  logic wipe_i,
  output logic wipe_done_o,

  // ==============================================================
  // NTT interface
  // ==============================================================
  input  logic                         ntt_req,
  input  logic [$clog2(NUM_BANKS)-1:0] ntt_bank,
  input  logic                         ntt_we,
  input  logic [ADDR_W-1:0]            ntt_addr,
  input  logic [W-1:0]                 ntt_wdata,
  output logic [W-1:0]                 ntt_rdata,
  output logic                         ntt_stall,

  // ==============================================================
  // PolyMul interface
  // ==============================================================
  input  logic                         pm_req,

  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r0,
  input  logic [ADDR_W-1:0]            pm_addr_r0,
  output logic [W-1:0]                 pm_rdata_r0,

  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r1,
  input  logic [ADDR_W-1:0]            pm_addr_r1,
  output logic [W-1:0]                 pm_rdata_r1,

  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_w,
  input  logic                         pm_we,
  input  logic [ADDR_W-1:0]            pm_addr_w,
  input  logic [W-1:0]                 pm_wdata,
  output logic                         pm_stall,

  // ==============================================================
  // Pack/Unpack interface
  // ==============================================================
  input  logic                         pu_req,
  input  logic [$clog2(NUM_BANKS)-1:0] pu_bank,
  input  logic                         pu_we,
  input  logic [ADDR_W-1:0]            pu_addr,
  input  logic [W-1:0]                 pu_wdata,
  output logic [W-1:0]                 pu_rdata,
  output logic                         pu_stall
);

  // ==============================================================
  // Internal bank interface signals
  // ==============================================================
  logic [NUM_BANKS-1:0]             bank_a_we, bank_b_we;
  logic [NUM_BANKS-1:0][ADDR_W-1:0] bank_a_addr, bank_b_addr;
  logic [NUM_BANKS-1:0][W-1:0]      bank_a_wdata, bank_b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]      bank_a_rdata, bank_b_rdata;

  // ==============================================================
  // RAM bank instances
  // ==============================================================
  genvar i;
  generate
    for (i = 0; i < NUM_BANKS; i++) begin : G_BANKS
      poly_ram_bank #(
        .N(N),
        .W(W),
        .ADDR_W(ADDR_W)
      ) u_bank (
        .clk    (clk),
        .rst_n  (rst_n),

        .a_we   (bank_a_we[i]),
        .a_addr (bank_a_addr[i]),
        .a_wdata(bank_a_wdata[i]),
        .a_rdata(bank_a_rdata[i]),

        .b_we   (bank_b_we[i]),
        .b_addr (bank_b_addr[i]),
        .b_wdata(bank_b_wdata[i]),
        .b_rdata(bank_b_rdata[i])
      );
    end
  endgenerate

  // ==============================================================
  // Wipe FSM
  // ==============================================================
  typedef enum logic [1:0] {
    WIPE_IDLE,
    WIPE_ACTIVE,
    WIPE_DONE
  } wipe_state_e;

  wipe_state_e         wipe_state_q, wipe_state_d;
  logic [ADDR_W-1:0]   wipe_addr_q, wipe_addr_d;

  // ==============================================================
  // Accepted request signals for sync-read steering
  // ==============================================================
  logic ntt_accept;
  logic pm_r0_accept;
  logic pm_r1_accept;
  logic pu_accept;

  // Delayed bank tags
  logic [$clog2(NUM_BANKS)-1:0] ntt_bank_q;
  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r0_q;
  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r1_q;
  logic [$clog2(NUM_BANKS)-1:0] pu_bank_q;

  // Delayed read-valid tags
  logic ntt_rd_valid_q;
  logic pm_r0_valid_q;
  logic pm_r1_valid_q;
  logic pu_rd_valid_q;

  // ==============================================================
  // Arbitration / request routing
  // Wipe is master override
  // ==============================================================
  integer k;
  always_comb begin
    // Defaults
    bank_a_we    = '0;
    bank_b_we    = '0;
    bank_a_addr  = '0;
    bank_b_addr  = '0;
    bank_a_wdata = '0;
    bank_b_wdata = '0;

    ntt_stall    = 1'b0;
    pm_stall     = 1'b0;
    pu_stall     = 1'b0;
    wipe_done_o  = 1'b0;

    // Default accepts
    ntt_accept   = 1'b0;
    pm_r0_accept = 1'b0;
    pm_r1_accept = 1'b0;
    pu_accept    = 1'b0;

    // ----------------------------
    // Wipe override
    // ----------------------------
    if (wipe_state_q == WIPE_ACTIVE) begin
      for (k = 0; k < NUM_BANKS; k++) begin
        bank_a_we[k]    = 1'b1;
        bank_a_addr[k]  = wipe_addr_q;
        bank_a_wdata[k] = '0;
      end

      ntt_stall = 1'b1;
      pm_stall  = 1'b1;
      pu_stall  = 1'b1;
    end
    else begin
      // ----------------------------------------------------------
      // PORT A: NTT (highest priority)
      // ----------------------------------------------------------
      if (ntt_req) begin
        bank_a_addr[ntt_bank]  = ntt_addr;
        bank_a_we[ntt_bank]    = ntt_we;
        bank_a_wdata[ntt_bank] = ntt_wdata;

        if (!ntt_we)
          ntt_accept = 1'b1;
      end

      // ----------------------------------------------------------
      // PORT A: PolyMul write
      // ----------------------------------------------------------
      if (pm_req) begin
        if (!(ntt_req && (ntt_bank == pm_bank_w))) begin
          bank_a_addr[pm_bank_w]  = pm_addr_w;
          bank_a_we[pm_bank_w]    = pm_we;
          bank_a_wdata[pm_bank_w] = pm_wdata;
        end
        else begin
          pm_stall = 1'b1;
        end
      end

      // ----------------------------------------------------------
      // PORT A: Pack/Unpack (lowest priority)
      // ----------------------------------------------------------
      if (pu_req) begin
        if (!(ntt_req && (ntt_bank == pu_bank)) &&
            !(pm_req  && (pm_bank_w == pu_bank))) begin
          bank_a_addr[pu_bank]  = pu_addr;
          bank_a_we[pu_bank]    = pu_we;
          bank_a_wdata[pu_bank] = pu_wdata;

          if (!pu_we)
            pu_accept = 1'b1;
        end
        else begin
          pu_stall = 1'b1;
        end
      end

      // ----------------------------------------------------------
      // PORT B: PolyMul reads
      // ----------------------------------------------------------
      if (pm_req) begin
        // r0 always issues
        bank_b_addr[pm_bank_r0] = pm_addr_r0;
        pm_r0_accept = 1'b1;

        // r1 only if different bank
        if (pm_bank_r1 != pm_bank_r0) begin
          bank_b_addr[pm_bank_r1] = pm_addr_r1;
          pm_r1_accept = 1'b1;
        end
        else begin
          pm_stall = 1'b1;
        end
      end
    end

    if (wipe_state_q == WIPE_DONE)
      wipe_done_o = 1'b1;
  end

  // ==============================================================
  // Wipe next-state logic
  // ==============================================================
  always_comb begin
    wipe_state_d = wipe_state_q;
    wipe_addr_d  = wipe_addr_q;

    case (wipe_state_q)
      WIPE_IDLE: begin
        if (wipe_i) begin
          wipe_state_d = WIPE_ACTIVE;
          wipe_addr_d  = '0;
        end
      end

      WIPE_ACTIVE: begin
        if (wipe_addr_q == N-1) begin
          wipe_state_d = WIPE_DONE;
          wipe_addr_d  = wipe_addr_q;
        end
        else begin
          wipe_state_d = WIPE_ACTIVE;
          wipe_addr_d  = wipe_addr_q + 1'b1;
        end
      end

      WIPE_DONE: begin
        wipe_state_d = WIPE_IDLE;
        wipe_addr_d  = '0;
      end

      default: begin
        wipe_state_d = WIPE_IDLE;
        wipe_addr_d  = '0;
      end
    endcase
  end

  // ==============================================================
  // Sequential state / delayed read steering
  // ==============================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wipe_state_q <= WIPE_IDLE;
      wipe_addr_q  <= '0;

      ntt_bank_q   <= '0;
      pm_bank_r0_q <= '0;
      pm_bank_r1_q <= '0;
      pu_bank_q    <= '0;

      ntt_rd_valid_q <= 1'b0;
      pm_r0_valid_q  <= 1'b0;
      pm_r1_valid_q  <= 1'b0;
      pu_rd_valid_q  <= 1'b0;
    end
    else begin
      wipe_state_q <= wipe_state_d;
      wipe_addr_q  <= wipe_addr_d;

      // Latch only accepted read requests
      if (ntt_accept)
        ntt_bank_q <= ntt_bank;

      if (pm_r0_accept)
        pm_bank_r0_q <= pm_bank_r0;

      if (pm_r1_accept)
        pm_bank_r1_q <= pm_bank_r1;

      if (pu_accept)
        pu_bank_q <= pu_bank;

      // Valid tags update every cycle
      ntt_rd_valid_q <= ntt_accept;
      pm_r0_valid_q  <= pm_r0_accept;
      pm_r1_valid_q  <= pm_r1_accept;
      pu_rd_valid_q  <= pu_accept;
    end
  end

  // ==============================================================
  // Returned data steering
  // Use delayed bank tags because RAM reads are synchronous
  // ==============================================================
  always_comb begin
    ntt_rdata   = '0;
    pm_rdata_r0 = '0;
    pm_rdata_r1 = '0;
    pu_rdata    = '0;

    if (ntt_rd_valid_q)
      ntt_rdata = bank_a_rdata[ntt_bank_q];

    if (pm_r0_valid_q)
      pm_rdata_r0 = bank_b_rdata[pm_bank_r0_q];

    if (pm_r1_valid_q)
      pm_rdata_r1 = bank_b_rdata[pm_bank_r1_q];

    if (pu_rd_valid_q)
      pu_rdata = bank_a_rdata[pu_bank_q];
  end

endmodule