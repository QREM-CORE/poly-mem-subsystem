/*
 * Module Name: seed_ram
 * Author(s): Mavra Muzmmal
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 * Description:
 *   Simple synchronous RAM used to store seed values.
 *   The memory supports one read and one write per clock cycle.
 *   If write enable (we) is asserted, data is written to the
 *   specified address. The read is synchronous and returns the
 *   value stored at the given address.
 *
 *   Parameters:
 *     DEPTH   : Number of memory locations
 *     W       : Width of each memory word
 *     ADDR_W  : Width of the address bus (log2 of DEPTH)
 */

module seed_ram #(
  parameter int DEPTH   = 16,                 // Total number of memory entries
  parameter int W       = 64,                 // Width of each stored word (64 bits)
  parameter int ADDR_W  = $clog2(DEPTH)       // Address width automatically computed
)(
  // Clock signal (all operations are synchronized to this)
  input  logic              clk,

  // Active-low reset (currently unused but kept for system consistency)
  input  logic              rst,

  // Write enable signal
  // When 'we' = 1, data will be written into memory
  input  logic              we,

  // Address for both read and write operations
  input  logic [ADDR_W-1:0] addr,

  // Data to be written into memory
  input  logic [W-1:0]      wdata,

  // Data read from memory
  output logic [W-1:0]      rdata
);

  // ===============================================================
  // Memory Declaration
  // Creates an array of DEPTH entries, each W bits wide
  // Example with default parameters:
  //   16 locations × 64 bits each
  // ===============================================================
  logic [W-1:0] mem [0:DEPTH-1];


  // ===============================================================
  // Sequential Memory Logic
  // This block runs on the rising edge of the clock.
  //
  // Write Operation:
  //   If 'we' is asserted, wdata is stored at mem[addr]
  //
  // Read Operation:
  //   rdata always outputs the value stored at mem[addr]
  //   (Synchronous read with 1 clock cycle latency)
  // ===============================================================
  always_ff @(posedge clk) begin

    // Write data into memory when write enable is active
    if (we)
      mem[addr] <= wdata;

    // Read data from memory
    rdata <= mem[addr];

  end

endmodule