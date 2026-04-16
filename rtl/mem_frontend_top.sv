// ================================================================
// mem_frontend_top
// ------------------------------------------------
// Logical memory front-end for the QREM memory plane.
//
// Clients provide:
//   - poly_id
//   - coeff_idx
//   - req / we / wdata
//
// This module performs:
//   1. logical -> physical address mapping
//   2. arbitration for the shared NTT-side path (PAU > HSU)
//   3. direct connection of Transcoder to PU path
//   4. connection into poly_mem_subsystem
//
// Notes:
//   - PAU and HSU currently share the NTT-side path.
//   - Transcoder uses the PU path directly.
//   - A true PAU->PM-path integration would require a richer PAU
//     interface (2 read indices + 1 writeback path), which is not
//     present in the current top-level client interface.
// ================================================================
module mem_frontend_top #(
  parameter int NUM_BANKS = 4,
  parameter int NUM_POLYS = 32,
  parameter int NCOEFF    = 256,
  parameter int N         = 2048,
  parameter int W         = 16,
  parameter int ADDR_W    = $clog2(N)
)(
  input  logic clk,
  input  logic rst_n,

  // -------------------------
  // Wipe control
  // -------------------------
  input  logic wipe_i,
  output logic wipe_done_o,

  // ==============================================================
  // PAU interface (logical)
  // ==============================================================
  input  logic                         pau_req,
  input  logic [$clog2(NUM_POLYS)-1:0] pau_poly_id,
  input  logic [$clog2(NCOEFF)-1:0]    pau_coeff_idx,
  input  logic                         pau_we,
  input  logic [W-1:0]                 pau_wdata,
  output logic [W-1:0]                 pau_rdata,
  output logic                         pau_stall,

  // ==============================================================
  // HSU interface (logical)
  // ==============================================================
  input  logic                         hsu_req,
  input  logic [$clog2(NUM_POLYS)-1:0] hsu_poly_id,
  input  logic [$clog2(NCOEFF)-1:0]    hsu_coeff_idx,
  input  logic                         hsu_we,
  input  logic [W-1:0]                 hsu_wdata,
  output logic [W-1:0]                 hsu_rdata,
  output logic                         hsu_stall,

  // ==============================================================
  // Transcoder interface (logical)
  // ==============================================================
  input  logic                         tr_req,
  input  logic [$clog2(NUM_POLYS)-1:0] tr_poly_id,
  input  logic [$clog2(NCOEFF)-1:0]    tr_coeff_idx,
  input  logic                         tr_we,
  input  logic [W-1:0]                 tr_wdata,
  output logic [W-1:0]                 tr_rdata,
  output logic                         tr_stall
);

  // ==============================================================
  // Physical mapped coordinates per client
  // ==============================================================
  logic [$clog2(NUM_BANKS)-1:0] pau_bank, hsu_bank, tr_bank;
  logic [ADDR_W-1:0]            pau_addr, hsu_addr, tr_addr;

  // ==============================================================
  // Shared NTT-side arbiter wires (PAU vs HSU)
  // ==============================================================
  logic                         ntt_req_mux;
  logic [$clog2(NUM_BANKS)-1:0] ntt_bank_mux;
  logic                         ntt_we_mux;
  logic [ADDR_W-1:0]            ntt_addr_mux;
  logic [W-1:0]                 ntt_wdata_mux;

  logic                         mem_pau_stall;
  logic                         mem_hsu_stall;

  logic                         pau_stall_int;
  logic                         hsu_stall_int;

  // ==============================================================
  // Memory subsystem feedback wires
  // ==============================================================
  logic [W-1:0] ntt_rdata_wire;
  logic         ntt_stall_wire;

  logic [W-1:0] pu_rdata_wire;
  logic         pu_stall_wire;

  // ==============================================================
  // Address mappers
  // ==============================================================
  mem_addr_map #(
    .NUM_BANKS(NUM_BANKS),
    .NUM_POLYS(NUM_POLYS),
    .NCOEFF(NCOEFF),
    .ADDR_W(ADDR_W)
  ) u_map_pau (
    .poly_id_i   (pau_poly_id),
    .coeff_idx_i (pau_coeff_idx),
    .bank_o      (pau_bank),
    .addr_o      (pau_addr)
  );

  mem_addr_map #(
    .NUM_BANKS(NUM_BANKS),
    .NUM_POLYS(NUM_POLYS),
    .NCOEFF(NCOEFF),
    .ADDR_W(ADDR_W)
  ) u_map_hsu (
    .poly_id_i   (hsu_poly_id),
    .coeff_idx_i (hsu_coeff_idx),
    .bank_o      (hsu_bank),
    .addr_o      (hsu_addr)
  );

  mem_addr_map #(
    .NUM_BANKS(NUM_BANKS),
    .NUM_POLYS(NUM_POLYS),
    .NCOEFF(NCOEFF),
    .ADDR_W(ADDR_W)
  ) u_map_tr (
    .poly_id_i   (tr_poly_id),
    .coeff_idx_i (tr_coeff_idx),
    .bank_o      (tr_bank),
    .addr_o      (tr_addr)
  );

  // ==============================================================
  // Arbiter
  // --------------------------------------------------------------
  // Use arbiter only for the shared NTT-side path.
  // PAU has higher priority than HSU.
  // Transcoder is handled separately through PU path.
  // ==============================================================
  mem_arbiter #(
    .NUM_BANKS(NUM_BANKS),
    .ADDR_W(ADDR_W),
    .W(W)
  ) u_arbiter (
    .pau_req    (pau_req),
    .pau_bank   (pau_bank),
    .pau_we     (pau_we),
    .pau_addr   (pau_addr),
    .pau_wdata  (pau_wdata),
    .pau_stall  (pau_stall_int),

    .hsu_req    (hsu_req),
    .hsu_bank   (hsu_bank),
    .hsu_we     (hsu_we),
    .hsu_addr   (hsu_addr),
    .hsu_wdata  (hsu_wdata),
    .hsu_stall  (hsu_stall_int),

    // Transcoder not part of this shared NTT-side arbitration
    .tr_req     (1'b0),
    .tr_bank    ('0),
    .tr_we      (1'b0),
    .tr_addr    ('0),
    .tr_wdata   ('0),
    .tr_stall   (),

    .mem_pau_stall_i(mem_pau_stall),
    .mem_hsu_stall_i(mem_hsu_stall),
    .mem_tr_stall_i (1'b0),

    .mem_req    (ntt_req_mux),
    .mem_bank   (ntt_bank_mux),
    .mem_we     (ntt_we_mux),
    .mem_addr   (ntt_addr_mux),
    .mem_wdata  (ntt_wdata_mux)
  );

  // ==============================================================
  // Memory subsystem
  // ==============================================================
  poly_mem_subsystem #(
    .NUM_BANKS(NUM_BANKS),
    .N(N),
    .W(W),
    .ADDR_W(ADDR_W)
  ) u_mem (
    .clk        (clk),
    .rst_n      (rst_n),

    .wipe_i     (wipe_i),
    .wipe_done_o(wipe_done_o),

    // ------------------------------------------------------------
    // Shared NTT-side path: PAU / HSU via arbiter
    // ------------------------------------------------------------
    .ntt_req    (ntt_req_mux),
    .ntt_bank   (ntt_bank_mux),
    .ntt_we     (ntt_we_mux),
    .ntt_addr   (ntt_addr_mux),
    .ntt_wdata  (ntt_wdata_mux),
    .ntt_rdata  (ntt_rdata_wire),
    .ntt_stall  (ntt_stall_wire),

    // ------------------------------------------------------------
    // PM path unused for now
    // ------------------------------------------------------------
    .pm_req      (1'b0),
    .pm_bank_r0  ('0),
    .pm_addr_r0  ('0),
    .pm_rdata_r0 (),
    .pm_bank_r1  ('0),
    .pm_addr_r1  ('0),
    .pm_rdata_r1 (),
    .pm_bank_w   ('0),
    .pm_we       (1'b0),
    .pm_addr_w   ('0),
    .pm_wdata    ('0),
    .pm_stall    (),

    // ------------------------------------------------------------
    // PU path: Transcoder direct
    // ------------------------------------------------------------
    .pu_req     (tr_req),
    .pu_bank    (tr_bank),
    .pu_we      (tr_we),
    .pu_addr    (tr_addr),
    .pu_wdata   (tr_wdata),
    .pu_rdata   (pu_rdata_wire),
    .pu_stall   (pu_stall_wire)
  );

  // ==============================================================
  // Stall propagation back to arbiter-selected NTT-side clients
  // ==============================================================
  assign mem_pau_stall = ntt_stall_wire;
  assign mem_hsu_stall = ntt_stall_wire;

  // ==============================================================
  // Client outputs
  // --------------------------------------------------------------
  // NTT-side clients (PAU/HSU) see the shared NTT read path.
  // Transcoder sees the PU read path.
  // ==============================================================
  assign pau_rdata = ntt_rdata_wire;
  assign hsu_rdata = ntt_rdata_wire;
  assign tr_rdata  = pu_rdata_wire;

  assign pau_stall = pau_stall_int;
  assign hsu_stall = hsu_stall_int;
  assign tr_stall  = pu_stall_wire;

endmodule
