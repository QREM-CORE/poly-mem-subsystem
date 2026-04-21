`timescale 1ns/1ps

module poly_mem_wrapper_4bank_tb;

  localparam int N         = 256;
  localparam int W         = 16;
  localparam int NUM_POLYS = 8;
  localparam int POLY_W    = $clog2(NUM_POLYS);
  localparam int COEFF_W   = $clog2(N);

  logic clk, rst;

  logic [POLY_W-1:0]       p0_poly_id_i, p1_poly_id_i;
  logic                    p0_v_i, p1_v_i;
  logic [3:0]              p0_wr_en_i, p1_wr_en_i;
  logic [3:0][COEFF_W-1:0] p0_idx_i, p1_idx_i;
  logic [3:0]              p0_lane_valid_i, p1_lane_valid_i;
  logic [3:0][W-1:0]       p0_data_i, p1_data_i;
  logic                    p0_ready_o, p1_ready_o;
  logic                    p0_rd_valid_o, p1_rd_valid_o;
  logic [POLY_W-1:0]       p0_rd_poly_id_o, p1_rd_poly_id_o;
  logic [3:0][COEFF_W-1:0] p0_rd_idx_o, p1_rd_idx_o;
  logic [3:0]              p0_rd_lane_valid_o, p1_rd_lane_valid_o;
  logic [3:0][W-1:0]       p0_rd_data_o, p1_rd_data_o;
  logic                    fault_o;
  logic [2:0]              fault_code_o;

  poly_mem_wrapper_4bank #(
    .N(N),
    .W(W),
    .NUM_POLYS(NUM_POLYS)
  ) dut (
    .clk(clk),
    .rst(rst),
    .p0_poly_id_i(p0_poly_id_i),
    .p0_v_i(p0_v_i),
    .p0_wr_en_i(p0_wr_en_i),
    .p0_idx_i(p0_idx_i),
    .p0_lane_valid_i(p0_lane_valid_i),
    .p0_data_i(p0_data_i),
    .p0_ready_o(p0_ready_o),
    .p0_rd_valid_o(p0_rd_valid_o),
    .p0_rd_poly_id_o(p0_rd_poly_id_o),
    .p0_rd_idx_o(p0_rd_idx_o),
    .p0_rd_lane_valid_o(p0_rd_lane_valid_o),
    .p0_rd_data_o(p0_rd_data_o),
    .p1_poly_id_i(p1_poly_id_i),
    .p1_v_i(p1_v_i),
    .p1_wr_en_i(p1_wr_en_i),
    .p1_idx_i(p1_idx_i),
    .p1_lane_valid_i(p1_lane_valid_i),
    .p1_data_i(p1_data_i),
    .p1_ready_o(p1_ready_o),
    .p1_rd_valid_o(p1_rd_valid_o),
    .p1_rd_poly_id_o(p1_rd_poly_id_o),
    .p1_rd_idx_o(p1_rd_idx_o),
    .p1_rd_lane_valid_o(p1_rd_lane_valid_o),
    .p1_rd_data_o(p1_rd_data_o),
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

  task automatic clear_ports;
    begin
      p0_poly_id_i     = '0;
      p0_v_i           = 1'b0;
      p0_wr_en_i       = '0;
      p0_idx_i         = '0;
      p0_lane_valid_i  = '0;
      p0_data_i        = '0;

      p1_poly_id_i     = '0;
      p1_v_i           = 1'b0;
      p1_wr_en_i       = '0;
      p1_idx_i         = '0;
      p1_lane_valid_i  = '0;
      p1_data_i        = '0;
    end
  endtask

  task automatic drive_p0_write(
    input int poly_id,
    input logic [3:0] en_mask,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      p0_poly_id_i = POLY_W'(poly_id);
      p0_v_i       = 1'b1;
      p0_wr_en_i   = en_mask;
      p0_idx_i[0]  = COEFF_W'(idx0);
      p0_idx_i[1]  = COEFF_W'(idx1);
      p0_idx_i[2]  = COEFF_W'(idx2);
      p0_idx_i[3]  = COEFF_W'(idx3);
      p0_data_i[0] = d0;
      p0_data_i[1] = d1;
      p0_data_i[2] = d2;
      p0_data_i[3] = d3;
    end
  endtask

  task automatic drive_p1_write(
    input int poly_id,
    input logic [3:0] en_mask,
    input int idx0, input int idx1, input int idx2, input int idx3,
    input logic [W-1:0] d0, input logic [W-1:0] d1,
    input logic [W-1:0] d2, input logic [W-1:0] d3
  );
    begin
      p1_poly_id_i = POLY_W'(poly_id);
      p1_v_i       = 1'b1;
      p1_wr_en_i   = en_mask;
      p1_idx_i[0]  = COEFF_W'(idx0);
      p1_idx_i[1]  = COEFF_W'(idx1);
      p1_idx_i[2]  = COEFF_W'(idx2);
      p1_idx_i[3]  = COEFF_W'(idx3);
      p1_data_i[0] = d0;
      p1_data_i[1] = d1;
      p1_data_i[2] = d2;
      p1_data_i[3] = d3;
    end
  endtask

  task automatic drive_p0_read(
    input int poly_id,
    input logic [3:0] lane_mask,
    input int idx0, input int idx1, input int idx2, input int idx3
  );
    begin
      p0_poly_id_i     = POLY_W'(poly_id);
      p0_v_i           = 1'b1;
      p0_wr_en_i       = '0;
      p0_idx_i[0]      = COEFF_W'(idx0);
      p0_idx_i[1]      = COEFF_W'(idx1);
      p0_idx_i[2]      = COEFF_W'(idx2);
      p0_idx_i[3]      = COEFF_W'(idx3);
      p0_lane_valid_i  = lane_mask;
    end
  endtask

  task automatic drive_p1_read(
    input int poly_id,
    input logic [3:0] lane_mask,
    input int idx0, input int idx1, input int idx2, input int idx3
  );
    begin
      p1_poly_id_i     = POLY_W'(poly_id);
      p1_v_i           = 1'b1;
      p1_wr_en_i       = '0;
      p1_idx_i[0]      = COEFF_W'(idx0);
      p1_idx_i[1]      = COEFF_W'(idx1);
      p1_idx_i[2]      = COEFF_W'(idx2);
      p1_idx_i[3]      = COEFF_W'(idx3);
      p1_lane_valid_i  = lane_mask;
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_ports();
    repeat (2) tick();
    rst = 1'b0;
    tick();

    // Prime two source polynomials for later dual-read tests.
    drive_p0_write(2, 4'b1111, 0, 1, 2, 3, 16'h1000, 16'h1001, 16'h1002, 16'h1003);
    if (!p0_ready_o || fault_o)
      $fatal(1, "Expected legal prime write on port 0");
    tick();
    clear_ports();

    drive_p0_write(3, 4'b1111, 4, 5, 6, 7, 16'h2000, 16'h2001, 16'h2002, 16'h2003);
    if (!p0_ready_o || fault_o)
      $fatal(1, "Expected second legal prime write on port 0");
    tick();
    clear_ports();

    // ------------------------------------------------------------------
    // 1) Legal dual-read: both generic ports may issue reads together.
    // ------------------------------------------------------------------
    drive_p0_read(2, 4'b1111, 0, 1, 2, 3);
    drive_p1_read(3, 4'b1111, 4, 5, 6, 7);
    #1;
    if (!p0_ready_o || !p1_ready_o || fault_o)
      $fatal(1, "Expected legal dual-read scheduling");
    tick();

    if (!p0_rd_valid_o || !p1_rd_valid_o)
      $fatal(1, "Expected both read responses after legal dual-read");
    if (p0_rd_poly_id_o !== POLY_W'(2) || p1_rd_poly_id_o !== POLY_W'(3))
      $fatal(1, "Dual-read response metadata mismatch");
    if (p0_rd_data_o[0] !== 16'h1000 || p0_rd_data_o[1] !== 16'h1001 ||
        p0_rd_data_o[2] !== 16'h1002 || p0_rd_data_o[3] !== 16'h1003)
      $fatal(1, "Port 0 dual-read data mismatch");
    if (p1_rd_data_o[0] !== 16'h2000 || p1_rd_data_o[1] !== 16'h2001 ||
        p1_rd_data_o[2] !== 16'h2002 || p1_rd_data_o[3] !== 16'h2003)
      $fatal(1, "Port 1 dual-read data mismatch");
    clear_ports();

    // ------------------------------------------------------------------
    // 2) Legal dual-write: both generic ports may issue writes together.
    // ------------------------------------------------------------------
    drive_p0_write(4, 4'b1111, 8, 9, 10, 11, 16'h4100, 16'h4101, 16'h4102, 16'h4103);
    drive_p1_write(5, 4'b1111, 12, 13, 14, 15, 16'h5200, 16'h5201, 16'h5202, 16'h5203);
    #1;
    if (!p0_ready_o || !p1_ready_o || fault_o)
      $fatal(1, "Expected legal dual-write scheduling");
    tick();
    clear_ports();

    drive_p0_read(4, 4'b1111, 8, 9, 10, 11);
    drive_p1_read(5, 4'b1111, 12, 13, 14, 15);
    #1;
    if (!p0_ready_o || !p1_ready_o || fault_o)
      $fatal(1, "Expected readback after legal dual-write");
    tick();
    if (p0_rd_data_o[0] !== 16'h4100 || p0_rd_data_o[1] !== 16'h4101 ||
        p0_rd_data_o[2] !== 16'h4102 || p0_rd_data_o[3] !== 16'h4103)
      $fatal(1, "Dual-write readback mismatch on port 0");
    if (p1_rd_data_o[0] !== 16'h5200 || p1_rd_data_o[1] !== 16'h5201 ||
        p1_rd_data_o[2] !== 16'h5202 || p1_rd_data_o[3] !== 16'h5203)
      $fatal(1, "Dual-write readback mismatch on port 1");
    clear_ports();

    // ------------------------------------------------------------------
    // 3) Legal read/write overlap: same bank but different addresses.
    // ------------------------------------------------------------------
    drive_p0_read(4, 4'b0001, 8, 0, 0, 0);
    drive_p1_write(4, 4'b0001, 16, 0, 0, 0, 16'h44AA, '0, '0, '0);
    #1;
    if (!p0_ready_o || !p1_ready_o || fault_o)
      $fatal(1, "Expected legal same-bank different-address read/write overlap");
    tick();
    if (!p0_rd_valid_o || p0_rd_data_o[0] !== 16'h4100)
      $fatal(1, "Read/write overlap should preserve the original read data");
    clear_ports();

    drive_p0_read(4, 4'b0001, 16, 0, 0, 0);
    #1;
    if (!p0_ready_o || fault_o)
      $fatal(1, "Expected readback of overlapped write");
    tick();
    if (!p0_rd_valid_o || p0_rd_data_o[0] !== 16'h44AA)
      $fatal(1, "Expected write data after legal read/write overlap");
    clear_ports();

    // ------------------------------------------------------------------
    // 4) Illegal same-address read/write is rejected with fault code 001.
    // ------------------------------------------------------------------
    drive_p0_read(4, 4'b0001, 8, 0, 0, 0);
    drive_p1_write(4, 4'b0001, 8, 0, 0, 0, 16'hDEAD, '0, '0, '0);
    #1;
    if (p0_ready_o || p1_ready_o)
      $fatal(1, "Expected same-address read/write to be rejected");
    if (!fault_o || fault_code_o !== 3'b001)
      $fatal(1, "Expected same-address read/write fault code");
    clear_ports();

    // ------------------------------------------------------------------
    // 5) Illegal same-address write/write is rejected with fault code 010.
    // ------------------------------------------------------------------
    drive_p0_write(4, 4'b0001, 20, 0, 0, 0, 16'hAAAA, '0, '0, '0);
    drive_p1_write(4, 4'b0001, 20, 0, 0, 0, 16'hBBBB, '0, '0, '0);
    #1;
    if (p0_ready_o || p1_ready_o)
      $fatal(1, "Expected same-address write/write to be rejected");
    if (!fault_o || fault_code_o !== 3'b010)
      $fatal(1, "Expected same-address write/write fault code");
    clear_ports();

    // ------------------------------------------------------------------
    // 6) Same-request lane conflicts remain illegal with generic code 011.
    //    idx 1 and idx 4 both map to bank 1 under the CMI function.
    // ------------------------------------------------------------------
    drive_p0_write(4, 4'b0011, 1, 4, 0, 0, 16'h1111, 16'h2222, '0, '0);
    #1;
    if (p0_ready_o)
      $fatal(1, "Expected same-request lane conflict to be rejected");
    if (!fault_o || fault_code_o !== 3'b011)
      $fatal(1, "Expected generic request-conflict fault code");
    clear_ports();

    $display("TB PASS");
    $finish;
  end

endmodule
