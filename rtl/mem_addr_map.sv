// ================================================================
// mem_addr_map
// ------------------------------------------------
// Converts logical polynomial coordinates into physical memory
// coordinates for the banked memory subsystem.
//
// Logical view:
//   - poly_id   : which polynomial slot (0..31)
//   - coeff_idx : coefficient index inside that polynomial (0..255)
//
// Physical view:
//   - bank : which of the 4 banks
//   - addr : row address inside the bank RAM
//
// Mapping:
//   bank = coeff_idx[1:0]
//   row  = coeff_idx[7:2]
//
// Each polynomial occupies 64 rows per bank.
// Final address:
//   addr = poly_id * 64 + row
// ================================================================
module mem_addr_map #(
  parameter int NUM_BANKS          = 4,
  parameter int NUM_POLYS          = 32,
  parameter int NCOEFF             = 256,
  parameter int ROWS_PER_POLY_BANK = NCOEFF / NUM_BANKS, // 64
  parameter int ADDR_W             = 11                  // 32*64 = 2048 rows
)(
  input  logic [$clog2(NUM_POLYS)-1:0] poly_id_i,
  input  logic [$clog2(NCOEFF)-1:0]    coeff_idx_i,

  output logic [$clog2(NUM_BANKS)-1:0] bank_o,
  output logic [ADDR_W-1:0]            addr_o
);

  logic [$clog2(ROWS_PER_POLY_BANK)-1:0] row;

  always_comb begin
    bank_o = coeff_idx_i[$clog2(NUM_BANKS)-1:0];
    row    = coeff_idx_i[$clog2(NCOEFF)-1:$clog2(NUM_BANKS)];
    addr_o = poly_id_i * ROWS_PER_POLY_BANK + row;
  end

endmodule