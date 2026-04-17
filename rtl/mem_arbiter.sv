/*
 * Module Name: mem_arbiter
 * Author(s): OpenAI Codex
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Centralized front-end arbiter for the shared polynomial-memory request
 *   plane.
 *
 * Why this exists:
 *   v0.7 codifies a strict PAU > HSU > Transcoder priority hierarchy for
 *   accesses to the banked polynomial memory. The old frontend partly
 *   arbitrated PAU/HSU and partly let the transcoder bypass that logic,
 *   which split the true ownership rules across multiple modules.
 *
 * New contract:
 *   - Arbitration is strictly centralized here.
 *   - Only one client wins the shared vector transaction slot each cycle.
 *   - The selected client sees downstream stall if the polynomial memory
 *     wrapper cannot accept its request that cycle.
 *   - Lower-priority requesting clients are stalled immediately.
 *
 * Notes:
 *   - This arbiter chooses an owner only. mem_frontend_top performs the
 *     actual request muxing and response routing.
 *   - A more aggressive bank-aware "multiple clients in one cycle" policy
 *     is intentionally not implemented here because the v0.7 snapshot calls
 *     for strict priority and safe backpressure rather than optimistic
 *     concurrency.
 */

module mem_arbiter (
  // ------------------------------------------------------------
  // Client request valids
  // ------------------------------------------------------------
  input  logic pau_req_i,
  input  logic hsu_req_i,
  input  logic tr_req_i,

  // ------------------------------------------------------------
  // Shared downstream ready
  // ------------------------------------------------------------
  input  logic mem_ready_i,

  // ------------------------------------------------------------
  // One-hot grants
  // ------------------------------------------------------------
  output logic grant_pau_o,
  output logic grant_hsu_o,
  output logic grant_tr_o,

  // ------------------------------------------------------------
  // Client-visible stalls
  // ------------------------------------------------------------
  output logic pau_stall_o,
  output logic hsu_stall_o,
  output logic tr_stall_o
);

  always_comb begin
    grant_pau_o = 1'b0;
    grant_hsu_o = 1'b0;
    grant_tr_o  = 1'b0;

    pau_stall_o = 1'b0;
    hsu_stall_o = 1'b0;
    tr_stall_o  = 1'b0;

    // Highest priority: PAU
    if (pau_req_i) begin
      grant_pau_o = 1'b1;
      pau_stall_o = ~mem_ready_i;

      if (hsu_req_i) hsu_stall_o = 1'b1;
      if (tr_req_i)  tr_stall_o  = 1'b1;
    end
    // Next priority: HSU / poly memory writer
    else if (hsu_req_i) begin
      grant_hsu_o = 1'b1;
      hsu_stall_o = ~mem_ready_i;

      if (tr_req_i) tr_stall_o = 1'b1;
    end
    // Lowest priority: Transcoder
    else if (tr_req_i) begin
      grant_tr_o = 1'b1;
      tr_stall_o = ~mem_ready_i;
    end
  end

endmodule
