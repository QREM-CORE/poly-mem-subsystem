/*
 * Module Name: seed_ram
 * Author(s): Mavra Muzmmal, Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Lightweight true-dual-port seed / protocol store used by the QREM core.
 *
 *   v0.85 treats the seed store differently from the polynomial banks:
 *     - no shared arbiter
 *     - small fixed-size protocol values
 *     - concurrent HSU-side and Transcoder-side access
 *
 *   This module therefore exposes two independent ports:
 *     - Port A: intended for the HSU seed bridge
 *     - Port B: intended for the Transcoder / host-facing seed bridge
 *
 * Notes:
 *   - Reads are synchronous with 1-cycle latency.
 *   - Reset is active-high and synchronous.
 *   - Reset is kept for interface consistency but is intentionally unused
 *     inside this RAM primitive.
 *   - Memory contents and raw read-data registers are not reset here. The
 *     top-level wipe FSM zeroises protocol storage when required.
 */

module seed_ram #(
  parameter int DEPTH  = 32,
  parameter int W      = 64,
  parameter int ADDR_W = $clog2(DEPTH)
)(
  input  logic              clk,
  input  logic              rst,       // Kept for interface consistency; unused

  // --------------------------------------------------------------------------
  // Port A (HSU-side seed access)
  // --------------------------------------------------------------------------
  input  logic              a_we,
  input  logic [ADDR_W-1:0] a_addr,
  input  logic [W-1:0]      a_wdata,
  output logic [W-1:0]      a_rdata,

  // --------------------------------------------------------------------------
  // Port B (Transcoder-side seed access)
  // --------------------------------------------------------------------------
  input  logic              b_we,
  input  logic [ADDR_W-1:0] b_addr,
  input  logic [W-1:0]      b_wdata,
  output logic [W-1:0]      b_rdata
);

  logic [W-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (a_we)
      mem[a_addr] <= a_wdata;

    a_rdata <= mem[a_addr];
  end

  always_ff @(posedge clk) begin
    if (b_we)
      mem[b_addr] <= b_wdata;

    b_rdata <= mem[b_addr];
  end

endmodule
