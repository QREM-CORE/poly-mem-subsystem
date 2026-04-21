package qrem_seed_map_pkg;

  // ---------------------------------------------------------------------------
  // Seed / protocol store sizing
  // ---------------------------------------------------------------------------
  // v0.75 treats this as a lightweight protocol store for short fixed-size
  // ML-KEM objects. It remains address-based inside Memory, while bridges above
  // Memory may present semantic access as {seed_id, seed_idx}.
  //
  // A 32 x 64-bit layout is enough to keep the common 256-bit ML-KEM variables
  // resident at the same time without forcing immediate overwrite/reload churn.
  //
  // This width is intentionally friendly to both FPGA and ASIC implementation:
  // - wide enough to move 256-bit values in 4 words
  // - still small enough to infer simple BRAM / LUTRAM / register-file style RAM
  localparam int QREM_SEED_DEPTH = 32;
  localparam int QREM_SEED_W     = 64;
  localparam int QREM_SEED_AW    = $clog2(QREM_SEED_DEPTH);

  localparam int QREM_WORDS_256B = 4;   // 256-bit value in 64-bit words
  localparam int QREM_NUM_SEED_IDS = 8;
  localparam int QREM_SEED_BEATS   = QREM_WORDS_256B;

  typedef enum logic [2:0] {
    SEED_ID_D     = 3'd0,
    SEED_ID_Z     = 3'd1,
    SEED_ID_M     = 3'd2,
    SEED_ID_RHO   = 3'd3,
    SEED_ID_SIGMA = 3'd4,
    SEED_ID_HEK   = 3'd5,
    SEED_ID_SS    = 3'd6,
    SEED_ID_TMP   = 3'd7
  } seed_id_e;

  // ---------------------------------------------------------------------------
  // 256-bit protocol-object base addresses
  // ---------------------------------------------------------------------------
  // These are base WORD addresses, not single-entry IDs.
  // The controller / bridges should treat each item as a 4-word region:
  //   [BASE + 0] .. [BASE + 3]
  //
  // The names intentionally mix "seed" and "protocol" concepts because the
  // store is used for more than just fresh randomness in v0.75:
  //   d, z, m, rho, sigma, H(ek), ss, and temporary protocol values.
  //
  // Why bases instead of IDs:
  // - several values span multiple 64-bit words
  // - the memory fabric should stay a simple addressable RAM
  // - bridges / controller logic should form BASE + word_offset explicitly
  //
  // Example:
  //   H(ek) is a 256-bit digest in ML-KEM, so it occupies 4 x 64-bit words:
  //   [SEED_BASE_HEK + 0] .. [SEED_BASE_HEK + 3]
  localparam int SEED_BASE_D      = 0;   // host-provided d
  localparam int SEED_BASE_Z      = 4;   // host-provided z
  localparam int SEED_BASE_M      = 8;   // host-provided m / raw message
  localparam int SEED_BASE_RHO    = 12;  // public seed for A
  localparam int SEED_BASE_SIGMA  = 16;  // internal seed for PRF / CBD
  localparam int SEED_BASE_HEK    = 20;  // H(ek), 256-bit hash value
  localparam int SEED_BASE_SS     = 24;  // shared secret / protocol result
  localparam int SEED_BASE_TMP    = 28;  // temporary / reserved protocol slot

  function automatic logic [QREM_SEED_AW-1:0] seed_base_addr(
    input seed_id_e id
  );
    begin
      unique case (id)
        SEED_ID_D    : seed_base_addr = QREM_SEED_AW'(SEED_BASE_D);
        SEED_ID_Z    : seed_base_addr = QREM_SEED_AW'(SEED_BASE_Z);
        SEED_ID_M    : seed_base_addr = QREM_SEED_AW'(SEED_BASE_M);
        SEED_ID_RHO  : seed_base_addr = QREM_SEED_AW'(SEED_BASE_RHO);
        SEED_ID_SIGMA: seed_base_addr = QREM_SEED_AW'(SEED_BASE_SIGMA);
        SEED_ID_HEK  : seed_base_addr = QREM_SEED_AW'(SEED_BASE_HEK);
        SEED_ID_SS   : seed_base_addr = QREM_SEED_AW'(SEED_BASE_SS);
        SEED_ID_TMP  : seed_base_addr = QREM_SEED_AW'(SEED_BASE_TMP);
        default      : seed_base_addr = '0;
      endcase
    end
  endfunction

  function automatic logic [QREM_SEED_AW-1:0] seed_word_addr(
    input seed_id_e id,
    input logic [$clog2(QREM_SEED_BEATS)-1:0] beat
  );
    begin
      seed_word_addr = seed_base_addr(id) + QREM_SEED_AW'(beat);
    end
  endfunction

endpackage
