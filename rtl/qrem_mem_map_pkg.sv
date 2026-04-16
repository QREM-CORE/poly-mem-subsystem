package qrem_mem_map_pkg;

  // ============================================================
  // Global memory capacity plan
  // ============================================================
  localparam int QREM_NUM_POLYS = 32;

  // Each polynomial occupies 64 rows per bank (256 coeffs / 4 banks)
  localparam int QREM_POLY_ROWS_PER_BANK = 64;

  // ============================================================
  // Base allocations
  // ============================================================
  // A matrix: worst-case ML-KEM-1024 uses k=4 => 4x4 = 16 polys
  localparam int POLY_ID_A_BASE    = 0;   // 0..15

  // Secret vector s: up to 4 polys
  localparam int POLY_ID_S_BASE    = 16;  // 16..19

  // Error vector e: up to 4 polys
  localparam int POLY_ID_E_BASE    = 20;  // 20..23

  // Output / t vector / result region
  localparam int POLY_ID_T_BASE    = 24;  // 24..27

  // Temp / scratch / intermediate storage
  localparam int POLY_ID_TEMP_BASE = 28;  // 28..31

  // ============================================================
  // Explicit slot aliases
  // ============================================================
  localparam int POLY_ID_A_00 = 0;
  localparam int POLY_ID_A_01 = 1;
  localparam int POLY_ID_A_02 = 2;
  localparam int POLY_ID_A_03 = 3;

  localparam int POLY_ID_A_10 = 4;
  localparam int POLY_ID_A_11 = 5;
  localparam int POLY_ID_A_12 = 6;
  localparam int POLY_ID_A_13 = 7;

  localparam int POLY_ID_A_20 = 8;
  localparam int POLY_ID_A_21 = 9;
  localparam int POLY_ID_A_22 = 10;
  localparam int POLY_ID_A_23 = 11;

  localparam int POLY_ID_A_30 = 12;
  localparam int POLY_ID_A_31 = 13;
  localparam int POLY_ID_A_32 = 14;
  localparam int POLY_ID_A_33 = 15;

  localparam int POLY_ID_S_0 = 16;
  localparam int POLY_ID_S_1 = 17;
  localparam int POLY_ID_S_2 = 18;
  localparam int POLY_ID_S_3 = 19;

  localparam int POLY_ID_E_0 = 20;
  localparam int POLY_ID_E_1 = 21;
  localparam int POLY_ID_E_2 = 22;
  localparam int POLY_ID_E_3 = 23;

  localparam int POLY_ID_T_0 = 24;
  localparam int POLY_ID_T_1 = 25;
  localparam int POLY_ID_T_2 = 26;
  localparam int POLY_ID_T_3 = 27;

  localparam int POLY_ID_TEMP_0 = 28;
  localparam int POLY_ID_TEMP_1 = 29;
  localparam int POLY_ID_TEMP_2 = 30;
  localparam int POLY_ID_TEMP_3 = 31;

endpackage