// rtl/poly_mem_wrapper_4bank.sv
//
// 4-bank interleaved polynomial memory wrapper.
// Supports reading/writing 4 coefficients per cycle (one per bank).
//
// Mapping (NUM_BANKS=4):
//   bank = coeff_idx[1:0]        (coeff_idx % 4)
//   row  = coeff_idx >> 2        (coeff_idx / 4)
//   bank_addr = poly_id*(N/4) + row
//
// Read latency: synchronous (1 cycle), inherited from poly_ram_bank.
//

module poly_mem_wrapper_4bank #(
  parameter int N         = 256,  // coefficients per polynomial
  parameter int W         = 16,   // coeff width
  parameter int NUM_POLYS = 4     // number of logical polynomials stored
)(
  input  logic clk,
  input  logic rst_n,

  // One polynomial selected per cycle for all lanes
  input  logic [$clog2(NUM_POLYS)-1:0] poly_id_i,

  // request valid
  input  logic                         v_i,

  // explicitly indicate when reads are requested
  input  logic                         rd_en_i,

  // deasserted on conflict
  output logic                         ready_o,

  // Read indices for lanes 0..3
  input  logic [3:0][$clog2(N)-1:0]    rd_idx_i,
  output logic [3:0][W-1:0]            rd_data_o,   // valid next cycle

  // Write controls for lanes 0..3
  input  logic [3:0]                   wr_en_i,
  input  logic [3:0][$clog2(N)-1:0]    wr_idx_i,
  input  logic [3:0][W-1:0]            wr_data_i
);

  initial begin
    if (N % 4 != 0) $fatal(1, "poly_mem_wrapper_4bank: N must be multiple of 4");
  end

  localparam int NUM_BANKS   = 4;
  localparam int SLICE_N     = N / NUM_BANKS;          // rows per poly per bank
  localparam int BANK_DEPTH  = SLICE_N * NUM_POLYS;
  localparam int BANK_AW     = $clog2(BANK_DEPTH);

  // Per-lane decoded bank + row
  logic [3:0][1:0]           rd_bank;
  logic [3:0][BANK_AW-1:0]   rd_baddr;

  logic [3:0][1:0]           wr_bank;
  logic [3:0][BANK_AW-1:0]   wr_baddr;

  // Decode function: maps (poly_id, coeff_idx) -> address within a bank
  function automatic [BANK_AW-1:0] calc_bank_addr(
    input logic [$clog2(NUM_POLYS)-1:0] pid,
    input logic [$clog2(N)-1:0]         coeff_idx
  );
    logic [$clog2(SLICE_N)-1:0] row;
    begin
      row = coeff_idx >> 2; // /4
      calc_bank_addr = pid * SLICE_N + row;
    end
  endfunction

  // Icarus-friendly decode using continuous assigns
  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : G_DECODE
      assign rd_bank[i]  = rd_idx_i[i][1:0];
      assign rd_baddr[i] = calc_bank_addr(poly_id_i, rd_idx_i[i]);

      assign wr_bank[i]  = wr_idx_i[i][1:0];
      assign wr_baddr[i] = calc_bank_addr(poly_id_i, wr_idx_i[i]);
    end
  endgenerate

  // Conflict detection
  logic rd_conflict, wr_conflict;
  logic any_wr;

  always_comb begin
    rd_conflict = 1'b0;
    wr_conflict = 1'b0;
    any_wr      = |wr_en_i;

    // Read conflicts only if reads are enabled
    if (v_i && rd_en_i) begin
      if (rd_bank[0] == rd_bank[1]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[2] == rd_bank[3]) rd_conflict = 1'b1;
    end

    // Write conflicts only among enabled lanes
    if (v_i && any_wr) begin
      if (wr_en_i[0] && wr_en_i[1] && (wr_bank[0] == wr_bank[1])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[2] && (wr_bank[0] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[3] && (wr_bank[0] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[2] && (wr_bank[1] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[3] && (wr_bank[1] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[2] && wr_en_i[3] && (wr_bank[2] == wr_bank[3])) wr_conflict = 1'b1;
    end
  end

  assign ready_o = ~(rd_conflict | wr_conflict);

  // Per-bank port signals
  logic [NUM_BANKS-1:0]              a_we, b_we;
  logic [NUM_BANKS-1:0][BANK_AW-1:0] a_addr, b_addr;
  logic [NUM_BANKS-1:0][W-1:0]       a_wdata, b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]       a_rdata, b_rdata;

  integer k;
  always_comb begin
    // defaults
    for (k = 0; k < NUM_BANKS; k++) begin
      a_we[k]    = 1'b0;
      a_addr[k]  = '0;
      a_wdata[k] = '0;

      b_we[k]    = 1'b0;
      b_addr[k]  = '0;
      b_wdata[k] = '0;
    end

    // Route reads (Port A): only when rd_en_i asserted
    if (v_i && ready_o && rd_en_i) begin
      for (k = 0; k < 4; k++) begin
        a_addr[rd_bank[k]] = rd_baddr[k];
      end
    end

    // Route writes (Port B): one lane per bank if enabled
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

  // Instantiate 4 banks
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

        .a_we   (a_we[b]),
        .a_addr (a_addr[b]),
        .a_wdata(a_wdata[b]),
        .a_rdata(a_rdata[b]),

        .b_we   (b_we[b]),
        .b_addr (b_addr[b]),
        .b_wdata(b_wdata[b]),
        .b_rdata(b_rdata[b])
      );
    end
  endgenerate

  // Return read data next cycle from each lane's bank
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