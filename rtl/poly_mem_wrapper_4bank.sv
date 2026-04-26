/*
 * Module Name: poly_mem_wrapper_4bank
 * Author(s): Mavra Muzmmal, Jessica Buentipo, Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Four-bank true-dual-port polynomial memory wrapper for the QREM core.
 *
 *   v0.85 treats the bank wrapper as two generic vector ports rather than a
 *   fixed "read plane + write plane" split:
 *     - Port 0 is bound to physical RAM Port A across all banks
 *     - Port 1 is bound to physical RAM Port B across all banks
 *     - Either port may service one 4-lane READ vector or one 4-lane WRITE
 *       vector in a cycle
 *
 *   This preserves a clean RAM-mapping-friendly structure while allowing:
 *     - two reads in one cycle when legal
 *     - two writes in one cycle when legal
 *     - one read + one write in one cycle when legal
 *
 * Notes:
 *   - Reset is active-high and synchronous.
 *   - Read response latency is 1 cycle from accepted read request.
 *   - Memory-side bit-pair-sum bank mapping is used for both ports.
 *     This is bank/row decode logic only; PAU-side CMI remains in PAU.
 *   - Same-address read+write is explicitly forbidden.
 *   - Same-address write+write is explicitly forbidden.
 *   - Same-request lane conflicts remain illegal.
 */

import qrem_global_pkg::*;

module poly_mem_wrapper_4bank #(
  parameter int N         = qrem_global_pkg::NCOEFF,
  parameter int W         = 16,
  parameter int NUM_POLYS = qrem_global_pkg::NUM_POLYS
)(
  input  logic clk,
  input  logic rst,

  // --------------------------------------------------------------------------
  // Generic port 0 (physical RAM Port A)
  // --------------------------------------------------------------------------
  input  logic [$clog2(NUM_POLYS)-1:0] p0_poly_id_i,
  input  logic                         p0_v_i,
  input  logic [3:0]                   p0_wr_en_i,
  input  logic [3:0][$clog2(N)-1:0]    p0_idx_i,
  input  logic [3:0]                   p0_lane_valid_i,
  input  logic [3:0][W-1:0]            p0_data_i,
  output logic                         p0_ready_o,

  output logic                         p0_rd_valid_o,
  output logic [$clog2(NUM_POLYS)-1:0] p0_rd_poly_id_o,
  output logic [3:0][$clog2(N)-1:0]    p0_rd_idx_o,
  output logic [3:0]                   p0_rd_lane_valid_o,
  output logic [3:0][W-1:0]            p0_rd_data_o,

  // --------------------------------------------------------------------------
  // Generic port 1 (physical RAM Port B)
  // --------------------------------------------------------------------------
  input  logic [$clog2(NUM_POLYS)-1:0] p1_poly_id_i,
  input  logic                         p1_v_i,
  input  logic [3:0]                   p1_wr_en_i,
  input  logic [3:0][$clog2(N)-1:0]    p1_idx_i,
  input  logic [3:0]                   p1_lane_valid_i,
  input  logic [3:0][W-1:0]            p1_data_i,
  output logic                         p1_ready_o,

  output logic                         p1_rd_valid_o,
  output logic [$clog2(NUM_POLYS)-1:0] p1_rd_poly_id_o,
  output logic [3:0][$clog2(N)-1:0]    p1_rd_idx_o,
  output logic [3:0]                   p1_rd_lane_valid_o,
  output logic [3:0][W-1:0]            p1_rd_data_o,

  // --------------------------------------------------------------------------
  // Fault reporting
  // --------------------------------------------------------------------------
  output logic                         fault_o,
  output logic [2:0]                   fault_code_o
);

  initial begin
    if (N != 256)
      $display("Warning: mem_bank_idx helper currently assumes 8-bit indices / N=256.");
    if (N % 4 != 0)
      $fatal(1, "poly_mem_wrapper_4bank: N must be divisible by 4");
  end

  localparam int NUM_BANKS  = 4;
  localparam int SLICE_N    = N / NUM_BANKS;
  localparam int BANK_DEPTH = SLICE_N * NUM_POLYS;
  localparam int BANK_AW    = $clog2(BANK_DEPTH);

  localparam logic [2:0] MEM_FAULT_NONE             = 3'b000;
  localparam logic [2:0] MEM_FAULT_RW_SAME_ADDR     = 3'b001;
  localparam logic [2:0] MEM_FAULT_WW_SAME_ADDR     = 3'b010;
  localparam logic [2:0] MEM_FAULT_REQUEST_CONFLICT = 3'b011;

  logic [3:0][1:0]         p0_bank, p1_bank;
  logic [3:0][BANK_AW-1:0] p0_baddr, p1_baddr;

  logic                    p0_has_req, p1_has_req;
  logic                    p0_any_rd,  p1_any_rd;
  logic                    p0_any_wr,  p1_any_wr;
  logic                    p0_is_rd,   p1_is_rd;
  logic                    p0_is_wr,   p1_is_wr;
  logic                    p0_mode_conflict, p1_mode_conflict;

  logic                    p0_req_conflict, p1_req_conflict;
  logic                    rw_same_addr_conflict;
  logic                    ww_same_addr_conflict;
  logic                    fault_detected;

  logic                    p0_fire, p1_fire;

  logic [NUM_BANKS-1:0]              a_we, b_we;
  logic [NUM_BANKS-1:0][BANK_AW-1:0] a_addr, b_addr;
  logic [NUM_BANKS-1:0][W-1:0]       a_wdata, b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]       a_rdata, b_rdata;

  function automatic [1:0] mem_bank_idx(
    input logic [$clog2(N)-1:0] order
  );
    logic [3:0] sum;
    begin
      sum = order[1:0] + order[3:2] + order[5:4] + order[7:6];
      mem_bank_idx = sum[1:0];
    end
  endfunction

  function automatic [BANK_AW-1:0] mem_bank_addr(
    input logic [$clog2(NUM_POLYS)-1:0] pid,
    input logic [$clog2(N)-1:0]         order
  );
    logic [$clog2(SLICE_N)-1:0] row;
    begin
      row = order >> 2;
      mem_bank_addr = pid * SLICE_N + row;
    end
  endfunction

  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : G_DECODE
      assign p0_bank[i]  = mem_bank_idx(p0_idx_i[i]);
      assign p0_baddr[i] = mem_bank_addr(p0_poly_id_i, p0_idx_i[i]);

      assign p1_bank[i]  = mem_bank_idx(p1_idx_i[i]);
      assign p1_baddr[i] = mem_bank_addr(p1_poly_id_i, p1_idx_i[i]);
    end
  endgenerate

  assign p0_any_rd         = |p0_lane_valid_i;
  assign p1_any_rd         = |p1_lane_valid_i;
  assign p0_any_wr         = |p0_wr_en_i;
  assign p1_any_wr         = |p1_wr_en_i;

  // Conflict detection uses raw masks (desire) instead of valid-qualified signals.
  // This ensures p0_ready_o/p1_ready_o are independent of p0_v_i/p1_v_i.
  assign p0_mode_conflict  = p0_any_rd && p0_any_wr;
  assign p1_mode_conflict  = p1_any_rd && p1_any_wr;
  assign p0_is_rd          = p0_any_rd && ~p0_any_wr;
  assign p1_is_rd          = p1_any_rd && ~p1_any_wr;
  assign p0_is_wr          = p0_any_wr && ~p0_any_rd;
  assign p1_is_wr          = p1_any_wr && ~p1_any_rd;

  // Firing logic qualifies with valid bit for actual memory array control.
  // These signals do not feed back into the 'ready' outputs.
  assign p0_has_req        = p0_v_i && (p0_is_rd || p0_is_wr || p0_mode_conflict);
  assign p1_has_req        = p1_v_i && (p1_is_rd || p1_is_wr || p1_mode_conflict);

  integer ii, jj;
  always_comb begin
    p0_req_conflict        = p0_mode_conflict;
    p1_req_conflict        = p1_mode_conflict;
    rw_same_addr_conflict  = 1'b0;
    ww_same_addr_conflict  = 1'b0;

    for (ii = 0; ii < 4; ii++) begin
      for (jj = ii + 1; jj < 4; jj++) begin
        if (p0_is_rd &&
            p0_lane_valid_i[ii] && p0_lane_valid_i[jj] &&
            (p0_bank[ii] == p0_bank[jj]))
          p0_req_conflict = 1'b1;

        if (p1_is_rd &&
            p1_lane_valid_i[ii] && p1_lane_valid_i[jj] &&
            (p1_bank[ii] == p1_bank[jj]))
          p1_req_conflict = 1'b1;

        if (p0_is_wr && p0_wr_en_i[ii] && p0_wr_en_i[jj] &&
            (p0_bank[ii] == p0_bank[jj])) begin
          if (p0_baddr[ii] == p0_baddr[jj])
            ww_same_addr_conflict = 1'b1;
          else
            p0_req_conflict = 1'b1;
        end

        if (p1_is_wr && p1_wr_en_i[ii] && p1_wr_en_i[jj] &&
            (p1_bank[ii] == p1_bank[jj])) begin
          if (p1_baddr[ii] == p1_baddr[jj])
            ww_same_addr_conflict = 1'b1;
          else
            p1_req_conflict = 1'b1;
        end
      end
    end

    if ((p0_is_rd && p1_is_wr) || (p0_is_wr && p1_is_rd)) begin
      for (ii = 0; ii < 4; ii++) begin
        for (jj = 0; jj < 4; jj++) begin
          if (p0_is_rd && p1_is_wr &&
              p0_lane_valid_i[ii] && p1_wr_en_i[jj] &&
              (p0_bank[ii] == p1_bank[jj]) &&
              (p0_baddr[ii] == p1_baddr[jj]))
            rw_same_addr_conflict = 1'b1;

          if (p0_is_wr && p1_is_rd &&
              p0_wr_en_i[ii] && p1_lane_valid_i[jj] &&
              (p0_bank[ii] == p1_bank[jj]) &&
              (p0_baddr[ii] == p1_baddr[jj]))
            rw_same_addr_conflict = 1'b1;
        end
      end
    end

    if (p0_is_wr && p1_is_wr) begin
      for (ii = 0; ii < 4; ii++) begin
        for (jj = 0; jj < 4; jj++) begin
          if (p0_wr_en_i[ii] && p1_wr_en_i[jj] &&
              (p0_bank[ii] == p1_bank[jj]) &&
              (p0_baddr[ii] == p1_baddr[jj]))
            ww_same_addr_conflict = 1'b1;
        end
      end
    end
  end

  assign fault_detected = p0_req_conflict || p1_req_conflict ||
                          rw_same_addr_conflict || ww_same_addr_conflict;

  always_comb begin
    fault_o      = 1'b0;
    fault_code_o = MEM_FAULT_NONE;

    if ((p0_has_req || p1_has_req) && fault_detected) begin
      fault_o = 1'b1;

      if (rw_same_addr_conflict)
        fault_code_o = MEM_FAULT_RW_SAME_ADDR;
      else if (ww_same_addr_conflict)
        fault_code_o = MEM_FAULT_WW_SAME_ADDR;
      else
        fault_code_o = MEM_FAULT_REQUEST_CONFLICT;
    end
  end

  assign p0_ready_o = ~(p0_req_conflict || rw_same_addr_conflict || ww_same_addr_conflict);
  assign p1_ready_o = ~(p1_req_conflict || rw_same_addr_conflict || ww_same_addr_conflict);
  assign p0_fire    = p0_has_req && p0_ready_o;
  assign p1_fire    = p1_has_req && p1_ready_o;

  integer k;
  always_comb begin
    for (k = 0; k < NUM_BANKS; k++) begin
      a_we[k]    = 1'b0;
      a_addr[k]  = '0;
      a_wdata[k] = '0;
      b_we[k]    = 1'b0;
      b_addr[k]  = '0;
      b_wdata[k] = '0;
    end

    if (p0_fire) begin
      for (k = 0; k < 4; k++) begin
        if (p0_is_rd && p0_lane_valid_i[k]) begin
          a_addr[p0_bank[k]] = p0_baddr[k];
        end

        if (p0_is_wr && p0_wr_en_i[k]) begin
          a_we[p0_bank[k]]    = 1'b1;
          a_addr[p0_bank[k]]  = p0_baddr[k];
          a_wdata[p0_bank[k]] = p0_data_i[k];
        end
      end
    end

    if (p1_fire) begin
      for (k = 0; k < 4; k++) begin
        if (p1_is_rd && p1_lane_valid_i[k]) begin
          b_addr[p1_bank[k]] = p1_baddr[k];
        end

        if (p1_is_wr && p1_wr_en_i[k]) begin
          b_we[p1_bank[k]]    = 1'b1;
          b_addr[p1_bank[k]]  = p1_baddr[k];
          b_wdata[p1_bank[k]] = p1_data_i[k];
        end
      end
    end
  end

  genvar b;
  generate
    for (b = 0; b < NUM_BANKS; b++) begin : G_BANK
      poly_ram_bank #(
        .N(BANK_DEPTH),
        .W(W),
        .ADDR_W(BANK_AW)
      ) u_bank (
        .clk   (clk),
        .rst   (rst),
        .a_we  (a_we[b]),
        .a_addr(a_addr[b]),
        .a_wdata(a_wdata[b]),
        .a_rdata(a_rdata[b]),
        .b_we  (b_we[b]),
        .b_addr(b_addr[b]),
        .b_wdata(b_wdata[b]),
        .b_rdata(b_rdata[b])
      );
    end
  endgenerate

  logic                         p0_rd_valid_r, p1_rd_valid_r;
  logic [$clog2(NUM_POLYS)-1:0] p0_rd_poly_id_r, p1_rd_poly_id_r;
  logic [3:0][$clog2(N)-1:0]    p0_rd_idx_r, p1_rd_idx_r;
  logic [3:0]                   p0_rd_lane_valid_r, p1_rd_lane_valid_r;
  logic [3:0][1:0]              p0_rd_bank_r, p1_rd_bank_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      p0_rd_valid_r      <= 1'b0;
      p0_rd_poly_id_r    <= '0;
      p0_rd_idx_r        <= '0;
      p0_rd_lane_valid_r <= '0;
      p0_rd_bank_r       <= '0;

      p1_rd_valid_r      <= 1'b0;
      p1_rd_poly_id_r    <= '0;
      p1_rd_idx_r        <= '0;
      p1_rd_lane_valid_r <= '0;
      p1_rd_bank_r       <= '0;
    end else begin
      p0_rd_valid_r <= p0_fire && p0_is_rd;
      p1_rd_valid_r <= p1_fire && p1_is_rd;

      if (p0_fire && p0_is_rd) begin
        p0_rd_poly_id_r    <= p0_poly_id_i;
        p0_rd_idx_r        <= p0_idx_i;
        p0_rd_lane_valid_r <= p0_lane_valid_i;
        p0_rd_bank_r       <= p0_bank;
      end

      if (p1_fire && p1_is_rd) begin
        p1_rd_poly_id_r    <= p1_poly_id_i;
        p1_rd_idx_r        <= p1_idx_i;
        p1_rd_lane_valid_r <= p1_lane_valid_i;
        p1_rd_bank_r       <= p1_bank;
      end
    end
  end

  always_comb begin
    p0_rd_valid_o      = p0_rd_valid_r;
    p0_rd_poly_id_o    = p0_rd_poly_id_r;
    p0_rd_idx_o        = p0_rd_idx_r;
    p0_rd_lane_valid_o = p0_rd_lane_valid_r;
    p0_rd_data_o       = '0;

    if (p0_rd_valid_r) begin
      if (p0_rd_lane_valid_r[0]) p0_rd_data_o[0] = a_rdata[p0_rd_bank_r[0]];
      if (p0_rd_lane_valid_r[1]) p0_rd_data_o[1] = a_rdata[p0_rd_bank_r[1]];
      if (p0_rd_lane_valid_r[2]) p0_rd_data_o[2] = a_rdata[p0_rd_bank_r[2]];
      if (p0_rd_lane_valid_r[3]) p0_rd_data_o[3] = a_rdata[p0_rd_bank_r[3]];
    end
  end

  always_comb begin
    p1_rd_valid_o      = p1_rd_valid_r;
    p1_rd_poly_id_o    = p1_rd_poly_id_r;
    p1_rd_idx_o        = p1_rd_idx_r;
    p1_rd_lane_valid_o = p1_rd_lane_valid_r;
    p1_rd_data_o       = '0;

    if (p1_rd_valid_r) begin
      if (p1_rd_lane_valid_r[0]) p1_rd_data_o[0] = b_rdata[p1_rd_bank_r[0]];
      if (p1_rd_lane_valid_r[1]) p1_rd_data_o[1] = b_rdata[p1_rd_bank_r[1]];
      if (p1_rd_lane_valid_r[2]) p1_rd_data_o[2] = b_rdata[p1_rd_bank_r[2]];
      if (p1_rd_lane_valid_r[3]) p1_rd_data_o[3] = b_rdata[p1_rd_bank_r[3]];
    end
  end

endmodule
