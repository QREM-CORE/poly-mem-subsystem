`timescale 1ns/1ps

module poly_mem_wrapper_4bank_tb;

  localparam int N         = 256;
  localparam int W         = 16;
  localparam int NUM_POLYS = 8;
  localparam int POLY_W    = $clog2(NUM_POLYS);
  localparam int COEFF_W   = $clog2(N);

  logic clk, rst;

  logic [POLY_W-1:0]    rd_poly_id_i;
  logic                 rd_v_i;
  logic [3:0][COEFF_W-1:0] rd_idx_i;
  logic [3:0]          rd_lane_valid_i;
  logic                rd_ready_o;
  logic                rd_valid_o;
  logic [POLY_W-1:0]   rd_poly_id_o;
  logic [3:0][COEFF_W-1:0] rd_idx_o;
  logic [3:0]          rd_lane_valid_o;
  logic [3:0][W-1:0]   rd_data_o;

  logic [POLY_W-1:0]    wr_poly_id_i;
  logic                 wr_v_i;
  logic [3:0]          wr_en_i;
  logic [3:0][COEFF_W-1:0] wr_idx_i;
  logic [3:0][W-1:0]   wr_data_i;
  logic                wr_ready_o;

  poly_mem_wrapper_4bank #(
    .N(N),
    .W(W),
    .NUM_POLYS(NUM_POLYS)
  ) dut (
    .clk(clk),
    .rst(rst),
    .rd_poly_id_i(rd_poly_id_i),
    .rd_v_i(rd_v_i),
    .rd_idx_i(rd_idx_i),
    .rd_lane_valid_i(rd_lane_valid_i),
    .rd_ready_o(rd_ready_o),
    .rd_valid_o(rd_valid_o),
    .rd_poly_id_o(rd_poly_id_o),
    .rd_idx_o(rd_idx_o),
    .rd_lane_valid_o(rd_lane_valid_o),
    .rd_data_o(rd_data_o),
    .wr_poly_id_i(wr_poly_id_i),
    .wr_v_i(wr_v_i),
    .wr_en_i(wr_en_i),
    .wr_idx_i(wr_idx_i),
    .wr_data_i(wr_data_i),
    .wr_ready_o(wr_ready_o)
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
      rd_poly_id_i     = '0;
      rd_v_i           = 1'b0;
      rd_idx_i         = '0;
      rd_lane_valid_i  = '0;
      wr_poly_id_i     = '0;
      wr_v_i           = 1'b0;
      wr_en_i          = '0;
      wr_idx_i         = '0;
      wr_data_i        = '0;
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_all();
    repeat (2) tick();
    rst = 1'b0;
    tick();

    // ----------------------------------------------------------
    // Write four coefficients using only the write plane.
    // ----------------------------------------------------------
    wr_poly_id_i    = POLY_W'(2);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b1111;
    wr_idx_i[0]     = COEFF_W'(0);
    wr_idx_i[1]     = COEFF_W'(1);
    wr_idx_i[2]     = COEFF_W'(2);
    wr_idx_i[3]     = COEFF_W'(3);
    wr_data_i[0]    = 16'h1000;
    wr_data_i[1]    = 16'h1001;
    wr_data_i[2]    = 16'h1002;
    wr_data_i[3]    = 16'h1003;
    if (!wr_ready_o)
      $fatal(1, "Expected write plane ready for indices 0..3");
    tick();
    clear_all();

    // ----------------------------------------------------------
    // Simultaneous read-plane and write-plane use.
    // ----------------------------------------------------------
    rd_poly_id_i    = POLY_W'(2);
    rd_v_i          = 1'b1;
    rd_idx_i[0]     = COEFF_W'(0);
    rd_idx_i[1]     = COEFF_W'(1);
    rd_idx_i[2]     = COEFF_W'(2);
    rd_idx_i[3]     = COEFF_W'(3);
    rd_lane_valid_i = 4'b1111;

    wr_poly_id_i    = POLY_W'(3);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b1111;
    wr_idx_i[0]     = COEFF_W'(4);
    wr_idx_i[1]     = COEFF_W'(5);
    wr_idx_i[2]     = COEFF_W'(6);
    wr_idx_i[3]     = COEFF_W'(7);
    wr_data_i[0]    = 16'h2000;
    wr_data_i[1]    = 16'h2001;
    wr_data_i[2]    = 16'h2002;
    wr_data_i[3]    = 16'h2003;

    if (!rd_ready_o || !wr_ready_o)
      $fatal(1, "Expected simultaneous read/write plane readiness");
    tick();

    if (!rd_valid_o)
      $fatal(1, "Expected read response after simultaneous plane use");
    if (rd_data_o[0] !== 16'h1000 || rd_data_o[1] !== 16'h1001 ||
        rd_data_o[2] !== 16'h1002 || rd_data_o[3] !== 16'h1003)
      $fatal(1, "Read-plane data mismatch after simultaneous plane use");
    clear_all();

    // ----------------------------------------------------------
    // Read conflict: indices 1 and 4 both map to bank 1 under CMI.
    // ----------------------------------------------------------
    rd_v_i           = 1'b1;
    rd_idx_i[0]      = COEFF_W'(1);
    rd_idx_i[1]      = COEFF_W'(4);
    rd_idx_i[2]      = COEFF_W'(0);
    rd_idx_i[3]      = COEFF_W'(3);
    rd_lane_valid_i  = 4'b1111;
    #1;
    if (rd_ready_o)
      $fatal(1, "Expected read conflict for indices 1 and 4");
    clear_all();

    // ----------------------------------------------------------
    // Write conflict: same conflict pattern on Port B.
    // ----------------------------------------------------------
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b1111;
    wr_idx_i[0]     = COEFF_W'(1);
    wr_idx_i[1]     = COEFF_W'(4);
    wr_idx_i[2]     = COEFF_W'(0);
    wr_idx_i[3]     = COEFF_W'(3);
    #1;
    if (wr_ready_o)
      $fatal(1, "Expected write conflict for indices 1 and 4");
    clear_all();

    $display("TB PASS");
    $finish;
  end

endmodule
