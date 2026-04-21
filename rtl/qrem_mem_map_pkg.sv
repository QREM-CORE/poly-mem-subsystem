package qrem_mem_map_pkg;

  // ============================================================
  // Global memory capacity plan
  // ============================================================
  localparam int QREM_MAX_K = 4;
  localparam int QREM_NUM_POLYS = 32;

  // Each polynomial occupies 64 rows per bank (256 coeffs / 4 banks).
  localparam int QREM_POLY_ROWS_PER_BANK = 64;

  // ============================================================
  // v0.85 fixed controller-visible polynomial slots
  // ============================================================
  // Memory does not take k as an input and does not compute dynamic placement.
  // The controller chooses which subset of these fixed IDs is active for
  // k=2, k=3, or k=4.

  // Secret vector storage. PAU overwrites these same slots with s_hat in place.
  localparam int POLY_ID_S0 = 0;
  localparam int POLY_ID_S1 = 1;
  localparam int POLY_ID_S2 = 2;
  localparam int POLY_ID_S3 = 3;

  // Active row-error scratch. PAU overwrites this same slot with e_hat_i.
  localparam int POLY_ID_EI = 4;

  // Active A row buffer. These slots may hold A_hat[i][j] for the active row.
  localparam int POLY_ID_A0 = 5;
  localparam int POLY_ID_A1 = 6;
  localparam int POLY_ID_A2 = 7;
  localparam int POLY_ID_A3 = 8;

  // Final t vector storage. These slots hold final t_hat_i values.
  localparam int POLY_ID_T0 = 9;
  localparam int POLY_ID_T1 = 10;
  localparam int POLY_ID_T2 = 11;
  localparam int POLY_ID_T3 = 12;

  // Generic controller-visible work region.
  localparam int POLY_ID_WORK_BASE  = 13;
  localparam int POLY_ID_WORK_COUNT = 19;

  localparam int POLY_ID_WORK0  = 13;
  localparam int POLY_ID_WORK1  = 14;
  localparam int POLY_ID_WORK2  = 15;
  localparam int POLY_ID_WORK3  = 16;
  localparam int POLY_ID_WORK4  = 17;
  localparam int POLY_ID_WORK5  = 18;
  localparam int POLY_ID_WORK6  = 19;
  localparam int POLY_ID_WORK7  = 20;
  localparam int POLY_ID_WORK8  = 21;
  localparam int POLY_ID_WORK9  = 22;
  localparam int POLY_ID_WORK10 = 23;
  localparam int POLY_ID_WORK11 = 24;
  localparam int POLY_ID_WORK12 = 25;
  localparam int POLY_ID_WORK13 = 26;
  localparam int POLY_ID_WORK14 = 27;
  localparam int POLY_ID_WORK15 = 28;
  localparam int POLY_ID_WORK16 = 29;
  localparam int POLY_ID_WORK17 = 30;
  localparam int POLY_ID_WORK18 = 31;

endpackage
