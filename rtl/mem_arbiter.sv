// ================================================================
// mem_arbiter
// ------------------------------------------------
// Front-end priority arbiter for memory access.
//
// Priority:
//   1. PAU
//   2. HSU
//   3. Transcoder
//
// This version also propagates memory-subsystem stall feedback
// to the currently selected client.
//
// Notes:
//   - Lower-priority active clients are stalled.
//   - If the selected client is blocked by the memory subsystem,
//     its stall output is also asserted.
// ================================================================
module mem_arbiter #(
  parameter int NUM_BANKS = 4,
  parameter int ADDR_W    = 11,
  parameter int W         = 16
)(
  // ==============================================================
  // PAU request
  // ==============================================================
  input  logic                         pau_req,
  input  logic [$clog2(NUM_BANKS)-1:0] pau_bank,
  input  logic                         pau_we,
  input  logic [ADDR_W-1:0]            pau_addr,
  input  logic [W-1:0]                 pau_wdata,
  output logic                         pau_stall,

  // ==============================================================
  // HSU request
  // ==============================================================
  input  logic                         hsu_req,
  input  logic [$clog2(NUM_BANKS)-1:0] hsu_bank,
  input  logic                         hsu_we,
  input  logic [ADDR_W-1:0]            hsu_addr,
  input  logic [W-1:0]                 hsu_wdata,
  output logic                         hsu_stall,

  // ==============================================================
  // Transcoder request
  // ==============================================================
  input  logic                         tr_req,
  input  logic [$clog2(NUM_BANKS)-1:0] tr_bank,
  input  logic                         tr_we,
  input  logic [ADDR_W-1:0]            tr_addr,
  input  logic [W-1:0]                 tr_wdata,
  output logic                         tr_stall,

  // ==============================================================
  // Stall feedback from memory subsystem
  //
  // These are the stalls returned by the memory block for whichever
  // client was selected and connected downstream.
  // ==============================================================
  input  logic                         mem_pau_stall_i,
  input  logic                         mem_hsu_stall_i,
  input  logic                         mem_tr_stall_i,

  // ==============================================================
  // Output to memory subsystem
  // ==============================================================
  output logic                         mem_req,
  output logic [$clog2(NUM_BANKS)-1:0] mem_bank,
  output logic                         mem_we,
  output logic [ADDR_W-1:0]            mem_addr,
  output logic [W-1:0]                 mem_wdata
);

  always_comb begin
    // ------------------------------------------------------------
    // Defaults
    // ------------------------------------------------------------
    mem_req   = 1'b0;
    mem_bank  = '0;
    mem_we    = 1'b0;
    mem_addr  = '0;
    mem_wdata = '0;

    pau_stall = 1'b0;
    hsu_stall = 1'b0;
    tr_stall  = 1'b0;

    // ------------------------------------------------------------
    // Priority arbitration with memory stall propagation
    // ------------------------------------------------------------
    if (pau_req) begin
      // PAU wins
      mem_req   = 1'b1;
      mem_bank  = pau_bank;
      mem_we    = pau_we;
      mem_addr  = pau_addr;
      mem_wdata = pau_wdata;

      // Lower-priority active clients stall due to arbitration
      if (hsu_req) hsu_stall = 1'b1;
      if (tr_req)  tr_stall  = 1'b1;

      // Selected client also sees downstream memory stall
      pau_stall = mem_pau_stall_i;
    end
    else if (hsu_req) begin
      // HSU wins
      mem_req   = 1'b1;
      mem_bank  = hsu_bank;
      mem_we    = hsu_we;
      mem_addr  = hsu_addr;
      mem_wdata = hsu_wdata;

      // Lower-priority active clients stall due to arbitration
      if (tr_req) tr_stall = 1'b1;

      // Selected client also sees downstream memory stall
      hsu_stall = mem_hsu_stall_i;
    end
    else if (tr_req) begin
      // Transcoder wins
      mem_req   = 1'b1;
      mem_bank  = tr_bank;
      mem_we    = tr_we;
      mem_addr  = tr_addr;
      mem_wdata = tr_wdata;

      // Selected client also sees downstream memory stall
      tr_stall = mem_tr_stall_i;
    end
  end

endmodule