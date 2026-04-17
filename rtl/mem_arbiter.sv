/*
 * Module Name: mem_arbiter
 * Author(s): Mavra Muzmmal, Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Reference:
 *   "Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"
 *   H. Jung, Q. D. Truong, H. Lee — IEEE OJCAS 2025
 *
 * Description:
 *   Centralized priority arbiter for the shared polynomial-memory request
 *   plane inside the Memory Subsystem.
 *
 *   Implements the Arbitrator block from the reference architecture with
 *   strict PAU > HSU > Transcoder priority:
 *     - PAU (Polynomial Arithmetic Unit): highest, NTT/CWM/ADD operations
 *     - HSU (Hash Sampling Unit): mid, Poly Stream Writer coefficient loads
 *     - Transcoder: lowest, ByteEncode/Decode and Compress/Decompress
 *
 *   Only one client wins the shared vector transaction slot each cycle.
 *   The winning client sees downstream stall if the polynomial memory
 *   wrapper cannot accept its request. Lower-priority requesting clients
 *   are stalled immediately.
 *
 * Notes:
 *   - This arbiter chooses an owner only. poly_mem_subsystem performs the
 *     actual request muxing and response routing.
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
