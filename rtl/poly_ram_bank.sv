/*
 * Module Name: poly_ram_bank
 * Author(s): Mavra Muzmmal
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 * Description:
 *   This module implements a single dual-port RAM bank used for storing
 *   polynomial coefficients.
 *
 *   Key Features:
 *     - Depth: N entries
 *     - Width: W bits per entry
 *     - Two independent ports (Port A and Port B)
 *     - Each port can read or write in the same clock cycle
 *     - Reads are synchronous (data returned on next clock)
 *
 *   Reset notes:
 *     - Reset is active-high and synchronous.
 *     - Reset is kept for interface consistency but is intentionally unused
 *       inside this RAM primitive.
 *     - Memory contents and raw read-data registers are not reset here. The
 *       top-level wipe FSM is responsible for zeroising polynomial storage.
 *
 *   Why we need this:
 *     Higher-level modules (like poly_mem_wrapper_4bank or poly_mem_subsystem)
 *     connect several of these banks together to allow parallel access to
 *     polynomial coefficients.
 *
 *   Example:
 *     If N = 256 and W = 16,
 *     this bank stores 256 coefficients, each 16 bits wide.
 */

module poly_ram_bank #(
  parameter int N      = 256,          // Number of memory locations
  parameter int W      = 16,           // Data width (bits per coefficient)
  parameter int ADDR_W = $clog2(N)     // Address width needed for N entries
)(
  input  logic              clk,       // System clock
  input  logic              rst,       // Kept for interface consistency; unused

  // --------------------------------------------------------------------------
  // PORT A (first memory port)
  // --------------------------------------------------------------------------
  input  logic              a_we,      // Write enable for Port A
  input  logic [ADDR_W-1:0] a_addr,    // Address for read/write
  input  logic [W-1:0]      a_wdata,   // Data to write when a_we=1
  output logic [W-1:0]      a_rdata,   // Data read from memory

  // --------------------------------------------------------------------------
  // PORT B (second independent memory port)
  // --------------------------------------------------------------------------
  input  logic              b_we,      // Write enable for Port B
  input  logic [ADDR_W-1:0] b_addr,    // Address for read/write
  input  logic [W-1:0]      b_wdata,   // Data to write when b_we=1
  output logic [W-1:0]      b_rdata    // Data read from memory
);

  // --------------------------------------------------------------------------
  // Actual memory array
  //
  // mem[index] stores one coefficient.
  //
  // Example:
  // mem[0] = first coefficient
  // mem[1] = second coefficient
  // ...
  // mem[255] = last coefficient (if N=256)
  // --------------------------------------------------------------------------
 (* ram_style = "block" *) logic [W-1:0] mem [0:N-1];

  // --------------------------------------------------------------------------
  // PORT A behavior
  //
  // On every clock edge:
  //   1. If write enable is active → write data to memory
  //   2. Always read the memory at address a_addr
  //
  // Important:
  //   The read data appears AFTER the clock edge (synchronous read).
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (a_we)                         // If write enable is active
      mem[a_addr] <= a_wdata;         // Write new data into memory

    a_rdata <= mem[a_addr];           // Read data from the same address
  end

  // --------------------------------------------------------------------------
  // PORT B behavior (independent from Port A)
  //
  // Works exactly the same way but uses different signals.
  // This allows two accesses in the same clock cycle.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (b_we)                         // If Port B write enable is active
      mem[b_addr] <= b_wdata;         // Write data to memory

    b_rdata <= mem[b_addr];           // Read memory value
  end

endmodule
