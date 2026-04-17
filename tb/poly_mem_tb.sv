`timescale 1ns/1ps

module poly_mem_tb;

  localparam int NUM_POLYS  = 32;
  localparam int NCOEFF     = 256;
  localparam int W          = 16;
  localparam int SEED_DEPTH = 16;
  localparam int SEED_W     = 64;
  localparam int POLY_W     = $clog2(NUM_POLYS);
  localparam int COEFF_W    = $clog2(NCOEFF);
  localparam int SEED_AW    = $clog2(SEED_DEPTH);

  logic clk, rst_n;

  logic wipe_i;
  logic wipe_done_o;

  logic                           poly_req_i;
  logic [POLY_W-1:0]              poly_id_i;
  logic                           poly_rd_en_i;
  logic                           poly_ready_o;
  logic [3:0][COEFF_W-1:0]        poly_rd_idx_i;
  logic [3:0]                     poly_rd_lane_valid_i;
  logic                           poly_rd_valid_o;
  logic [POLY_W-1:0]              poly_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0]        poly_rd_idx_o;
  logic [3:0]                     poly_rd_lane_valid_o;
  logic [3:0][W-1:0]              poly_rd_data_o;
  logic [3:0]                     poly_wr_en_i;
  logic [3:0][COEFF_W-1:0]        poly_wr_idx_i;
  logic [3:0][W-1:0]              poly_wr_data_i;

  logic                           seed_req_i;
  logic                           seed_we_i;
  logic [SEED_AW-1:0]             seed_addr_i;
  logic [SEED_W-1:0]              seed_wdata_i;
  logic                           seed_ready_o;
  logic                           seed_rvalid_o;
  logic [SEED_W-1:0]              seed_rdata_o;

  poly_mem_subsystem #(
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
    .poly_req_i         (poly_req_i),
    .poly_id_i          (poly_id_i),
    .poly_rd_en_i       (poly_rd_en_i),
    .poly_ready_o       (poly_ready_o),
    .poly_rd_idx_i      (poly_rd_idx_i),
    .poly_rd_lane_valid_i(poly_rd_lane_valid_i),
    .poly_rd_valid_o    (poly_rd_valid_o),
    .poly_rd_poly_id_o  (poly_rd_poly_id_o),
    .poly_rd_idx_o      (poly_rd_idx_o),
    .poly_rd_lane_valid_o(poly_rd_lane_valid_o),
    .poly_rd_data_o     (poly_rd_data_o),
    .poly_wr_en_i       (poly_wr_en_i),
    .poly_wr_idx_i      (poly_wr_idx_i),
    .poly_wr_data_i     (poly_wr_data_i),
    .seed_req_i         (seed_req_i),
    .seed_we_i          (seed_we_i),
    .seed_addr_i        (seed_addr_i),
    .seed_wdata_i       (seed_wdata_i),
    .seed_ready_o       (seed_ready_o),
    .seed_rvalid_o      (seed_rvalid_o),
    .seed_rdata_o       (seed_rdata_o)
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
      wipe_i               = 1'b0;
      poly_req_i           = 1'b0;
      poly_id_i            = '0;
      poly_rd_en_i         = 1'b0;
      poly_rd_idx_i        = '0;
      poly_rd_lane_valid_i = '0;
      poly_wr_en_i         = '0;
      poly_wr_idx_i        = '0;
      poly_wr_data_i       = '0;
      seed_req_i           = 1'b0;
      seed_we_i            = 1'b0;
      seed_addr_i          = '0;
      seed_wdata_i         = '0;
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

  initial begin
    reset_all();

    // ----------------------------------------------------------
    // 1) Write one vector row
    // ----------------------------------------------------------
    @(posedge clk);
    poly_req_i           <= 1'b1;
    poly_id_i            <= POLY_W'(3);
    poly_rd_en_i         <= 1'b0;
    poly_wr_en_i         <= 4'b1111;
    poly_wr_idx_i[0]     <= COEFF_W'(8);
    poly_wr_idx_i[1]     <= COEFF_W'(9);
    poly_wr_idx_i[2]     <= COEFF_W'(10);
    poly_wr_idx_i[3]     <= COEFF_W'(11);
    poly_wr_data_i[0]    <= 16'h3000;
    poly_wr_data_i[1]    <= 16'h3001;
    poly_wr_data_i[2]    <= 16'h3002;
    poly_wr_data_i[3]    <= 16'h3003;

    @(posedge clk);
    poly_req_i        <= 1'b0;
    poly_wr_en_i      <= '0;
    poly_wr_idx_i     <= '0;
    poly_wr_data_i    <= '0;

    // ----------------------------------------------------------
    // 2) Read back vector row
    // ----------------------------------------------------------
    @(posedge clk);
    poly_req_i           <= 1'b1;
    poly_id_i            <= POLY_W'(3);
    poly_rd_en_i         <= 1'b1;
    poly_rd_idx_i[0]     <= COEFF_W'(8);
    poly_rd_idx_i[1]     <= COEFF_W'(9);
    poly_rd_idx_i[2]     <= COEFF_W'(10);
    poly_rd_idx_i[3]     <= COEFF_W'(11);
    poly_rd_lane_valid_i <= 4'b1111;

    @(posedge clk);
    poly_req_i           <= 1'b0;
    poly_rd_en_i         <= 1'b0;
    poly_rd_lane_valid_i <= '0;

    #1;
    if (!poly_rd_valid_o)
      $fatal(1, "Expected read response from poly_mem_subsystem");
    if (poly_rd_data_o[0] !== 16'h3000 || poly_rd_data_o[1] !== 16'h3001 ||
        poly_rd_data_o[2] !== 16'h3002 || poly_rd_data_o[3] !== 16'h3003)
      $fatal(1, "Vector readback mismatch");

    // ----------------------------------------------------------
    // 3) Seed store smoke test
    // ----------------------------------------------------------
    @(posedge clk);
    seed_req_i   <= 1'b1;
    seed_we_i    <= 1'b1;
    seed_addr_i  <= SEED_AW'(2);
    seed_wdata_i <= 64'hFACE_CAFE_1234_5678;

    @(posedge clk);
    seed_req_i   <= 1'b0;
    seed_we_i    <= 1'b0;

    @(posedge clk);
    seed_req_i   <= 1'b1;
    seed_we_i    <= 1'b0;
    seed_addr_i  <= SEED_AW'(2);

    @(posedge clk);
    seed_req_i <= 1'b0;

    #1;
    if (!seed_rvalid_o || seed_rdata_o !== 64'hFACE_CAFE_1234_5678)
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
    poly_req_i           <= 1'b1;
    poly_id_i            <= POLY_W'(3);
    poly_rd_en_i         <= 1'b1;
    poly_rd_idx_i[0]     <= COEFF_W'(8);
    poly_rd_idx_i[1]     <= COEFF_W'(9);
    poly_rd_idx_i[2]     <= COEFF_W'(10);
    poly_rd_idx_i[3]     <= COEFF_W'(11);
    poly_rd_lane_valid_i <= 4'b1111;

    @(posedge clk);
    poly_req_i           <= 1'b0;
    poly_rd_en_i         <= 1'b0;
    poly_rd_lane_valid_i <= '0;

    #1;
    if (!poly_rd_valid_o)
      $fatal(1, "Expected read response after wipe");
    if (poly_rd_data_o[0] !== 16'h0000 || poly_rd_data_o[1] !== 16'h0000 ||
        poly_rd_data_o[2] !== 16'h0000 || poly_rd_data_o[3] !== 16'h0000)
      $fatal(1, "Polynomial wipe failed");

    @(posedge clk);
    seed_req_i  <= 1'b1;
    seed_we_i   <= 1'b0;
    seed_addr_i <= SEED_AW'(2);
    @(posedge clk);
    seed_req_i <= 1'b0;
    #1;
    if (!seed_rvalid_o || seed_rdata_o !== 64'h0)
      $fatal(1, "Seed wipe failed");

    $display("TB PASS");
    $finish;
  end

endmodule
