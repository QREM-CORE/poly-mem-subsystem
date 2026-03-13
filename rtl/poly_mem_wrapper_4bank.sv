// ============================================================================
//
// Purpose:
//   This module is a 4-bank interleaved polynomial memory wrapper.
//
// What it does:
//   - Stores multiple logical polynomials across 4 physical RAM banks
//   - Supports up to 4 accesses per cycle (one lane per bank)
//   - Uses bank interleaving so consecutive coefficients are distributed
//     across different banks
//
// Mapping rule (for NUM_BANKS = 4):
//   bank = coeff_idx[1:0]         -> coeff_idx % 4
//   row  = coeff_idx >> 2         -> coeff_idx / 4
//   bank_addr = poly_id*(N/4) + row
//
// Example:
//   coeff 0 -> bank 0, row 0
//   coeff 1 -> bank 1, row 0
//   coeff 2 -> bank 2, row 0
//   coeff 3 -> bank 3, row 0
//   coeff 4 -> bank 0, row 1
//
// Read latency:
//   Synchronous read (1-cycle latency), inherited from poly_ram_bank
// ============================================================================

module poly_mem_wrapper_4bank #(
  parameter int N         = 256,  // Number of coefficients per polynomial
  parameter int W         = 16,   // Width of each coefficient in bits
  parameter int NUM_POLYS = 4     // Number of logical polynomials stored
)(
  input  logic clk,               // System clock
  input  logic rst_n,             // Active-low reset

  // One polynomial is selected for all 4 lanes in a cycle
  input  logic [$clog2(NUM_POLYS)-1:0] poly_id_i,

  // Global valid for this cycle
  input  logic                         v_i,

  // Read enable:
  // When high, the rd_idx_i values are treated as valid read requests
  input  logic                         rd_en_i,

  // ready_o is high when no bank conflicts exist
  // If conflict happens, ready_o goes low
  output logic                         ready_o,

  // --------------------------------------------------------------------------
  // Read interface
  // 4 lanes, each lane provides a coefficient index to read
  // rd_data_o is returned next cycle due to synchronous memory
  // --------------------------------------------------------------------------
  input  logic [3:0][$clog2(N)-1:0]    rd_idx_i,
  output logic [3:0][W-1:0]            rd_data_o,

  // --------------------------------------------------------------------------
  // Write interface
  // 4 lanes, each lane may optionally write one coefficient
  // --------------------------------------------------------------------------
  input  logic [3:0]                   wr_en_i,
  input  logic [3:0][$clog2(N)-1:0]    wr_idx_i,
  input  logic [3:0][W-1:0]            wr_data_i
);

  // --------------------------------------------------------------------------
  // Safety check:
  // Since this wrapper uses 4-bank interleaving, N must be divisible by 4
  // --------------------------------------------------------------------------
  initial begin
    if (N % 4 != 0) $fatal(1, "poly_mem_wrapper_4bank: N must be multiple of 4");
  end

  // --------------------------------------------------------------------------
  // Local parameters
  // --------------------------------------------------------------------------
  localparam int NUM_BANKS   = 4;                 // Fixed number of banks
  localparam int SLICE_N     = N / NUM_BANKS;     // Number of rows per polynomial per bank    n/4
  localparam int BANK_DEPTH  = SLICE_N * NUM_POLYS; // Total entries per bank
  localparam int BANK_AW     = $clog2(BANK_DEPTH);  // Address width inside each bank

  // --------------------------------------------------------------------------
  // Per-lane decoded bank number and bank-local address
  //
  // rd_bank[i]  = which bank read lane i should access
  // rd_baddr[i] = row address inside that bank for read lane i
  //
  // wr_bank[i]  = which bank write lane i should access
  // wr_baddr[i] = row address inside that bank for write lane i
  // --------------------------------------------------------------------------
  logic [3:0][1:0]           rd_bank;
  logic [3:0][BANK_AW-1:0]   rd_baddr;

  logic [3:0][1:0]           wr_bank;
  logic [3:0][BANK_AW-1:0]   wr_baddr;

  // --------------------------------------------------------------------------
  // Function: calc_bank_addr
  //
  // Converts (poly_id, coeff_idx) into a bank-local address
  //
  // Formula:
  //   row = coeff_idx / 4
  //   bank_addr = poly_id * SLICE_N + row
  //
  // Why:
  //   - coeff_idx chooses which coefficient in the polynomial
  //   - lower 2 bits choose the bank
  //   - upper bits choose the row
  //   - poly_id offsets to the correct polynomial region in that bank
  // --------------------------------------------------------------------------
  function automatic [BANK_AW-1:0] calc_bank_addr(
    input logic [$clog2(NUM_POLYS)-1:0] pid,
    input logic [$clog2(N)-1:0]         coeff_idx
  );
    logic [$clog2(SLICE_N)-1:0] row;
    begin
      row = coeff_idx >> 2; // divide by 4
      calc_bank_addr = pid * SLICE_N + row;
    end
  endfunction

  // --------------------------------------------------------------------------
  // Decode logic for each lane
  //
  // bank = coeff_idx[1:0]
  // address = calc_bank_addr(poly_id_i, coeff_idx)
  //
  // This is done for all 4 read lanes and all 4 write lanes
  // --------------------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : G_DECODE
      assign rd_bank[i]  = rd_idx_i[i][1:0];
      assign rd_baddr[i] = calc_bank_addr(poly_id_i, rd_idx_i[i]);

      assign wr_bank[i]  = wr_idx_i[i][1:0];
      assign wr_baddr[i] = calc_bank_addr(poly_id_i, wr_idx_i[i]);
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Conflict detection
  //
  // A conflict happens if:
  //   - two reads want the same bank in the same cycle
  //   - two enabled writes want the same bank in the same cycle
  //
  // Since each bank has only one read port used here and one write port used
  // here, only one lane per bank is allowed for reads and writes respectively.
  // --------------------------------------------------------------------------
  logic rd_conflict, wr_conflict;
  logic any_wr;

  always_comb begin
    rd_conflict = 1'b0;
    wr_conflict = 1'b0;
    any_wr      = |wr_en_i;   // true if any write lane is enabled

    // ------------------------------------------------------------------------
    // Read conflicts:
    // Only check when input is valid and reads are enabled
    // If any two lanes decode to the same bank, conflict = 1
    // ------------------------------------------------------------------------
    if (v_i && rd_en_i) begin
      if (rd_bank[0] == rd_bank[1]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[2] == rd_bank[3]) rd_conflict = 1'b1;
    end

    // ------------------------------------------------------------------------
    // Write conflicts:
    // Only compare lanes that actually have wr_en_i asserted
    // If two enabled write lanes target the same bank, conflict = 1
    // ------------------------------------------------------------------------
    if (v_i && any_wr) begin
      if (wr_en_i[0] && wr_en_i[1] && (wr_bank[0] == wr_bank[1])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[2] && (wr_bank[0] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[3] && (wr_bank[0] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[2] && (wr_bank[1] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[3] && (wr_bank[1] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[2] && wr_en_i[3] && (wr_bank[2] == wr_bank[3])) wr_conflict = 1'b1;
    end
  end

  // ready_o is high only when there is no read or write conflict
  assign ready_o = ~(rd_conflict | wr_conflict);

  // --------------------------------------------------------------------------
  // Per-bank physical port signals
  //
  // Port A is used for reads in this wrapper
  // Port B is used for writes in this wrapper
  // --------------------------------------------------------------------------
  logic [NUM_BANKS-1:0]              a_we, b_we;
  logic [NUM_BANKS-1:0][BANK_AW-1:0] a_addr, b_addr;
  logic [NUM_BANKS-1:0][W-1:0]       a_wdata, b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]       a_rdata, b_rdata;

  // --------------------------------------------------------------------------
  // Routing logic:
  //   - Route reads to Port A
  //   - Route writes to Port B
  //
  // Defaults are assigned first.
  // Then requests are connected only if v_i=1 and ready_o=1
  // --------------------------------------------------------------------------
  integer k;
  always_comb begin
    // Default values for all banks
    for (k = 0; k < NUM_BANKS; k++) begin
      a_we[k]    = 1'b0;   // Port A only used for read here, so write disabled
      a_addr[k]  = '0;
      a_wdata[k] = '0;

      b_we[k]    = 1'b0;
      b_addr[k]  = '0;
      b_wdata[k] = '0;
    end

    // ------------------------------------------------------------------------
    // Route reads onto Port A
    // Each read lane selects one bank and one bank-local address
    // Because ready_o already ensures no conflicts, one lane per bank is safe
    // ------------------------------------------------------------------------
    if (v_i && ready_o && rd_en_i) begin
      for (k = 0; k < 4; k++) begin
        a_addr[rd_bank[k]] = rd_baddr[k];
      end
    end

    // ------------------------------------------------------------------------
    // Route writes onto Port B
    // Each enabled write lane writes to its bank and address
    // ready_o guarantees no same-bank write conflicts
    // ------------------------------------------------------------------------
    if (v_i && ready_o) begin
      for (k = 0; k < 4; k++) begin
        if (wr_en_i[k]) begin
          b_we[wr_bank[k]]    = 1'b1;
          b_addr[wr_bank[k]]  = wr_baddr[k];
          b_wdata[wr_bank[k]] = wr_data_i[k];
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Instantiate the 4 physical banks
  //
  // Each bank stores BANK_DEPTH words
  // --------------------------------------------------------------------------
  genvar b;
  generate
    for (b = 0; b < NUM_BANKS; b++) begin : G_BANK
      poly_ram_bank #(
        .N(BANK_DEPTH),
        .W(W),
        .ADDR_W(BANK_AW)
      ) u_bank (
        .clk   (clk),
        .rst_n (rst_n),

        // Port A
        .a_we   (a_we[b]),
        .a_addr (a_addr[b]),
        .a_wdata(a_wdata[b]),
        .a_rdata(a_rdata[b]),

        // Port B
        .b_we   (b_we[b]),
        .b_addr (b_addr[b]),
        .b_wdata(b_wdata[b]),
        .b_rdata(b_rdata[b])
      );
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Read data return path
  //
  // Since RAM reads are synchronous, data appears next cycle.
  // For each lane, use the bank selected by rd_bank[i] and return that bank's
  // Port A read data.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_data_o <= '0;
    end else begin
      rd_data_o[0] <= a_rdata[rd_bank[0]];
      rd_data_o[1] <= a_rdata[rd_bank[1]];
      rd_data_o[2] <= a_rdata[rd_bank[2]];
      rd_data_o[3] <= a_rdata[rd_bank[3]];
    end
  end

endmodule