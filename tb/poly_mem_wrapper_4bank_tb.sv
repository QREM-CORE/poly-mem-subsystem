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
  logic                fault_o;
  logic [2:0]          fault_code_o;

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
    .wr_ready_o(wr_ready_o),
    .fault_o(fault_o),
    .fault_code_o(fault_code_o)
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
    // Same-bank read + write to different addresses is allowed.
    // Port A services the read and Port B services the write, so
    // only same-address mixed-port hazards are forbidden.
    // idx 0 and idx 10 both map to bank 0 under the CMI function.
    // ----------------------------------------------------------
    rd_poly_id_i    = POLY_W'(2);
    rd_v_i          = 1'b1;
    rd_idx_i[0]     = COEFF_W'(0);
    rd_lane_valid_i = 4'b0001;

    wr_poly_id_i    = POLY_W'(2);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b0001;
    wr_idx_i[0]     = COEFF_W'(10);
    wr_data_i[0]    = 16'h10AA;
    #1;
    if (!rd_ready_o || !wr_ready_o)
      $fatal(1, "Expected same-bank different-address read/write overlap to succeed");
    if (fault_o)
      $fatal(1, "Did not expect a fault for same-bank different-address read/write");
    tick();
    if (!rd_valid_o || rd_data_o[0] !== 16'h1000)
      $fatal(1, "Expected original read data during same-bank different-address overlap");
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

    // ----------------------------------------------------------
    // Same-address read + write is explicitly forbidden.
    // ----------------------------------------------------------
    rd_poly_id_i    = POLY_W'(2);
    rd_v_i          = 1'b1;
    rd_idx_i[0]     = COEFF_W'(0);
    rd_lane_valid_i = 4'b0001;
    wr_poly_id_i    = POLY_W'(2);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b0001;
    wr_idx_i[0]     = COEFF_W'(0);
    wr_data_i[0]    = 16'hDEAD;
    #1;
    if (rd_ready_o || wr_ready_o)
      $fatal(1, "Expected same-address read/write to be rejected");
    if (!fault_o || fault_code_o !== 3'b001)
      $fatal(1, "Expected same-address read/write fault code");
    clear_all();

    // ----------------------------------------------------------
    // Same-address write + write is explicitly forbidden.
    // ----------------------------------------------------------
    wr_poly_id_i    = POLY_W'(2);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b0011;
    wr_idx_i[0]     = COEFF_W'(20);
    wr_idx_i[1]     = COEFF_W'(20);
    wr_data_i[0]    = 16'hAAAA;
    wr_data_i[1]    = 16'hBBBB;
    #1;
    if (wr_ready_o)
      $fatal(1, "Expected same-address write/write to be rejected");
    if (!fault_o || fault_code_o !== 3'b010)
      $fatal(1, "Expected same-address write/write fault code");
    clear_all();

    // ----------------------------------------------------------
    // Same-bank but different-address lane conflict reports generic fault.
    // ----------------------------------------------------------
    wr_poly_id_i    = POLY_W'(2);
    wr_v_i          = 1'b1;
    wr_en_i         = 4'b0011;
    wr_idx_i[0]     = COEFF_W'(1);
    wr_idx_i[1]     = COEFF_W'(4);
    wr_data_i[0]    = 16'h1111;
    wr_data_i[1]    = 16'h2222;
    #1;
    if (wr_ready_o)
      $fatal(1, "Expected same-bank different-address conflict");
    if (!fault_o || fault_code_o !== 3'b011)
      $fatal(1, "Expected generic request-conflict fault code");
    clear_all();

    $display("TB PASS");
    $finish;
  end

endmodule
