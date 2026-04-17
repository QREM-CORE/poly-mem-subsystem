`timescale 1ns/1ps

module poly_mem_tb;

  localparam int NUM_BANKS = 4;
  localparam int N         = 2048;
  localparam int W         = 16;
  localparam int ADDR_W    = $clog2(N);
  localparam int BANK_W    = $clog2(NUM_BANKS);

  logic clk, rst_n;

  // Wipe
  logic wipe_i;
  logic wipe_done_o;

  // NTT
  logic              ntt_req;
  logic [BANK_W-1:0] ntt_bank;
  logic              ntt_we;
  logic [ADDR_W-1:0] ntt_addr;
  logic [W-1:0]      ntt_wdata;
  logic [W-1:0]      ntt_rdata;
  logic              ntt_stall;

  // PolyMul
  logic              pm_req;
  logic [BANK_W-1:0] pm_bank_r0, pm_bank_r1, pm_bank_w;
  logic [ADDR_W-1:0] pm_addr_r0, pm_addr_r1, pm_addr_w;
  logic              pm_we;
  logic [W-1:0]      pm_wdata;
  logic [W-1:0]      pm_rdata_r0, pm_rdata_r1;
  logic              pm_stall;

  // Pack/Unpack
  logic              pu_req;
  logic [BANK_W-1:0] pu_bank;
  logic              pu_we;
  logic [ADDR_W-1:0] pu_addr;
  logic [W-1:0]      pu_wdata;
  logic [W-1:0]      pu_rdata;
  logic              pu_stall;

  poly_mem_subsystem #(
    .NUM_BANKS(NUM_BANKS),
    .N(N),
    .W(W),
    .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .wipe_i(wipe_i),
    .wipe_done_o(wipe_done_o),

    .ntt_req(ntt_req),
    .ntt_bank(ntt_bank),
    .ntt_we(ntt_we),
    .ntt_addr(ntt_addr),
    .ntt_wdata(ntt_wdata),
    .ntt_rdata(ntt_rdata),
    .ntt_stall(ntt_stall),

    .pm_req(pm_req),
    .pm_bank_r0(pm_bank_r0),
    .pm_addr_r0(pm_addr_r0),
    .pm_rdata_r0(pm_rdata_r0),
    .pm_bank_r1(pm_bank_r1),
    .pm_addr_r1(pm_addr_r1),
    .pm_rdata_r1(pm_rdata_r1),
    .pm_bank_w(pm_bank_w),
    .pm_we(pm_we),
    .pm_addr_w(pm_addr_w),
    .pm_wdata(pm_wdata),
    .pm_stall(pm_stall),

    .pu_req(pu_req),
    .pu_bank(pu_bank),
    .pu_we(pu_we),
    .pu_addr(pu_addr),
    .pu_wdata(pu_wdata),
    .pu_rdata(pu_rdata),
    .pu_stall(pu_stall)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic clear_inputs;
    begin
      wipe_i    = 1'b0;

      ntt_req   = 1'b0;
      ntt_bank  = '0;
      ntt_we    = 1'b0;
      ntt_addr  = '0;
      ntt_wdata = '0;

      pm_req     = 1'b0;
      pm_bank_r0 = '0;
      pm_bank_r1 = '0;
      pm_bank_w  = '0;
      pm_we      = 1'b0;
      pm_addr_r0 = '0;
      pm_addr_r1 = '0;
      pm_addr_w  = '0;
      pm_wdata   = '0;

      pu_req   = 1'b0;
      pu_bank  = '0;
      pu_we    = 1'b0;
      pu_addr  = '0;
      pu_wdata = '0;
    end
  endtask

  task automatic reset_all;
    begin
      clear_inputs();
      rst_n = 1'b0;
      repeat (3) tick();
      rst_n = 1'b1;
      repeat (2) tick();
    end
  endtask

  // ------------------------------------------------------------
  // Write a pattern into one bank using NTT writes
  // ------------------------------------------------------------
  task automatic write_ramp(input int bank, input int count);
    int i;
    begin
      for (i = 0; i < count; i++) begin
        @(posedge clk);
        ntt_req   <= 1'b1;
        ntt_bank  <= BANK_W'(bank);
        ntt_we    <= 1'b1;
        ntt_addr  <= ADDR_W'(i);
        ntt_wdata <= W'(i*3 + 7);
      end
      @(posedge clk);
      ntt_req <= 1'b0;
      ntt_we  <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------
  // Read back one location and verify 1-cycle latency
  // ------------------------------------------------------------
  task automatic check_ntt_read_latency(
    input int bank,
    input int addr,
    input logic [W-1:0] exp_data
  );
    begin
      // Issue read request at cycle T
      @(posedge clk);
      ntt_req  <= 1'b1;
      ntt_bank <= BANK_W'(bank);
      ntt_we   <= 1'b0;
      ntt_addr <= ADDR_W'(addr);

      // At T itself, data is not yet the returned value we want
      #1;

      // At T+1, returned data should appear
      @(posedge clk);
      #1;
      if (ntt_rdata !== exp_data) begin
        $fatal(1, "NTT read latency check failed: bank=%0d addr=%0d got=%0h exp=%0h",
               bank, addr, ntt_rdata, exp_data);
      end

      // Clear request
      @(posedge clk);
      ntt_req <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------
  // Port A battle: NTT vs PM write vs PU on same bank
  // Expect NTT wins, PM and PU stall
  // ------------------------------------------------------------
  task automatic port_a_priority_battle(input int bank);
    begin
      @(posedge clk);
      ntt_req   <= 1'b1;
      ntt_bank  <= BANK_W'(bank);
      ntt_we    <= 1'b1;
      ntt_addr  <= ADDR_W'(10);
      ntt_wdata <= 16'h1111;

      pm_req     <= 1'b1;
      pm_bank_w  <= BANK_W'(bank);
      pm_we      <= 1'b1;
      pm_addr_w  <= ADDR_W'(11);
      pm_wdata   <= 16'h2222;
      pm_bank_r0 <= BANK_W'((bank+1) % NUM_BANKS);
      pm_addr_r0 <= ADDR_W'(0);
      pm_bank_r1 <= BANK_W'((bank+2) % NUM_BANKS);
      pm_addr_r1 <= ADDR_W'(0);

      pu_req   <= 1'b1;
      pu_bank  <= BANK_W'(bank);
      pu_we    <= 1'b1;
      pu_addr  <= ADDR_W'(12);
      pu_wdata <= 16'h3333;

      #1;
      if (ntt_stall !== 1'b0)
        $fatal(1, "Expected NTT to win Port A arbitration");
      if (pm_stall !== 1'b1)
        $fatal(1, "Expected PM write to stall under Port A conflict");
      if (pu_stall !== 1'b1)
        $fatal(1, "Expected PU to stall under Port A conflict");

      @(posedge clk);
      clear_inputs();
    end
  endtask

  // ------------------------------------------------------------
  // PolyMul same-bank dual-read conflict
  // Expect full stall
  // ------------------------------------------------------------
  task automatic force_same_bank_read_conflict(input int bank);
    begin
      @(posedge clk);
      pm_req     <= 1'b1;
      pm_bank_r0 <= BANK_W'(bank);
      pm_addr_r0 <= ADDR_W'(1);
      pm_bank_r1 <= BANK_W'(bank);
      pm_addr_r1 <= ADDR_W'(2);
      pm_we      <= 1'b0;

      #1;
      if (!pm_stall)
        $fatal(1, "Expected pm_stall on same-bank dual-read conflict!");

      @(posedge clk);
      clear_inputs();
    end
  endtask

  // ------------------------------------------------------------
  // Wipe test: trigger wipe and wait for done
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

  // ------------------------------------------------------------
  // Verify random-ish sample addresses are all zero after wipe
  // Since subsystem exposes NTT/PU reads on Port A, use NTT reads.
  // ------------------------------------------------------------
  task automatic verify_wipe_integrity;
    logic [W-1:0] rd;
    begin
      // Sample several addresses across all banks
      check_ntt_read_latency(0, 0,     16'h0000);
      check_ntt_read_latency(1, 5,     16'h0000);
      check_ntt_read_latency(2, 37,    16'h0000);
      check_ntt_read_latency(3, 99,    16'h0000);
      check_ntt_read_latency(0, 255,   16'h0000);
      check_ntt_read_latency(1, 511,   16'h0000);
      check_ntt_read_latency(2, 1023,  16'h0000);
      check_ntt_read_latency(3, 2047,  16'h0000);
    end
  endtask

  initial begin
    reset_all();

    // 1) preload some data so wipe actually matters
    write_ramp(0, 32);
    write_ramp(1, 16);

    // 2) verify 1-cycle latency on readback
    check_ntt_read_latency(0, 4, 16'(4*3 + 7));   // 19
    check_ntt_read_latency(1, 3, 16'(3*3 + 7));   // 16

    // 3) high-stress Port A arbitration
    port_a_priority_battle(2);

    // 4) same-bank PolyMul read conflict
    force_same_bank_read_conflict(0);

    // 5) wipe and verify memory is really zero
    run_wipe();
    verify_wipe_integrity();

    $display("TB PASS");
    $finish;
  end

endmodule
