package qrem_seed_map_pkg;

  // ---------------------------------------------------------------------------
  // Seed / protocol store sizing
  // ---------------------------------------------------------------------------
  // v0.75 treats the seed store as a lightweight RAM for short protocol values.
  // A 32 x 64-bit layout is enough to keep the common 256-bit ML-KEM variables
  // resident at the same time without forcing immediate overwrite/reload churn.
  localparam int QREM_SEED_DEPTH = 32;
  localparam int QREM_SEED_W     = 64;
  localparam int QREM_SEED_AW    = $clog2(QREM_SEED_DEPTH);

  localparam int QREM_WORDS_256B = 4;   // 256-bit value in 64-bit words

  // ---------------------------------------------------------------------------
  // 256-bit variable base addresses
  // ---------------------------------------------------------------------------
  // These are base WORD addresses, not single-entry IDs.
  // The controller / bridges should treat each item as a 4-word region:
  //   [BASE + 0] .. [BASE + 3]
  //
  // The names intentionally mix "seed" and "protocol" concepts because the
  // store is used for more than just fresh randomness in v0.75.
  localparam int SEED_BASE_D      = 0;   // host-provided d
  localparam int SEED_BASE_Z      = 4;   // host-provided z
  localparam int SEED_BASE_M      = 8;   // host-provided m / raw message
  localparam int SEED_BASE_RHO    = 12;  // public seed for A
  localparam int SEED_BASE_SIGMA  = 16;  // internal seed for PRF / CBD
  localparam int SEED_BASE_HEK    = 20;  // H(ek)
  localparam int SEED_BASE_SS     = 24;  // shared secret / protocol result
  localparam int SEED_BASE_TMP    = 28;  // temporary / reserved protocol slot

endpackage
