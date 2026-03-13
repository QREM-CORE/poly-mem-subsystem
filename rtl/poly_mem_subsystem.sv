// ================================================================
// Purpose:
//   This module acts as the memory controller/subsystem for polynomial
//   storage. It connects multiple clients (NTT, PolyMul, Pack/Unpack)
//   to multiple RAM banks.
//
// Main idea:
//   - There are NUM_BANKS memory banks.
//   - Each bank is a dual-port RAM:
//       Port A = shared by NTT / PolyMul write / Pack-Unpack
//       Port B = used by PolyMul reads
//   - Arbitration logic decides who gets access when multiple blocks
//     want the same bank/port at the same time.
//
// Important:
//   RAM reads are synchronous, so read data comes with 1-cycle latency.
// ================================================================
module poly_mem_subsystem #(
  parameter int NUM_BANKS = 4,        // Number of memory banks
  parameter int N         = 256,      // Depth of each bank (number of words)
  parameter int W         = 16,       // Data width of each word
  parameter int ADDR_W    = $clog2(N) // Address width needed for N locations
)(
  input  logic clk,                   // System clock
  input  logic rst_n,                 // Active-low reset

  // ==============================================================
  // NTT interface
  // Uses Port A of the selected bank
  // ==============================================================
  input  logic                         ntt_req,    // NTT requests access
  input  logic [$clog2(NUM_BANKS)-1:0] ntt_bank,   // Which bank NTT wants
  input  logic                         ntt_we,     // Write enable: 1=write, 0=read
  input  logic [ADDR_W-1:0]            ntt_addr,   // Address inside selected bank
  input  logic [W-1:0]                 ntt_wdata,  // Data to write from NTT
  output logic [W-1:0]                 ntt_rdata,  // Data read back to NTT
  output logic                         ntt_stall,  // Stall signal for NTT (currently not heavily used)

  // ==============================================================
  // PolyMul interface
  // - Reads use Port B
  // - Writes use Port A
  // ==============================================================
  input  logic                         pm_req,      // PolyMul requests access

  // PolyMul read channel 0
  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r0,  // Bank for read channel 0
  input  logic [ADDR_W-1:0]            pm_addr_r0,  // Address for read channel 0
  output logic [W-1:0]                 pm_rdata_r0, // Read data from channel 0

  // PolyMul read channel 1
  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_r1,  // Bank for read channel 1
  input  logic [ADDR_W-1:0]            pm_addr_r1,  // Address for read channel 1
  output logic [W-1:0]                 pm_rdata_r1, // Read data from channel 1

  // PolyMul write channel
  input  logic [$clog2(NUM_BANKS)-1:0] pm_bank_w,   // Bank for write
  input  logic                         pm_we,       // Write enable for PolyMul
  input  logic [ADDR_W-1:0]            pm_addr_w,   // Write address
  input  logic [W-1:0]                 pm_wdata,    // Data to write
  output logic                         pm_stall,    // Stall if conflict happens

  // ==============================================================
  // Pack/Unpack interface
  // Uses Port A of selected bank
  // ==============================================================
  input  logic                         pu_req,      // Pack/Unpack request
  input  logic [$clog2(NUM_BANKS)-1:0] pu_bank,     // Bank selected by Pack/Unpack
  input  logic                         pu_we,       // Write enable: 1=write, 0=read
  input  logic [ADDR_W-1:0]            pu_addr,     // Address inside selected bank
  input  logic [W-1:0]                 pu_wdata,    // Data to write
  output logic [W-1:0]                 pu_rdata,    // Data read back
  output logic                         pu_stall     // Stall if conflict happens
);

  // ==============================================================
  // Internal signals to connect arbitration logic to each bank
  //
  // For each bank, we keep:
  //   - write enable for Port A and Port B
  //   - address for Port A and Port B
  //   - write data for Port A and Port B
  //   - read data returned from Port A and Port B
  // ==============================================================
  logic [NUM_BANKS-1:0]             bank_a_we, bank_b_we;
  logic [NUM_BANKS-1:0][ADDR_W-1:0] bank_a_addr, bank_b_addr;
  logic [NUM_BANKS-1:0][W-1:0]      bank_a_wdata, bank_b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]      bank_a_rdata, bank_b_rdata;

  // ==============================================================
  // Instantiate NUM_BANKS copies of poly_ram_bank
  //
  // Each bank is dual-port:
  //   Port A -> shared by NTT / PolyMul write / Pack-Unpack
  //   Port B -> used for PolyMul reads
  // ==============================================================
  genvar i;
  generate
    for (i=0; i<NUM_BANKS; i++) begin : G_BANKS
      poly_ram_bank #(.N(N), .W(W), .ADDR_W(ADDR_W)) u_bank (
        .clk(clk),
        .rst_n(rst_n),

        // Port A connections
        .a_we(bank_a_we[i]),
        .a_addr(bank_a_addr[i]),
        .a_wdata(bank_a_wdata[i]),
        .a_rdata(bank_a_rdata[i]),

        // Port B connections
        .b_we(bank_b_we[i]),
        .b_addr(bank_b_addr[i]),
        .b_wdata(bank_b_wdata[i]),
        .b_rdata(bank_b_rdata[i])
      );
    end
  endgenerate

  
  // ==============================================================
  // Arbitration / routing logic
  //
  // Port A priority:
  //   1. NTT
  //   2. PolyMul write
  //   3. Pack/Unpack
  //
  // Port B usage:
  //   - Only PolyMul reads
  //
  // Note:
  //   RAM reads are synchronous (1-cycle latency), so returned read data
  //   corresponds to a previously issued address.
  // ==============================================================
  always_comb begin
    // ------------------------------------------------------------
    // Default assignments
    // Start by clearing everything so no unintended latches or
    // leftover values occur.
    // ------------------------------------------------------------
    bank_a_we    = '0;
    bank_b_we    = '0;
    bank_a_addr  = '0;
    bank_b_addr  = '0;
    bank_a_wdata = '0;
    bank_b_wdata = '0;

    ntt_rdata   = '0;
    ntt_stall   = 1'b0;

    pm_rdata_r0 = '0;
    pm_rdata_r1 = '0;
    pm_stall    = 1'b0;

    pu_rdata    = '0;
    pu_stall    = 1'b0;

    // ------------------------------------------------------------
    // PORT A: NTT access
    // Highest priority on Port A
    //
    // If NTT requests access:
    //   - send its address to selected bank
    //   - send write enable
    //   - send write data
    //   - return read data from that bank
    // ------------------------------------------------------------
    if (ntt_req) begin
      bank_a_addr[ntt_bank]  = ntt_addr;
      bank_a_we[ntt_bank]    = ntt_we;
      bank_a_wdata[ntt_bank] = ntt_wdata;
      ntt_rdata              = bank_a_rdata[ntt_bank];
    end

    // ------------------------------------------------------------
    // PORT A: PolyMul write
    // Lower priority than NTT
    //
    // If PolyMul wants to write:
    //   - it can use Port A only if NTT is NOT using the same bank
    //   - if same bank conflict happens, PolyMul is stalled
    // ------------------------------------------------------------
    if (pm_req) begin
      if (!(ntt_req && (ntt_bank == pm_bank_w))) begin
        bank_a_addr[pm_bank_w]  = pm_addr_w;
        bank_a_we[pm_bank_w]    = pm_we;
        bank_a_wdata[pm_bank_w] = pm_wdata;
      end else begin
        pm_stall = 1'b1;
      end
    end

    // ------------------------------------------------------------
    // PORT A: Pack/Unpack access
    // Lowest priority on Port A
    //
    // Pack/Unpack can use Port A only if:
    //   - NTT is not using the same bank
    //   - PolyMul write is not using the same bank
    //
    // Otherwise Pack/Unpack is stalled.
    // ------------------------------------------------------------
    if (pu_req) begin
      if (!(ntt_req && (ntt_bank == pu_bank)) &&
          !(pm_req  && (pm_bank_w == pu_bank))) begin
        bank_a_addr[pu_bank]  = pu_addr;
        bank_a_we[pu_bank]    = pu_we;
        bank_a_wdata[pu_bank] = pu_wdata;
        pu_rdata              = bank_a_rdata[pu_bank];
      end else begin
        pu_stall = 1'b1;
      end
    end

    // ------------------------------------------------------------
    // PORT B: PolyMul reads
    //
    // PolyMul has 2 read channels (r0 and r1), but each bank only
    // has one Port B.
    //
    // So:
    //   - read channel 0 always uses its selected bank on Port B
    //   - read channel 1 can also proceed only if it uses a different
    //     bank from read channel 0
    //   - if both want same bank, only one Port B exists there, so
    //     conflict occurs and pm_stall is asserted
    // ------------------------------------------------------------
    if (pm_req) begin
      // Read channel 0
      bank_b_addr[pm_bank_r0] = pm_addr_r0;
      pm_rdata_r0             = bank_b_rdata[pm_bank_r0];

      // Read channel 1
      if (pm_bank_r1 != pm_bank_r0) begin
        bank_b_addr[pm_bank_r1] = pm_addr_r1;
        pm_rdata_r1             = bank_b_rdata[pm_bank_r1];
      end else begin
        pm_stall = 1'b1;
      end
    end
  end

endmodule