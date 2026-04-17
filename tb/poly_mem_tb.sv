`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// poly_mem_tb — PAU-only smoke test for the refactored poly_mem_subsystem.
//
// Exercises the PAU client vector write/read, seed store, and security wipe
// paths.  For full arbitration/isolation tests see mem_frontend_top_tb.
// ---------------------------------------------------------------------------

module poly_mem_tb;

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 16;
  localparam int SEED_W     = 64;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_W    = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);

  logic clk, rst;

  logic wipe_i;
  logic wipe_done_o;

  // PAU interface
  logic                           pau_req;
  logic [POLY_W-1:0]              pau_poly_id;
  logic                           pau_rd_en;
  logic [3:0][COEFF_W-1:0]        pau_rd_idx;
  logic [3:0]                     pau_rd_lane_valid;
  logic [3:0]                     pau_wr_en;
  logic [3:0][COEFF_W-1:0]        pau_wr_idx;
  logic [3:0][W-1:0]              pau_wr_data;
  logic                           pau_rd_valid;
  logic [POLY_W-1:0]              pau_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        pau_rd_idx_o;
  logic [3:0]                     pau_rd_lane_valid_o;
  logic [3:0][W-1:0]              pau_rd_data;
  logic                           pau_stall;

  // HSU interface (active-low, unused)
  logic                           hsu_req;
  logic [POLY_W-1:0]              hsu_poly_id;
  logic                           hsu_rd_en;
  logic [3:0][COEFF_W-1:0]        hsu_rd_idx;
  logic [3:0]                     hsu_rd_lane_valid;
  logic [3:0]                     hsu_wr_en;
  logic [3:0][COEFF_W-1:0]        hsu_wr_idx;
  logic [3:0][W-1:0]              hsu_wr_data;
  logic                           hsu_rd_valid;
  logic [POLY_W-1:0]              hsu_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        hsu_rd_idx_o;
  logic [3:0]                     hsu_rd_lane_valid_o;
  logic [3:0][W-1:0]              hsu_rd_data;
  logic                           hsu_stall;

  // Transcoder interface (unused)
  logic                           tr_req;
  logic [POLY_W-1:0]              tr_poly_id;
  logic                           tr_rd_en;
  logic [3:0][COEFF_W-1:0]        tr_rd_idx;
  logic [3:0]                     tr_rd_lane_valid;
  logic [3:0]                     tr_wr_en;
  logic [3:0][COEFF_W-1:0]        tr_wr_idx;
  logic [3:0][W-1:0]              tr_wr_data;
  logic                           tr_rd_valid;
  logic [POLY_W-1:0]              tr_rd_poly_id;
  logic [3:0][COEFF_W-1:0]        tr_rd_idx_o;
  logic [3:0]                     tr_rd_lane_valid_o;
  logic [3:0][W-1:0]              tr_rd_data;
  logic                           tr_stall;

  // Seed interface
  logic                           seed_req;
  logic                           seed_we;
  logic [SEED_AW-1:0]             seed_addr;
  logic [SEED_W-1:0]              seed_wdata;
  logic                           seed_ready;
  logic                           seed_rvalid;
  logic [SEED_W-1:0]              seed_rdata;

  poly_mem_subsystem #(
    .NUM_POLYS  (NUM_POLYS),
    .NCOEFF     (NCOEFF),
    .W          (W),
    .SEED_DEPTH (SEED_DEPTH),
    .SEED_W     (SEED_W)
  ) dut (
    .clk                (clk),
    .rst                (rst),
    .wipe_i             (wipe_i),
    .wipe_done_o        (wipe_done_o),
    .pau_req            (pau_req),
    .pau_poly_id        (pau_poly_id),
    .pau_rd_en          (pau_rd_en),
    .pau_rd_idx         (pau_rd_idx),
    .pau_rd_lane_valid  (pau_rd_lane_valid),
    .pau_wr_en          (pau_wr_en),
    .pau_wr_idx         (pau_wr_idx),
    .pau_wr_data        (pau_wr_data),
    .pau_rd_valid       (pau_rd_valid),
    .pau_rd_poly_id     (pau_rd_poly_id),
    .pau_rd_idx_o       (pau_rd_idx_o),
    .pau_rd_lane_valid_o(pau_rd_lane_valid_o),
    .pau_rd_data        (pau_rd_data),
    .pau_stall          (pau_stall),
    .hsu_req            (hsu_req),
    .hsu_poly_id        (hsu_poly_id),
    .hsu_rd_en          (hsu_rd_en),
    .hsu_rd_idx         (hsu_rd_idx),
    .hsu_rd_lane_valid  (hsu_rd_lane_valid),
    .hsu_wr_en          (hsu_wr_en),
    .hsu_wr_idx         (hsu_wr_idx),
    .hsu_wr_data        (hsu_wr_data),
    .hsu_rd_valid       (hsu_rd_valid),
    .hsu_rd_poly_id     (hsu_rd_poly_id),
    .hsu_rd_idx_o       (hsu_rd_idx_o),
    .hsu_rd_lane_valid_o(hsu_rd_lane_valid_o),
    .hsu_rd_data        (hsu_rd_data),
    .hsu_stall          (hsu_stall),
    .tr_req             (tr_req),
    .tr_poly_id         (tr_poly_id),
    .tr_rd_en           (tr_rd_en),
    .tr_rd_idx          (tr_rd_idx),
    .tr_rd_lane_valid   (tr_rd_lane_valid),
    .tr_wr_en           (tr_wr_en),
    .tr_wr_idx          (tr_wr_idx),
    .tr_wr_data         (tr_wr_data),
    .tr_rd_valid        (tr_rd_valid),
    .tr_rd_poly_id      (tr_rd_poly_id),
    .tr_rd_idx_o        (tr_rd_idx_o),
    .tr_rd_lane_valid_o (tr_rd_lane_valid_o),
    .tr_rd_data         (tr_rd_data),
    .tr_stall           (tr_stall),
    .seed_req           (seed_req),
    .seed_we            (seed_we),
    .seed_addr          (seed_addr),
    .seed_wdata         (seed_wdata),
    .seed_ready         (seed_ready),
    .seed_rvalid        (seed_rvalid),
    .seed_rdata         (seed_rdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic clear_all;
    begin
      wipe_i            = 1'b0;

      pau_req           = 1'b0;
      pau_poly_id       = '0;
      pau_rd_en         = 1'b0;
      pau_rd_idx        = '0;
      pau_rd_lane_valid = '0;
      pau_wr_en         = '0;
      pau_wr_idx        = '0;
      pau_wr_data       = '0;

      hsu_req           = 1'b0;
      hsu_poly_id       = '0;
      hsu_rd_en         = 1'b0;
      hsu_rd_idx        = '0;
      hsu_rd_lane_valid = '0;
      hsu_wr_en         = '0;
      hsu_wr_idx        = '0;
      hsu_wr_data       = '0;

      tr_req            = 1'b0;
      tr_poly_id        = '0;
      tr_rd_en          = 1'b0;
      tr_rd_idx         = '0;
      tr_rd_lane_valid  = '0;
      tr_wr_en          = '0;
      tr_wr_idx         = '0;
      tr_wr_data        = '0;

      seed_req          = 1'b0;
      seed_we           = 1'b0;
      seed_addr         = '0;
      seed_wdata        = '0;
    end
  endtask

  task automatic reset_all;
    begin
      clear_all();
      rst = 1'b0;
      repeat (3) tick();
      rst = 1'b1;
      repeat (2) tick();
    end
  endtask

  initial begin
    reset_all();

    // ----------------------------------------------------------
    // 1) PAU write one vector row
    // ----------------------------------------------------------
    @(posedge clk);
    pau_req           <= 1'b1;
    pau_poly_id       <= POLY_W'(3);
    pau_rd_en         <= 1'b0;
    pau_wr_en         <= 4'b1111;
    pau_wr_idx[0]     <= COEFF_W'(8);
    pau_wr_idx[1]     <= COEFF_W'(9);
    pau_wr_idx[2]     <= COEFF_W'(10);
    pau_wr_idx[3]     <= COEFF_W'(11);
    pau_wr_data[0]    <= 16'h3000;
    pau_wr_data[1]    <= 16'h3001;
    pau_wr_data[2]    <= 16'h3002;
    pau_wr_data[3]    <= 16'h3003;

    @(posedge clk);
    pau_req        <= 1'b0;
    pau_wr_en      <= '0;
    pau_wr_idx     <= '0;
    pau_wr_data    <= '0;

    // ----------------------------------------------------------
    // 2) PAU read back vector row
    // ----------------------------------------------------------
    @(posedge clk);
    pau_req           <= 1'b1;
    pau_poly_id       <= POLY_W'(3);
    pau_rd_en         <= 1'b1;
    pau_rd_idx[0]     <= COEFF_W'(8);
    pau_rd_idx[1]     <= COEFF_W'(9);
    pau_rd_idx[2]     <= COEFF_W'(10);
    pau_rd_idx[3]     <= COEFF_W'(11);
    pau_rd_lane_valid <= 4'b1111;

    @(posedge clk);
    pau_req           <= 1'b0;
    pau_rd_en         <= 1'b0;
    pau_rd_lane_valid <= '0;

    #1;
    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response from poly_mem_subsystem");
    if (pau_rd_data[0] !== 16'h3000 || pau_rd_data[1] !== 16'h3001 ||
        pau_rd_data[2] !== 16'h3002 || pau_rd_data[3] !== 16'h3003)
      $fatal(1, "PAU vector readback mismatch");

    // ----------------------------------------------------------
    // 3) Seed store smoke test
    // ----------------------------------------------------------
    @(posedge clk);
    seed_req   <= 1'b1;
    seed_we    <= 1'b1;
    seed_addr  <= SEED_AW'(2);
    seed_wdata <= 64'hFACE_CAFE_1234_5678;

    @(posedge clk);
    seed_req   <= 1'b0;
    seed_we    <= 1'b0;

    @(posedge clk);
    seed_req  <= 1'b1;
    seed_we   <= 1'b0;
    seed_addr <= SEED_AW'(2);

    @(posedge clk);
    seed_req <= 1'b0;

    #1;
    if (!seed_rvalid || seed_rdata !== 64'hFACE_CAFE_1234_5678)
      $fatal(1, "Seed store readback mismatch");

    // ----------------------------------------------------------
    // 4) Wipe clears both memories
    // ----------------------------------------------------------
    @(posedge clk);
    wipe_i <= 1'b1;
    @(posedge clk);
    wipe_i <= 1'b0;

    wait (wipe_done_o == 1'b1);
    @(posedge clk);

    @(posedge clk);
    pau_req           <= 1'b1;
    pau_poly_id       <= POLY_W'(3);
    pau_rd_en         <= 1'b1;
    pau_rd_idx[0]     <= COEFF_W'(8);
    pau_rd_idx[1]     <= COEFF_W'(9);
    pau_rd_idx[2]     <= COEFF_W'(10);
    pau_rd_idx[3]     <= COEFF_W'(11);
    pau_rd_lane_valid <= 4'b1111;

    @(posedge clk);
    pau_req           <= 1'b0;
    pau_rd_en         <= 1'b0;
    pau_rd_lane_valid <= '0;

    #1;
    if (!pau_rd_valid)
      $fatal(1, "Expected PAU read response after wipe");
    if (pau_rd_data[0] !== 16'h0000 || pau_rd_data[1] !== 16'h0000 ||
        pau_rd_data[2] !== 16'h0000 || pau_rd_data[3] !== 16'h0000)
      $fatal(1, "Polynomial wipe failed");

    @(posedge clk);
    seed_req  <= 1'b1;
    seed_we   <= 1'b0;
    seed_addr <= SEED_AW'(2);
    @(posedge clk);
    seed_req <= 1'b0;
    #1;
    if (!seed_rvalid || seed_rdata !== 64'h0)
      $fatal(1, "Seed wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
