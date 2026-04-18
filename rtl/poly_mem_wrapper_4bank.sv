/*
 * Module Name: poly_mem_wrapper_4bank
 * Author(s): Mavra Muzmmal, Jessica Buentipo, Quardin Lyttle
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Description:
 *   Four-bank true-dual-port polynomial memory wrapper for the QREM core.
 *
 *   The important architectural shift in v0.75 is that the subsystem should
 *   actively exploit the physical Port A / Port B split:
 *     - Port A services one 4-lane READ plane per cycle
 *     - Port B services one 4-lane WRITE plane per cycle
 *
 *   That means:
 *     - one read owner and one write owner may be accepted in the same cycle
 *     - read-vs-write same-bank overlap is legal because they use different
 *       RAM ports
 *     - read-read conflicts and write-write conflicts are still blocked
 *
 * Notes:
 *   - Reset is active-high and synchronous.
 *   - Read response latency is 1 cycle from accepted read request.
 *   - CMI bit-pair-sum bank mapping is used for both planes.
 */

module poly_mem_wrapper_4bank #(
  parameter int N         = 256,
  parameter int W         = 16,
  parameter int NUM_POLYS = 32
)(
  input  logic clk,
  input  logic rst,

  // --------------------------------------------------------------------------
  // Read plane (Port A of the banked RAMs)
  // --------------------------------------------------------------------------
  input  logic [$clog2(NUM_POLYS)-1:0] rd_poly_id_i,
  input  logic                         rd_v_i,
  input  logic [3:0][$clog2(N)-1:0]    rd_idx_i,
  input  logic [3:0]                   rd_lane_valid_i,
  output logic                         rd_ready_o,

  output logic                         rd_valid_o,
  output logic [$clog2(NUM_POLYS)-1:0] rd_poly_id_o,
  output logic [3:0][$clog2(N)-1:0]    rd_idx_o,
  output logic [3:0]                   rd_lane_valid_o,
  output logic [3:0][W-1:0]            rd_data_o,

  // --------------------------------------------------------------------------
  // Write plane (Port B of the banked RAMs)
  // --------------------------------------------------------------------------
  input  logic [$clog2(NUM_POLYS)-1:0] wr_poly_id_i,
  input  logic                         wr_v_i,
  input  logic [3:0]                   wr_en_i,
  input  logic [3:0][$clog2(N)-1:0]    wr_idx_i,
  input  logic [3:0][W-1:0]            wr_data_i,
  output logic                         wr_ready_o
);

  initial begin
    if (N != 256)
      $display("Warning: cmi_bank_idx helper currently assumes 8-bit indices / N=256.");
    if (N % 4 != 0)
      $fatal(1, "poly_mem_wrapper_4bank: N must be divisible by 4");
  end

  localparam int NUM_BANKS  = 4;
  localparam int SLICE_N    = N / NUM_BANKS;
  localparam int BANK_DEPTH = SLICE_N * NUM_POLYS;
  localparam int BANK_AW    = $clog2(BANK_DEPTH);

  logic [3:0][1:0]         rd_bank;
  logic [3:0][BANK_AW-1:0] rd_baddr;
  logic [3:0][1:0]         wr_bank;
  logic [3:0][BANK_AW-1:0] wr_baddr;

  logic                    rd_fire;
  logic                    wr_fire;
  logic                    rd_conflict;
  logic                    wr_conflict;
  logic                    any_rd;
  logic                    any_wr;

  logic [NUM_BANKS-1:0]              a_we, b_we;
  logic [NUM_BANKS-1:0][BANK_AW-1:0] a_addr, b_addr;
  logic [NUM_BANKS-1:0][W-1:0]       a_wdata, b_wdata;
  logic [NUM_BANKS-1:0][W-1:0]       a_rdata, b_rdata;

  function automatic [1:0] cmi_bank_idx(
    input logic [$clog2(N)-1:0] order
  );
    logic [3:0] sum;
    begin
      sum = order[1:0] + order[3:2] + order[5:4] + order[7:6];
      cmi_bank_idx = sum[1:0];
    end
  endfunction

  function automatic [BANK_AW-1:0] cmi_bank_addr(
    input logic [$clog2(NUM_POLYS)-1:0] pid,
    input logic [$clog2(N)-1:0]         order
  );
    logic [$clog2(SLICE_N)-1:0] row;
    begin
      row = order >> 2;
      cmi_bank_addr = pid * SLICE_N + row;
    end
  endfunction

  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : G_DECODE
      assign rd_bank[i]  = cmi_bank_idx(rd_idx_i[i]);
      assign rd_baddr[i] = cmi_bank_addr(rd_poly_id_i, rd_idx_i[i]);

      assign wr_bank[i]  = cmi_bank_idx(wr_idx_i[i]);
      assign wr_baddr[i] = cmi_bank_addr(wr_poly_id_i, wr_idx_i[i]);
    end
  endgenerate

  integer ii, jj;
  always_comb begin
    rd_conflict = 1'b0;
    wr_conflict = 1'b0;
    any_rd      = 1'b0;
    any_wr      = 1'b0;

    for (ii = 0; ii < 4; ii++) begin
      any_rd |= rd_lane_valid_i[ii];
      any_wr |= wr_en_i[ii];
    end

    for (ii = 0; ii < 4; ii++) begin
      for (jj = ii + 1; jj < 4; jj++) begin
        if (rd_lane_valid_i[ii] && rd_lane_valid_i[jj] && (rd_bank[ii] == rd_bank[jj]))
          rd_conflict = 1'b1;

        if (wr_en_i[ii] && wr_en_i[jj] && (wr_bank[ii] == wr_bank[jj]))
          wr_conflict = 1'b1;
      end
    end
  end

  assign rd_ready_o = ~rd_conflict;
  assign wr_ready_o = ~wr_conflict;
  assign rd_fire    = rd_v_i && rd_ready_o;
  assign wr_fire    = wr_v_i && wr_ready_o;

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

    if (rd_fire) begin
      for (k = 0; k < 4; k++) begin
        if (rd_lane_valid_i[k]) begin
          a_addr[rd_bank[k]] = rd_baddr[k];
        end
      end
    end

    if (wr_fire) begin
      for (k = 0; k < 4; k++) begin
        if (wr_en_i[k]) begin
          b_we[wr_bank[k]]    = 1'b1;
          b_addr[wr_bank[k]]  = wr_baddr[k];
          b_wdata[wr_bank[k]] = wr_data_i[k];
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

  logic                         rd_valid_r;
  logic [$clog2(NUM_POLYS)-1:0] rd_poly_id_r;
  logic [3:0][$clog2(N)-1:0]    rd_idx_r;
  logic [3:0]                   rd_lane_valid_r;
  logic [3:0][1:0]              rd_bank_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_valid_r      <= 1'b0;
      rd_poly_id_r    <= '0;
      rd_idx_r        <= '0;
      rd_lane_valid_r <= '0;
      rd_bank_r       <= '0;
    end else begin
      rd_valid_r <= rd_fire;

      if (rd_fire) begin
        rd_poly_id_r    <= rd_poly_id_i;
        rd_idx_r        <= rd_idx_i;
        rd_lane_valid_r <= rd_lane_valid_i;
        rd_bank_r       <= rd_bank;
      end
    end
  end

  always_comb begin
    rd_valid_o      = rd_valid_r;
    rd_poly_id_o    = rd_poly_id_r;
    rd_idx_o        = rd_idx_r;
    rd_lane_valid_o = rd_lane_valid_r;
    rd_data_o       = '0;

    if (rd_valid_r) begin
      if (rd_lane_valid_r[0]) rd_data_o[0] = a_rdata[rd_bank_r[0]];
      if (rd_lane_valid_r[1]) rd_data_o[1] = a_rdata[rd_bank_r[1]];
      if (rd_lane_valid_r[2]) rd_data_o[2] = a_rdata[rd_bank_r[2]];
      if (rd_lane_valid_r[3]) rd_data_o[3] = a_rdata[rd_bank_r[3]];
    end
  end

endmodule
