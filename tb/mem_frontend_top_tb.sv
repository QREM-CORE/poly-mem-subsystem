`timescale 1ns/1ps

module mem_frontend_top_tb;

  localparam int NUM_BANKS = 4;
  localparam int NUM_POLYS = 32;
  localparam int NCOEFF    = 256;
  localparam int N         = 2048;
  localparam int W         = 16;
  localparam int ADDR_W    = $clog2(N);
  localparam int POLY_W    = $clog2(NUM_POLYS);
  localparam int COEFF_W   = $clog2(NCOEFF);

  logic clk;
  logic rst_n;

  logic wipe_i;
  logic wipe_done_o;

  // PAU
  logic               pau_req;
  logic [POLY_W-1:0]  pau_poly_id;
  logic [COEFF_W-1:0] pau_coeff_idx;
  logic               pau_we;
  logic [W-1:0]       pau_wdata;
  logic [W-1:0]       pau_rdata;
  logic               pau_stall;

  // HSU
  logic               hsu_req;
  logic [POLY_W-1:0]  hsu_poly_id;
  logic [COEFF_W-1:0] hsu_coeff_idx;
  logic               hsu_we;
  logic [W-1:0]       hsu_wdata;
  logic [W-1:0]       hsu_rdata;
  logic               hsu_stall;

  // Transcoder
  logic               tr_req;
  logic [POLY_W-1:0]  tr_poly_id;
  logic [COEFF_W-1:0] tr_coeff_idx;
  logic               tr_we;
  logic [W-1:0]       tr_wdata;
  logic [W-1:0]       tr_rdata;
  logic               tr_stall;

  mem_frontend_top #(
    .NUM_BANKS(NUM_BANKS),
    .NUM_POLYS(NUM_POLYS),
    .NCOEFF(NCOEFF),
    .N(N),
    .W(W),
    .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .wipe_i(wipe_i),
    .wipe_done_o(wipe_done_o),

    .pau_req(pau_req),
    .pau_poly_id(pau_poly_id),
    .pau_coeff_idx(pau_coeff_idx),
    .pau_we(pau_we),
    .pau_wdata(pau_wdata),
    .pau_rdata(pau_rdata),
    .pau_stall(pau_stall),

    .hsu_req(hsu_req),
    .hsu_poly_id(hsu_poly_id),
    .hsu_coeff_idx(hsu_coeff_idx),
    .hsu_we(hsu_we),
    .hsu_wdata(hsu_wdata),
    .hsu_rdata(hsu_rdata),
    .hsu_stall(hsu_stall),

    .tr_req(tr_req),
    .tr_poly_id(tr_poly_id),
    .tr_coeff_idx(tr_coeff_idx),
    .tr_we(tr_we),
    .tr_wdata(tr_wdata),
    .tr_rdata(tr_rdata),
    .tr_stall(tr_stall)
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
      wipe_i = 1'b0;

      pau_req       = 1'b0;
      pau_poly_id   = '0;
      pau_coeff_idx = '0;
      pau_we        = 1'b0;
      pau_wdata     = '0;

      hsu_req       = 1'b0;
      hsu_poly_id   = '0;
      hsu_coeff_idx = '0;
      hsu_we        = 1'b0;
      hsu_wdata     = '0;

      tr_req        = 1'b0;
      tr_poly_id    = '0;
      tr_coeff_idx  = '0;
      tr_we         = 1'b0;
      tr_wdata      = '0;
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

  // ------------------------------------------------------------
  // PAU write/read through shared NTT-side path
  // ------------------------------------------------------------
  task automatic pau_write(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] data
  );
    begin
      @(posedge clk);
      pau_req       <= 1'b1;
      pau_poly_id   <= POLY_W'(poly_id);
      pau_coeff_idx <= COEFF_W'(coeff_idx);
      pau_we        <= 1'b1;
      pau_wdata     <= data;

      @(posedge clk);
      pau_req   <= 1'b0;
      pau_we    <= 1'b0;
      pau_wdata <= '0;
    end
  endtask

  task automatic pau_read_check(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] exp_data
  );
    begin
      @(posedge clk);
      pau_req       <= 1'b1;
      pau_poly_id   <= POLY_W'(poly_id);
      pau_coeff_idx <= COEFF_W'(coeff_idx);
      pau_we        <= 1'b0;

      @(posedge clk);
      #1;
      if (pau_rdata !== exp_data) begin
        $fatal(1, "PAU read mismatch: poly=%0d coeff=%0d got=%0h exp=%0h",
               poly_id, coeff_idx, pau_rdata, exp_data);
      end

      @(posedge clk);
      pau_req <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------
  // HSU write/read through shared NTT-side path
  // ------------------------------------------------------------
  task automatic hsu_write(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] data
  );
    begin
      @(posedge clk);
      hsu_req       <= 1'b1;
      hsu_poly_id   <= POLY_W'(poly_id);
      hsu_coeff_idx <= COEFF_W'(coeff_idx);
      hsu_we        <= 1'b1;
      hsu_wdata     <= data;

      @(posedge clk);
      hsu_req   <= 1'b0;
      hsu_we    <= 1'b0;
      hsu_wdata <= '0;
    end
  endtask

  task automatic hsu_read_check(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] exp_data
  );
    begin
      @(posedge clk);
      hsu_req       <= 1'b1;
      hsu_poly_id   <= POLY_W'(poly_id);
      hsu_coeff_idx <= COEFF_W'(coeff_idx);
      hsu_we        <= 1'b0;

      @(posedge clk);
      #1;
      if (hsu_rdata !== exp_data) begin
        $fatal(1, "HSU read mismatch: poly=%0d coeff=%0d got=%0h exp=%0h",
               poly_id, coeff_idx, hsu_rdata, exp_data);
      end

      @(posedge clk);
      hsu_req <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------
  // Transcoder write/read through PU path
  // ------------------------------------------------------------
  task automatic tr_write(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] data
  );
    begin
      @(posedge clk);
      tr_req       <= 1'b1;
      tr_poly_id   <= POLY_W'(poly_id);
      tr_coeff_idx <= COEFF_W'(coeff_idx);
      tr_we        <= 1'b1;
      tr_wdata     <= data;

      @(posedge clk);
      tr_req   <= 1'b0;
      tr_we    <= 1'b0;
      tr_wdata <= '0;
    end
  endtask

  task automatic tr_read_check(
    input int poly_id,
    input int coeff_idx,
    input logic [W-1:0] exp_data
  );
    begin
      @(posedge clk);
      tr_req       <= 1'b1;
      tr_poly_id   <= POLY_W'(poly_id);
      tr_coeff_idx <= COEFF_W'(coeff_idx);
      tr_we        <= 1'b0;

      @(posedge clk);
      #1;
      if (tr_rdata !== exp_data) begin
        $fatal(1, "TR read mismatch: poly=%0d coeff=%0d got=%0h exp=%0h",
               poly_id, coeff_idx, tr_rdata, exp_data);
      end

      @(posedge clk);
      tr_req <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------
  // Arbitration check: PAU beats HSU on shared NTT-side path
  // ------------------------------------------------------------
  task automatic arbitration_priority_check;
    begin
      @(posedge clk);
      pau_req       <= 1'b1;
      pau_poly_id   <= 5;
      pau_coeff_idx <= 8;
      pau_we        <= 1'b1;
      pau_wdata     <= 16'h1111;

      hsu_req       <= 1'b1;
      hsu_poly_id   <= 6;
      hsu_coeff_idx <= 12;
      hsu_we        <= 1'b1;
      hsu_wdata     <= 16'h2222;

      #1;
      if (pau_stall !== 1'b0) $fatal(1, "PAU should win arbitration");
      if (hsu_stall !== 1'b1) $fatal(1, "HSU should stall under PAU");

      @(posedge clk);
      clear_all();
    end
  endtask

  // ------------------------------------------------------------
  // PU path should be independent of NTT-side arbitration
  // ------------------------------------------------------------
  task automatic transcoder_parallel_check;
    begin
      @(posedge clk);
      pau_req       <= 1'b1;
      pau_poly_id   <= 2;
      pau_coeff_idx <= 20;
      pau_we        <= 1'b1;
      pau_wdata     <= 16'hAAAA;

      tr_req        <= 1'b1;
      tr_poly_id    <= 9;
      tr_coeff_idx  <= 14;
      tr_we         <= 1'b1;
      tr_wdata      <= 16'hBBBB;

      #1;
      if (pau_stall !== 1'b0) $fatal(1, "PAU should not stall here");
      if (tr_stall  !== 1'b0) $fatal(1, "TR should not stall here");

      @(posedge clk);
      clear_all();
    end
  endtask

  // ------------------------------------------------------------
  // Wipe through frontend
  // ------------------------------------------------------------
  task automatic run_wipe;
    begin
      @(posedge clk);
      wipe_i <= 1'b1;

      @(posedge clk);
      wipe_i <= 1'b0;

      wait (wipe_done_o == 1'b1);
      @(posedge clk);
    end
  endtask

  initial begin
    reset_all();

    // 1) PAU path
    pau_write(3, 9, 16'hA5A5);
    pau_read_check(3, 9, 16'hA5A5);

    // 2) HSU path
    hsu_write(10, 17, 16'h5A5A);
    hsu_read_check(10, 17, 16'h5A5A);

    // 3) TR path
    tr_write(7, 21, 16'h1234);
    tr_read_check(7, 21, 16'h1234);

    // 4) Shared-path arbitration
    arbitration_priority_check();

    // 5) Parallel PAU + Transcoder
    transcoder_parallel_check();

    // 6) Wipe and verify
    run_wipe();
    pau_read_check(3, 9, 16'h0000);
    hsu_read_check(10, 17, 16'h0000);
    tr_read_check(7, 21, 16'h0000);

    $display("TB PASS");
    $finish;
  end

endmodule