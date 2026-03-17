// ================================================================
// 4-Bank Polynomial Memory Wrapper (CMI-based mapping)
// ------------------------------------------------
// - Splits polynomial memory into 4 banks
// - Uses CMI-style mapping for bank selection
// - Supports 4 parallel reads + 4 parallel writes
// - Detects bank conflicts and stalls using ready_o
// ================================================================

module poly_mem_wrapper_4bank #(
  parameter int N         = 256,  // Number of coefficients per polynomial
  parameter int W         = 16,   // Bit-width of each coefficient
  parameter int NUM_POLYS = 4     // Number of polynomials stored
)(
  input  logic clk,
  input  logic rst_n,

  // Control signals
  input  logic [$clog2(NUM_POLYS)-1:0] poly_id_i, // Select which polynomial
  input  logic                         v_i,       // Valid input
  input  logic                         rd_en_i,   // Read enable
  output logic                         ready_o,   // Ready (no bank conflict)

  // Read interface (4 parallel reads)
  input  logic [3:0][$clog2(N)-1:0]    rd_idx_i,  // Coefficient indices
  output logic [3:0][W-1:0]            rd_data_o, // Read data

  // Write interface (4 parallel writes)
  input  logic [3:0]                   wr_en_i,   // Write enables
  input  logic [3:0][$clog2(N)-1:0]    wr_idx_i,  // Write indices
  input  logic [3:0][W-1:0]            wr_data_i  // Write data
);

  // ================================================================
  // Parameter checks
  // ================================================================
  initial begin
    if (N != 256)
      $display("Warning: current CMI helper assumes 8-bit indices for N=256.");
    if (N % 4 != 0)
      $fatal(1, "poly_mem_wrapper_4bank: N must be divisible by 4");
  end

  // ================================================================
  // Derived parameters
  // ================================================================
  localparam int NUM_BANKS  = 4;                  // Fixed number of banks
  localparam int SLICE_N    = N / NUM_BANKS;      // Elements per bank per poly
  localparam int BANK_DEPTH = SLICE_N * NUM_POLYS;// Total depth per bank
  localparam int BANK_AW    = $clog2(BANK_DEPTH); // Address width per bank

  // ================================================================
  // Internal signals for bank selection and addressing
  // ================================================================
  logic [3:0][1:0]         rd_bank;   // Bank index for reads
  logic [3:0][BANK_AW-1:0] rd_baddr;  // Bank address for reads
  logic [3:0][1:0]         wr_bank;   // Bank index for writes
  logic [3:0][BANK_AW-1:0] wr_baddr;  // Bank address for writes

  // ================================================================
  // CMI BANK INDEX FUNCTION
  // ------------------------------------------------
  // Computes bank index using:
  // bank = sum of 2-bit chunks of index mod 4
  // Helps distribute accesses evenly across banks
  // ================================================================
  function automatic [1:0] cmi_bank_idx(
    input logic [$clog2(N)-1:0] order
  );
    logic [3:0] sum;
    begin
      sum = order[1:0] + order[3:2] + order[5:4] + order[7:6];
      cmi_bank_idx = sum[1:0]; // mod 4
    end
  endfunction

  // ================================================================
  // BANK ADDRESS FUNCTION
  // ------------------------------------------------
  // Computes row inside a bank:
  // row = index / 4  (shift right by 2)
  // final address = poly offset + row
  // ================================================================
  function automatic [BANK_AW-1:0] cmi_bank_addr(
    input logic [$clog2(NUM_POLYS)-1:0] pid,
    input logic [$clog2(N)-1:0]         order
  );
    logic [$clog2(SLICE_N)-1:0] row;
    begin
      row = order >> 2;
      cmi_bank_addr = pid * SLICE_N + row;
    end
  endfunction

  // ================================================================
  // Decode read/write indices into bank + address
  // ================================================================
  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : G_DECODE
      // Read path
      assign rd_bank[i]  = cmi_bank_idx(rd_idx_i[i]);
      assign rd_baddr[i] = cmi_bank_addr(poly_id_i, rd_idx_i[i]);

      // Write path
      assign wr_bank[i]  = cmi_bank_idx(wr_idx_i[i]);
      assign wr_baddr[i] = cmi_bank_addr(poly_id_i, wr_idx_i[i]);
    end
  endgenerate

  // ================================================================
  // Conflict detection logic
  // - Detect if two accesses target same bank
  // ================================================================
  logic rd_conflict, wr_conflict, any_wr;

  always_comb begin
    rd_conflict = 1'b0;
    wr_conflict = 1'b0;
    any_wr      = |wr_en_i;

    // -------- Read conflicts --------
    if (v_i && rd_en_i) begin
      if (rd_bank[0] == rd_bank[1]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[0] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[2]) rd_conflict = 1'b1;
      if (rd_bank[1] == rd_bank[3]) rd_conflict = 1'b1;
      if (rd_bank[2] == rd_bank[3]) rd_conflict = 1'b1;
    end

    // -------- Write conflicts --------
    if (v_i && any_wr) begin
      if (wr_en_i[0] && wr_en_i[1] && (wr_bank[0] == wr_bank[1])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[2] && (wr_bank[0] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[0] && wr_en_i[3] && (wr_bank[0] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[2] && (wr_bank[1] == wr_bank[2])) wr_conflict = 1'b1;
      if (wr_en_i[1] && wr_en_i[3] && (wr_bank[1] == wr_bank[3])) wr_conflict = 1'b1;
      if (wr_en_i[2] && wr_en_i[3] && (wr_bank[2] == wr_bank[3])) wr_conflict = 1'b1;
    end
  end

  // Ready = no conflicts
  assign ready_o = ~(rd_conflict | wr_conflict);

  // ================================================================
  // Bank interface signals (dual-port RAM per bank)
  // ================================================================
  logic [NUM_BANKS-1:0]              a_we, b_we;
  logic [NUM_BANKS-1:0][BANK_AW-1:0] a_addr, b_addr;
  logic [NUM_BANKS-1:0][W-1:0]       a_wdata, b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]       a_rdata, b_rdata;

  // ================================================================
  // Routing logic: map requests to correct bank ports
  // ================================================================
  integer k;
  always_comb begin
    // Default: disable everything
    for (k = 0; k < NUM_BANKS; k++) begin
      a_we[k]    = 1'b0;
      a_addr[k]  = '0;
      a_wdata[k] = '0;

      b_we[k]    = 1'b0;
      b_addr[k]  = '0;
      b_wdata[k] = '0;
    end

    // -------- READ ROUTING (Port A) --------
    if (v_i && ready_o && rd_en_i) begin
      for (k = 0; k < 4; k++) begin
        a_addr[rd_bank[k]] = rd_baddr[k];
      end
    end

    // -------- WRITE ROUTING (Port B) --------
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

  // ================================================================
  // Instantiate 4 memory banks (dual-port RAMs)
  // ================================================================
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

        // Port A = read
        .a_we    (a_we[b]),
        .a_addr  (a_addr[b]),
        .a_wdata (a_wdata[b]),
        .a_rdata (a_rdata[b]),

        // Port B = write
        .b_we    (b_we[b]),
        .b_addr  (b_addr[b]),
        .b_wdata (b_wdata[b]),
        .b_rdata (b_rdata[b])
      );
    end
  endgenerate

  // ================================================================
  // Output register (synchronous read output)
  // ================================================================
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