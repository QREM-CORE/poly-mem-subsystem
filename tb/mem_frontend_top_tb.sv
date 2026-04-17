`timescale 1ns/1ps

module mem_frontend_top_tb;

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 16;
  localparam int SEED_W     = 64;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_W    = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);

  logic clk;
  logic rst_n;

  logic wipe_i;
  logic wipe_done_o;

  // PAU
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

  // HSU
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

  // Transcoder
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

  // Seed
  logic                           seed_req;
  logic                           seed_we;
  logic [SEED_AW-1:0]             seed_addr;
  logic [SEED_W-1:0]              seed_wdata;
  logic                           seed_ready;
  logic                           seed_rvalid;
  logic [SEED_W-1:0]              seed_rdata;

  mem_frontend_top #(
    .NUM_POLYS  (NUM_POLYS),
    .NCOEFF     (NCOEFF),
    .W          (W),
    .SEED_DEPTH (SEED_DEPTH),
    .SEED_W     (SEED_W)
  ) dut (
    .clk                (clk),
    .rst_n              (rst_n),
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
      wipe_i             = 1'b0;

      pau_req            = 1'b0;
      pau_poly_id        = '0;
      pau_rd_en          = 1'b0;
      pau_rd_idx         = '0;
      pau_rd_lane_valid  = '0;
      pau_wr_en          = '0;
      pau_wr_idx         = '0;
      pau_wr_data        = '0;

      hsu_req            = 1'b0;
      hsu_poly_id        = '0;
      hsu_rd_en          = 1'b0;
      hsu_rd_idx         = '0;
      hsu_rd_lane_valid  = '0;
      hsu_wr_en          = '0;
      hsu_wr_idx         = '0;
      hsu_wr_data        = '0;

      tr_req             = 1'b0;
      tr_poly_id         = '0;
      tr_rd_en           = 1'b0;
      tr_rd_idx          = '0;
      tr_rd_lane_valid   = '0;
      tr_wr_en           = '0;
      tr_wr_idx          = '0;
      tr_wr_data         = '0;

      seed_req           = 1'b0;
      seed_we            = 1'b0;
      seed_addr          = '0;
      seed_wdata         = '0;
    end
  endtask

  task automatic reset_all;
    begin
      clear_all();
      rst_n = 1'b0;
      repeat (3) tick();
      rst_n = 1'b1;
      repeat (2) tick();
    end
  endtask

  task automatic pau_write_4(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      @(posedge clk);
      pau_req           <= 1'b1;
      pau_poly_id       <= POLY_W'(poly_id);
      pau_rd_en         <= 1'b0;
      pau_wr_en         <= 4'b1111;
      pau_wr_idx[0]     <= COEFF_W'(idx0);
      pau_wr_idx[1]     <= COEFF_W'(idx1);
      pau_wr_idx[2]     <= COEFF_W'(idx2);
      pau_wr_idx[3]     <= COEFF_W'(idx3);
      pau_wr_data[0]    <= d0;
      pau_wr_data[1]    <= d1;
      pau_wr_data[2]    <= d2;
      pau_wr_data[3]    <= d3;

      @(posedge clk);
      pau_req        <= 1'b0;
      pau_wr_en      <= '0;
      pau_wr_idx     <= '0;
      pau_wr_data    <= '0;
    end
  endtask

  task automatic pau_read_4_check(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] e0, input logic [W-1:0] e1,
    input logic [W-1:0] e2, input logic [W-1:0] e3
  );
    begin
      @(posedge clk);
      pau_req              <= 1'b1;
      pau_poly_id          <= POLY_W'(poly_id);
      pau_rd_en            <= 1'b1;
      pau_rd_idx[0]        <= COEFF_W'(idx0);
      pau_rd_idx[1]        <= COEFF_W'(idx1);
      pau_rd_idx[2]        <= COEFF_W'(idx2);
      pau_rd_idx[3]        <= COEFF_W'(idx3);
      pau_rd_lane_valid    <= 4'b1111;

      @(posedge clk);
      pau_req           <= 1'b0;
      pau_rd_en         <= 1'b0;
      pau_rd_lane_valid <= '0;

      #1;
      if (!pau_rd_valid)
        $fatal(1, "PAU read response expected");
      if (pau_rd_data[0] !== e0 || pau_rd_data[1] !== e1 ||
          pau_rd_data[2] !== e2 || pau_rd_data[3] !== e3)
        $fatal(1, "PAU vector read mismatch");
    end
  endtask

  task automatic hsu_write_4(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      @(posedge clk);
      hsu_req           <= 1'b1;
      hsu_poly_id       <= POLY_W'(poly_id);
      hsu_rd_en         <= 1'b0;
      hsu_wr_en         <= 4'b1111;
      hsu_wr_idx[0]     <= COEFF_W'(idx0);
      hsu_wr_idx[1]     <= COEFF_W'(idx1);
      hsu_wr_idx[2]     <= COEFF_W'(idx2);
      hsu_wr_idx[3]     <= COEFF_W'(idx3);
      hsu_wr_data[0]    <= d0;
      hsu_wr_data[1]    <= d1;
      hsu_wr_data[2]    <= d2;
      hsu_wr_data[3]    <= d3;

      @(posedge clk);
      hsu_req        <= 1'b0;
      hsu_wr_en      <= '0;
      hsu_wr_idx     <= '0;
      hsu_wr_data    <= '0;
    end
  endtask

  task automatic tr_read_4_check(
    input int poly_id,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] e0, input logic [W-1:0] e1,
    input logic [W-1:0] e2, input logic [W-1:0] e3
  );
    begin
      @(posedge clk);
      tr_req              <= 1'b1;
      tr_poly_id          <= POLY_W'(poly_id);
      tr_rd_en            <= 1'b1;
      tr_rd_idx[0]        <= COEFF_W'(idx0);
      tr_rd_idx[1]        <= COEFF_W'(idx1);
      tr_rd_idx[2]        <= COEFF_W'(idx2);
      tr_rd_idx[3]        <= COEFF_W'(idx3);
      tr_rd_lane_valid    <= 4'b1111;

      @(posedge clk);
      tr_req           <= 1'b0;
      tr_rd_en         <= 1'b0;
      tr_rd_lane_valid <= '0;

      #1;
      if (!tr_rd_valid)
        $fatal(1, "Transcoder read response expected");
      if (tr_rd_data[0] !== e0 || tr_rd_data[1] !== e1 ||
          tr_rd_data[2] !== e2 || tr_rd_data[3] !== e3)
        $fatal(1, "Transcoder vector read mismatch");
    end
  endtask

  task automatic seed_write_then_read_check;
    begin
      @(posedge clk);
      seed_req   <= 1'b1;
      seed_we    <= 1'b1;
      seed_addr  <= SEED_AW'(3);
      seed_wdata <= 64'h0123_4567_89AB_CDEF;

      @(posedge clk);
      seed_req   <= 1'b0;
      seed_we    <= 1'b0;
      seed_wdata <= '0;

      @(posedge clk);
      seed_req  <= 1'b1;
      seed_we   <= 1'b0;
      seed_addr <= SEED_AW'(3);

      @(posedge clk);
      seed_req <= 1'b0;

      #1;
      if (!seed_rvalid)
        $fatal(1, "Seed read response expected");
      if (seed_rdata !== 64'h0123_4567_89AB_CDEF)
        $fatal(1, "Seed read mismatch");
    end
  endtask

  initial begin
    reset_all();

    // ----------------------------------------------------------
    // 1) PAU vector write/read
    // ----------------------------------------------------------
    pau_write_4(2, 0, 1, 2, 3, 16'h1000, 16'h1001, 16'h1002, 16'h1003);
    pau_read_4_check(2, 0, 1, 2, 3, 16'h1000, 16'h1001, 16'h1002, 16'h1003);

    // ----------------------------------------------------------
    // 2) HSU writes a sampled row, Transcoder reads it later
    // ----------------------------------------------------------
    hsu_write_4(5, 4, 5, 6, 7, 16'h2000, 16'h2001, 16'h2002, 16'h2003);
    tr_read_4_check(5, 4, 5, 6, 7, 16'h2000, 16'h2001, 16'h2002, 16'h2003);

    // ----------------------------------------------------------
    // 3) Arbitration: PAU beats HSU and HSU must not see PAU read data
    // ----------------------------------------------------------
    @(posedge clk);
    pau_req           <= 1'b1;
    pau_poly_id       <= POLY_W'(2);
    pau_rd_en         <= 1'b1;
    pau_rd_idx[0]     <= COEFF_W'(0);
    pau_rd_idx[1]     <= COEFF_W'(1);
    pau_rd_idx[2]     <= COEFF_W'(2);
    pau_rd_idx[3]     <= COEFF_W'(3);
    pau_rd_lane_valid <= 4'b1111;

    hsu_req           <= 1'b1;
    hsu_poly_id       <= POLY_W'(5);
    hsu_rd_en         <= 1'b1;
    hsu_rd_idx[0]     <= COEFF_W'(4);
    hsu_rd_idx[1]     <= COEFF_W'(5);
    hsu_rd_idx[2]     <= COEFF_W'(6);
    hsu_rd_idx[3]     <= COEFF_W'(7);
    hsu_rd_lane_valid <= 4'b1111;
    #1;

    if (pau_stall !== 1'b0)
      $fatal(1, "PAU should win arbitration");
    if (hsu_stall !== 1'b1)
      $fatal(1, "HSU should stall behind PAU");

    @(posedge clk);
    pau_req           <= 1'b0;
    pau_rd_en         <= 1'b0;
    pau_rd_lane_valid <= '0;
    hsu_req           <= 1'b0;
    hsu_rd_en         <= 1'b0;
    hsu_rd_lane_valid <= '0;

    #1;
    if (!pau_rd_valid)
      $fatal(1, "PAU response expected");
    if (hsu_rd_valid)
      $fatal(1, "HSU must not see PAU read response");

    // ----------------------------------------------------------
    // 4) Seed store path
    // ----------------------------------------------------------
    seed_write_then_read_check();

    // ----------------------------------------------------------
    // 5) Wipe clears both polynomial memory and seed store
    // ----------------------------------------------------------
    @(posedge clk);
    wipe_i <= 1'b1;
    @(posedge clk);
    wipe_i <= 1'b0;

    wait (wipe_done_o == 1'b1);
    @(posedge clk);

    pau_read_4_check(2, 0, 1, 2, 3, 16'h0000, 16'h0000, 16'h0000, 16'h0000);

    @(posedge clk);
    seed_req  <= 1'b1;
    seed_we   <= 1'b0;
    seed_addr <= SEED_AW'(3);
    @(posedge clk);
    seed_req <= 1'b0;
    #1;
    if (!seed_rvalid || seed_rdata !== 64'h0)
      $fatal(1, "Seed wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
