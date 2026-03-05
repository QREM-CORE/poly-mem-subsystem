// tb/tb_poly_mem_wrapper_4bank.sv
`timescale 1ns/1ps

module tb_poly_mem_wrapper_4bank;

  localparam int N = 256;
  localparam int W = 16;
  localparam int NUM_POLYS = 4;

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

  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  logic [3:0][W-1:0] exp_next;

  initial begin
    clk = 0;
    rst_n = 0;
    v = 0;
    rd_en = 0;
    poly_id = '0;
    rd_idx = '0;
    wr_en  = '0;
    wr_idx = '0;
    wr_data = '0;
    exp_next = '0;

    repeat (3) tick();
    rst_n = 1;
    tick();

    // --------------------------
    // Write poly_id=0 with pattern: coeff[i] = i
    // --------------------------
    poly_id = 0;
    rd_en   = 0;  // IMPORTANT: no reads during write phase

    for (int i = 0; i < N; i += 4) begin
      v = 1;
      wr_en = 4'b1111;

      for (int l = 0; l < 4; l++) begin
        wr_idx[l]  = i + l;
        wr_data[l] = (i + l);
        rd_idx[l]  = '0;
      end

      tick();
      if (!ready) $fatal(1, "Unexpected stall during non-conflicting write at i=%0d", i);
    end
    v = 0; wr_en = 0;
    tick();

    // --------------------------
    // Read back and verify (sync read: check next cycle)
    // --------------------------
    rd_en = 1;

    for (int i = 0; i < N; i += 4) begin
      v = 1;
      wr_en = 0;

      for (int l = 0; l < 4; l++) begin
        rd_idx[l] = i + l;
        exp_next[l] = (i + l);
      end

      tick();
      if (!ready) $fatal(1, "Unexpected stall during non-conflicting read at i=%0d", i);

      tick();
      for (int l = 0; l < 4; l++) begin
        if (rd_data[l] !== exp_next[l]) begin
          $fatal(1, "Read mismatch lane=%0d idx=%0d got=%0h exp=%0h",
                 l, i+l, rd_data[l], exp_next[l]);
        end
      end
    end
    v = 0;
    tick();

    // --------------------------
    // Conflict test: two lanes hit same bank (0 and 4 both bank0)
    // --------------------------
    v = 1;
    rd_en = 1;
    wr_en = 0;
    rd_idx[0] = 0;
    rd_idx[1] = 4;   // same bank as 0
    rd_idx[2] = 2;
    rd_idx[3] = 3;
    tick();

    if (ready) $fatal(1, "Expected ready=0 on bank conflict but got ready=1");

    v = 0;
    tick();

    $display("TB PASS");
    $finish;
  end

endmodule