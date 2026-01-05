
module poly_mem_subsystem #(
  parameter int NUM_BANKS = 4,
  parameter int N         = 256,
  parameter int W         = 16,
  parameter int ADDR_W    = $clog2(N)
)(
  input  logic clk,
  input  logic rst_n,

  // ---------------- NTT (uses Port A) ----------------
  input  logic                         ntt_req,
  input  logic [$clog2(NUM_BANKS)-1:0]  ntt_bank,
  input  logic                         ntt_we,
  input  logic [ADDR_W-1:0]            ntt_addr,
  input  logic [W-1:0]                 ntt_wdata,
  output logic [W-1:0]                 ntt_rdata,
  output logic                         ntt_stall,

  // ---------------- PolyMul (reads on Port B, write on Port A) ----
  input  logic                         pm_req,

  input  logic [$clog2(NUM_BANKS)-1:0]  pm_bank_r0,
  input  logic [ADDR_W-1:0]            pm_addr_r0,
  output logic [W-1:0]                 pm_rdata_r0,

  input  logic [$clog2(NUM_BANKS)-1:0]  pm_bank_r1,
  input  logic [ADDR_W-1:0]            pm_addr_r1,
  output logic [W-1:0]                 pm_rdata_r1,

  input  logic [$clog2(NUM_BANKS)-1:0]  pm_bank_w,
  input  logic                         pm_we,
  input  logic [ADDR_W-1:0]            pm_addr_w,
  input  logic [W-1:0]                 pm_wdata,
  output logic                         pm_stall,

  // ---------------- Pack/Unpack (uses Port A) ---------------------
  input  logic                         pu_req,
  input  logic [$clog2(NUM_BANKS)-1:0]  pu_bank,
  input  logic                         pu_we,
  input  logic [ADDR_W-1:0]            pu_addr,
  input  logic [W-1:0]                 pu_wdata,
  output logic [W-1:0]                 pu_rdata,
  output logic                         pu_stall
);

  // Bank port signals
  logic [NUM_BANKS-1:0]               bank_a_we, bank_b_we;
  logic [NUM_BANKS-1:0][ADDR_W-1:0]   bank_a_addr, bank_b_addr;
  logic [NUM_BANKS-1:0][W-1:0]        bank_a_wdata, bank_b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]        bank_a_rdata, bank_b_rdata;

  // Instantiate banks
  genvar i;
  generate
    for (i=0; i<NUM_BANKS; i++) begin : G_BANKS
      poly_ram_bank #(.N(N), .W(W), .ADDR_W(ADDR_W)) u_bank (
        .clk(clk), .rst_n(rst_n),

        .a_we(bank_a_we[i]),
        .a_addr(bank_a_addr[i]),
        .a_wdata(bank_a_wdata[i]),
        .a_rdata(bank_a_rdata[i]),

        .b_we(bank_b_we[i]),
        .b_addr(bank_b_addr[i]),
        .b_wdata(bank_b_wdata[i]),
        .b_rdata(bank_b_rdata[i])
      );
    end
  endgenerate

  // ---------------- Simple fixed-priority port assignment ----------------
  // Port A priority: NTT > PolyMul write > Pack/Unpack
  // Port B: PolyMul reads only
  //
  // NOTE: Reads are synchronous (1-cycle latency) since RAM read is registered.

  always_comb begin
    // Defaults
    bank_a_we    = '0;
    bank_b_we    = '0;
    bank_a_addr  = '0;
    bank_b_addr  = '0;
    bank_a_wdata = '0;
    bank_b_wdata = '0;

    ntt_rdata   = '0; ntt_stall = 1'b0;
    pm_rdata_r0 = '0; pm_rdata_r1 = '0; pm_stall = 1'b0;
    pu_rdata    = '0; pu_stall  = 1'b0;

    // ---- Port A: NTT ----
    if (ntt_req) begin
      bank_a_addr[ntt_bank]  = ntt_addr;
      bank_a_we[ntt_bank]    = ntt_we;
      bank_a_wdata[ntt_bank] = ntt_wdata;
      ntt_rdata              = bank_a_rdata[ntt_bank];
    end

    // ---- Port A: PolyMul write (if not conflicting with NTT on same bank) ----
    if (pm_req) begin
      if (!(ntt_req && (ntt_bank == pm_bank_w))) begin
        bank_a_addr[pm_bank_w]  = pm_addr_w;
        bank_a_we[pm_bank_w]    = pm_we;
        bank_a_wdata[pm_bank_w] = pm_wdata;
      end else begin
        pm_stall = 1'b1;
      end
    end

    // ---- Port A: Pack/Unpack (if not conflicting) ----
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

    // ---- Port B: PolyMul reads ----
    if (pm_req) begin
      // Read channel 0
      bank_b_addr[pm_bank_r0] = pm_addr_r0;
      pm_rdata_r0             = bank_b_rdata[pm_bank_r0];

      // Read channel 1:
      // if same bank as r0, we can’t do both reads on one port -> stall.
      if (pm_bank_r1 != pm_bank_r0) begin
        bank_b_addr[pm_bank_r1] = pm_addr_r1;
        pm_rdata_r1             = bank_b_rdata[pm_bank_r1];
      end else begin
        pm_stall = 1'b1;
      end
    end
  end

endmodule