`timescale 1ns/1ps

module tb_poly_mem_wrapper_4bank;

  localparam int N = 256;
  localparam int W = 16;
  localparam int NUM_POLYS = 4;
  localparam int BANK_ROWS = N/4;
  localparam int BANK_DEPTH = BANK_ROWS * NUM_POLYS;

  logic clk, rst_n;

  logic [$clog2(NUM_POLYS)-1:0] poly_id;
  logic v;
  logic rd_en;
  logic ready;

  logic [3:0][$clog2(N)-1:0] rd_idx;
  logic [3:0][W-1:0]         rd_data;

  logic [3:0]                wr_en;
  logic [3:0][$clog2(N)-1:0] wr_idx;
  logic [3:0][W-1:0]         wr_data;

  logic [W-1:0] golden [0:3][0:BANK_DEPTH-1];
  logic [3:0][W-1:0] exp_next;

  integer bi, bj;
  integer i, base, l;
  integer idx0, idx1, idx2, idx3;

  poly_mem_wrapper_4bank #(
    .N(N),
    .W(W),
    .NUM_POLYS(NUM_POLYS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .poly_id_i(poly_id),
    .v_i(v),
    .rd_en_i(rd_en),
    .ready_o(ready),
    .rd_idx_i(rd_idx),
    .rd_data_o(rd_data),
    .wr_en_i(wr_en),
    .wr_idx_i(wr_idx),
    .wr_data_i(wr_data)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  function automatic [1:0] cmi_bank_idx;
    input [7:0] order;
    reg [3:0] sum;
    begin
      sum = order[1:0] + order[3:2] + order[5:4] + order[7:6];
      cmi_bank_idx = sum[1:0];
    end
  endfunction

  function automatic [7:0] cmi_bank_addr;
    input [$clog2(NUM_POLYS)-1:0] pid;
    input [7:0] order;
    reg [5:0] row;
    begin
      row = order >> 2;
      cmi_bank_addr = pid * BANK_ROWS + row;
    end
  endfunction

  initial begin
    for (bi = 0; bi < 4; bi = bi + 1) begin
      for (bj = 0; bj < BANK_DEPTH; bj = bj + 1) begin
        golden[bi][bj] = '0;
      end
    end

    rst_n    = 0;
    v        = 0;
    rd_en    = 0;
    poly_id  = 0;
    wr_en    = 4'b0000;
    wr_idx[0] = 0; wr_idx[1] = 0; wr_idx[2] = 0; wr_idx[3] = 0;
    wr_data[0] = 0; wr_data[1] = 0; wr_data[2] = 0; wr_data[3] = 0;
    rd_idx[0] = 0; rd_idx[1] = 0; rd_idx[2] = 0; rd_idx[3] = 0;
    exp_next[0] = 0; exp_next[1] = 0; exp_next[2] = 0; exp_next[3] = 0;

    repeat (3) tick();
    rst_n = 1;
    tick();

    // Test 1: single-lane writes for all coefficients of poly 0
    poly_id = 0;
    rd_en   = 0;

    for (i = 0; i < N; i = i + 1) begin
      v         = 1;
      wr_en     = 4'b0001;
      wr_idx[0] = i[7:0];
      wr_idx[1] = 0;
      wr_idx[2] = 0;
      wr_idx[3] = 0;

      wr_data[0] = i[W-1:0];
      wr_data[1] = 0;
      wr_data[2] = 0;
      wr_data[3] = 0;

      rd_idx[0] = 0;
      rd_idx[1] = 0;
      rd_idx[2] = 0;
      rd_idx[3] = 0;

      tick();
      if (!ready)
        $fatal(1, "Unexpected stall during single-lane write at coeff=%0d", i);

      golden[cmi_bank_idx(i[7:0])][cmi_bank_addr(poly_id, i[7:0])] = i[W-1:0];
    end

    v     = 0;
    wr_en = 4'b0000;
    tick();

    // Test 2: non-conflicting reads
    rd_en = 1;
    for (base = 0; base < 16; base = base + 1) begin
      idx0 = base;
      idx1 = base + 64;
      idx2 = base + 128;
      idx3 = base + 192;

      v     = 1;
      wr_en = 4'b0000;

      rd_idx[0] = idx0[7:0];
      rd_idx[1] = idx1[7:0];
      rd_idx[2] = idx2[7:0];
      rd_idx[3] = idx3[7:0];

      exp_next[0] = golden[cmi_bank_idx(idx0[7:0])][cmi_bank_addr(poly_id, idx0[7:0])];
      exp_next[1] = golden[cmi_bank_idx(idx1[7:0])][cmi_bank_addr(poly_id, idx1[7:0])];
      exp_next[2] = golden[cmi_bank_idx(idx2[7:0])][cmi_bank_addr(poly_id, idx2[7:0])];
      exp_next[3] = golden[cmi_bank_idx(idx3[7:0])][cmi_bank_addr(poly_id, idx3[7:0])];

      tick();
      if (!ready)
        $fatal(1, "Unexpected stall during non-conflicting read set base=%0d", base);

      tick();
      for (l = 0; l < 4; l = l + 1) begin
        if (rd_data[l] !== exp_next[l]) begin
          $fatal(1, "Read mismatch lane=%0d base=%0d got=%0h exp=%0h",
                 l, base, rd_data[l], exp_next[l]);
        end
      end
    end

    v = 0;
    tick();

    // Test 3: intentional conflict
    v     = 1;
    rd_en = 1;
    wr_en = 4'b0000;

    rd_idx[0] = 0;
    rd_idx[1] = 4;
    rd_idx[2] = 1;
    rd_idx[3] = 2;

    tick();
    if (ready)
      $fatal(1, "Expected ready=0 on conflicting read request but got ready=1");

    v = 0;
    tick();

    // Test 4: poly_id offset
    poly_id    = 1;
    rd_en      = 0;
    v          = 1;
    wr_en      = 4'b0001;
    wr_idx[0]  = 10;
    wr_idx[1]  = 0;
    wr_idx[2]  = 0;
    wr_idx[3]  = 0;
    wr_data[0] = 16'h55AA;
    wr_data[1] = 0;
    wr_data[2] = 0;
    wr_data[3] = 0;

    tick();
    if (!ready)
      $fatal(1, "Unexpected stall during poly_id=1 write");

    golden[cmi_bank_idx(8'd10)][cmi_bank_addr(poly_id, 8'd10)] = 16'h55AA;

    v     = 0;
    wr_en = 4'b0000;
    tick();

    rd_en    = 1;
    v        = 1;
    rd_idx[0] = 10;
    rd_idx[1] = 74;
    rd_idx[2] = 138;
    rd_idx[3] = 202;

    tick();
    if (!ready)
      $fatal(1, "Unexpected stall during poly_id=1 read");

    tick();
    if (rd_data[0] !== 16'h55AA)
      $fatal(1, "poly_id=1 readback mismatch got=%0h exp=55AA", rd_data[0]);

    v = 0;
    tick();

    $display("TB PASS");
    $finish;
  end

endmodule