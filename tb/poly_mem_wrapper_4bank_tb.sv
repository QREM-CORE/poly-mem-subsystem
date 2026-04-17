`timescale 1ns/1ps

module poly_mem_wrapper_4bank_tb;

  parameter int N = 256;
  parameter int W = 16;
  parameter int NUM_POLYS = 4;

  logic clk;
  logic rst;

  logic [$clog2(NUM_POLYS)-1:0] poly_id_i;
  logic                         v_i;
  logic                         rd_en_i;
  logic                         ready_o;

  logic [3:0][$clog2(N)-1:0]    rd_idx_i;
  logic [3:0]                   rd_lane_valid_i;

  logic                         rd_valid_o;
  logic [$clog2(NUM_POLYS)-1:0] rd_poly_id_o;
  logic [3:0][$clog2(N)-1:0]    rd_idx_o;
  logic [3:0]                   rd_lane_valid_o;
  logic [3:0][W-1:0]            rd_data_o;

  logic [3:0]                   wr_en_i;
  logic [3:0][$clog2(N)-1:0]    wr_idx_i;
  logic [3:0][W-1:0]            wr_data_i;

  // DUT
  poly_mem_wrapper_4bank #(
    .N(N),
    .W(W),
    .NUM_POLYS(NUM_POLYS)
  ) DUT (
    .clk                 (clk),
    .rst                 (rst),
    .poly_id_i           (poly_id_i),
    .v_i                 (v_i),
    .rd_en_i             (rd_en_i),
    .ready_o             (ready_o),
    .rd_idx_i            (rd_idx_i),
    .rd_lane_valid_i     (rd_lane_valid_i),
    .rd_valid_o          (rd_valid_o),
    .rd_poly_id_o        (rd_poly_id_o),
    .rd_idx_o            (rd_idx_o),
    .rd_lane_valid_o     (rd_lane_valid_o),
    .rd_data_o           (rd_data_o),
    .wr_en_i             (wr_en_i),
    .wr_idx_i            (wr_idx_i),
    .wr_data_i           (wr_data_i)
  );

  // Clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    // Reset / init
    rst             = 1'b0;
    poly_id_i       = '0;
    v_i             = 1'b0;
    rd_en_i         = 1'b0;
    rd_idx_i        = '0;
    rd_lane_valid_i = '0;
    wr_en_i         = '0;
    wr_idx_i        = '0;
    wr_data_i       = '0;

    #20;
    rst = 1'b1;

    // --------------------------------------------------
    // WRITE 4 values to 4 indices that should map cleanly
    // --------------------------------------------------
    @(posedge clk);
    v_i       <= 1'b1;
    rd_en_i   <= 1'b0;
    poly_id_i <= 2'd0;

    wr_en_i[0]   <= 1'b1;
    wr_en_i[1]   <= 1'b1;
    wr_en_i[2]   <= 1'b1;
    wr_en_i[3]   <= 1'b1;

    wr_idx_i[0]  <= 8'd2;
    wr_idx_i[1]  <= 8'd66;
    wr_idx_i[2]  <= 8'd130;
    wr_idx_i[3]  <= 8'd194;

    wr_data_i[0] <= 16'hA000;
    wr_data_i[1] <= 16'hA001;
    wr_data_i[2] <= 16'hA002;
    wr_data_i[3] <= 16'hA003;

    @(posedge clk);
    wr_en_i <= 4'b0000;

    @(posedge clk);
    v_i       <= 1'b1;
    rd_en_i   <= 1'b0;
    poly_id_i <= 2'd0;

    wr_en_i[0] <= 1'b1;
    wr_en_i[1]  <= 1'b1;
    wr_en_i[2]   <= 1'b1;
    wr_en_i[3]   <= 1'b1;

    wr_idx_i[0]<= 8'd1;
    wr_idx_i[1] <= 8'd65;
    wr_idx_i[2]  <= 8'd129;
    wr_idx_i[3]  <= 8'd193;

    wr_data_i[0]= 16'hA004;
    wr_data_i[1]<= 16'hA005;
    wr_data_i[2] <= 16'hA006;
    wr_data_i[3] <= 16'hA007;

    @(posedge clk);
    wr_en_i <= 4'b0000;

    // --------------------------------------------------
    // READ BACK same 4 indices
    // --------------------------------------------------
    @(posedge clk);
    rd_en_i         <= 1'b1;
    rd_lane_valid_i <= 4'b1111;
    rd_idx_i[0]     <= 8'd1;
    rd_idx_i[1]     <= 8'd65;
    rd_idx_i[2]     <= 8'd129;
    rd_idx_i[3]     <= 8'd193;

    @(posedge clk); // request accepted into wrapper
    @(posedge clk); // RAM data aligned to output response

    rd_en_i         <= 1'b1;
    rd_lane_valid_i <= 4'b1111;
    rd_idx_i[0]     <= 8'd2;
    rd_idx_i[1]     <= 8'd66;
    rd_idx_i[2]     <= 8'd130;
    rd_idx_i[3]     <= 8'd194;

    @(posedge clk); // request accepted into wrapper
    @(posedge clk); // RAM data aligned to output response

    #20;
    $finish;
  end

endmodule
