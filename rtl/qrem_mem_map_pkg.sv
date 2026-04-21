package qrem_mem_map_pkg;

  // ============================================================
  // Global memory capacity plan
  // ============================================================
  localparam int QREM_MAX_K = 4;
  localparam int QREM_NUM_POLYS = 32;

  // Each polynomial occupies 64 rows per bank (256 coeffs / 4 banks)
  localparam int QREM_POLY_ROWS_PER_BANK = 64;

  // ============================================================
  // Base allocations
  // ============================================================
  // A matrix: worst-case ML-KEM-1024 uses k=4 => 4x4 = 16 polys
  localparam int POLY_ID_A_BASE    = 0;   // 0..15
  localparam int POLY_ID_A_COUNT   = QREM_MAX_K * QREM_MAX_K;

  // Secret vector s: up to 4 polys
  localparam int POLY_ID_S_BASE    = 16;  // 16..19
  localparam int POLY_ID_S_COUNT   = QREM_MAX_K;

  // Error vector e: up to 4 polys
  localparam int POLY_ID_E_BASE    = 20;  // 20..23
  localparam int POLY_ID_E_COUNT   = QREM_MAX_K;

  // Output / t vector / result region
  localparam int POLY_ID_T_BASE    = 24;  // 24..27
  localparam int POLY_ID_T_COUNT   = QREM_MAX_K;

  // Temp / scratch / intermediate storage
  localparam int POLY_ID_TEMP_BASE = 28;  // 28..31
  localparam int POLY_ID_TEMP_COUNT = QREM_MAX_K;

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

  // ============================================================
  // Semantic aliases for controller-visible placement intent
  // ============================================================
  // Secret generation and row-error generation are intentionally in-place:
  // HSU writes s[j] / e[i], then PAU overwrites the same slot with s_hat[j]
  // / e_hat[i] after NTT. The numeric IDs remain unchanged.
  localparam int POLY_ID_S_HAT_0 = POLY_ID_S_0;
  localparam int POLY_ID_S_HAT_1 = POLY_ID_S_1;
  localparam int POLY_ID_S_HAT_2 = POLY_ID_S_2;
  localparam int POLY_ID_S_HAT_3 = POLY_ID_S_3;

  localparam int POLY_ID_E_HAT_0 = POLY_ID_E_0;
  localparam int POLY_ID_E_HAT_1 = POLY_ID_E_1;
  localparam int POLY_ID_E_HAT_2 = POLY_ID_E_2;
  localparam int POLY_ID_E_HAT_3 = POLY_ID_E_3;

  localparam int POLY_ID_T_HAT_0 = POLY_ID_T_0;
  localparam int POLY_ID_T_HAT_1 = POLY_ID_T_1;
  localparam int POLY_ID_T_HAT_2 = POLY_ID_T_2;
  localparam int POLY_ID_T_HAT_3 = POLY_ID_T_3;

  // Full A residency remains available in POLY_ID_A_*.
  // TEMP_0 is a dedicated semantic alias for streamed / transient A_hat usage
  // when a controller prefers scratch placement instead of full residency.
  localparam int POLY_ID_A_STREAM_SCRATCH = POLY_ID_TEMP_0;

  function automatic int unsigned poly_id_a(
    input int unsigned row,
    input int unsigned col
  );
    begin
      poly_id_a = POLY_ID_A_BASE + (row * QREM_MAX_K) + col;
    end
  endfunction

  function automatic int unsigned poly_id_s(
    input int unsigned col
  );
    begin
      poly_id_s = POLY_ID_S_BASE + col;
    end
  endfunction

  function automatic int unsigned poly_id_e(
    input int unsigned row
  );
    begin
      poly_id_e = POLY_ID_E_BASE + row;
    end
  endfunction

  function automatic int unsigned poly_id_t(
    input int unsigned row
  );
    begin
      poly_id_t = POLY_ID_T_BASE + row;
    end
  endfunction

  function automatic int unsigned poly_id_temp(
    input int unsigned slot
  );
    begin
      poly_id_temp = POLY_ID_TEMP_BASE + slot;
    end
  endfunction

endpackage
