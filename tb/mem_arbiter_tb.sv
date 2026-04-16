`timescale 1ns/1ps

module mem_arbiter_tb;

  localparam int NUM_BANKS = 4;
  localparam int ADDR_W    = 11;
  localparam int W         = 16;
  localparam int BANK_W    = $clog2(NUM_BANKS);

  // PAU
  logic              pau_req;
  logic [BANK_W-1:0] pau_bank;
  logic              pau_we;
  logic [ADDR_W-1:0] pau_addr;
  logic [W-1:0]      pau_wdata;
  logic              pau_stall;

  // HSU
  logic              hsu_req;
  logic [BANK_W-1:0] hsu_bank;
  logic              hsu_we;
  logic [ADDR_W-1:0] hsu_addr;
  logic [W-1:0]      hsu_wdata;
  logic              hsu_stall;

  // Transcoder
  logic              tr_req;
  logic [BANK_W-1:0] tr_bank;
  logic              tr_we;
  logic [ADDR_W-1:0] tr_addr;
  logic [W-1:0]      tr_wdata;
  logic              tr_stall;

  // Memory feedback stalls
  logic mem_pau_stall_i;
  logic mem_hsu_stall_i;
  logic mem_tr_stall_i;

  // Memory outputs
  logic              mem_req;
  logic [BANK_W-1:0] mem_bank;
  logic              mem_we;
  logic [ADDR_W-1:0] mem_addr;
  logic [W-1:0]      mem_wdata;

  mem_arbiter #(
    .NUM_BANKS(NUM_BANKS),
    .ADDR_W(ADDR_W),
    .W(W)
  ) dut (
    .pau_req(pau_req),
    .pau_bank(pau_bank),
    .pau_we(pau_we),
    .pau_addr(pau_addr),
    .pau_wdata(pau_wdata),
    .pau_stall(pau_stall),

    .hsu_req(hsu_req),
    .hsu_bank(hsu_bank),
    .hsu_we(hsu_we),
    .hsu_addr(hsu_addr),
    .hsu_wdata(hsu_wdata),
    .hsu_stall(hsu_stall),

    .tr_req(tr_req),
    .tr_bank(tr_bank),
    .tr_we(tr_we),
    .tr_addr(tr_addr),
    .tr_wdata(tr_wdata),
    .tr_stall(tr_stall),

    .mem_pau_stall_i(mem_pau_stall_i),
    .mem_hsu_stall_i(mem_hsu_stall_i),
    .mem_tr_stall_i(mem_tr_stall_i),

    .mem_req(mem_req),
    .mem_bank(mem_bank),
    .mem_we(mem_we),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata)
  );

  task automatic clear_all;
    begin
      pau_req   = 1'b0; pau_bank  = '0; pau_we  = 1'b0; pau_addr  = '0; pau_wdata  = '0;
      hsu_req   = 1'b0; hsu_bank  = '0; hsu_we  = 1'b0; hsu_addr  = '0; hsu_wdata  = '0;
      tr_req    = 1'b0; tr_bank   = '0; tr_we   = 1'b0; tr_addr   = '0; tr_wdata   = '0;

      mem_pau_stall_i = 1'b0;
      mem_hsu_stall_i = 1'b0;
      mem_tr_stall_i  = 1'b0;
    end
  endtask

  initial begin
    clear_all();

    // ------------------------------------------------------------
    // Test 1: only Transcoder requests
    // ------------------------------------------------------------
    tr_req   = 1'b1;
    tr_bank  = BANK_W'(2);
    tr_we    = 1'b1;
    tr_addr  = ADDR_W'(55);
    tr_wdata = 16'hAAAA;
    #1;

    if (!mem_req)                    $fatal(1, "Test1: mem_req should be high");
    if (mem_bank !== BANK_W'(2))     $fatal(1, "Test1: wrong mem_bank");
    if (mem_addr !== ADDR_W'(55))    $fatal(1, "Test1: wrong mem_addr");
    if (mem_wdata !== 16'hAAAA)      $fatal(1, "Test1: wrong mem_wdata");
    if (tr_stall !== 1'b0)           $fatal(1, "Test1: tr should not stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 2: HSU and Transcoder request together -> HSU wins
    // ------------------------------------------------------------
    hsu_req   = 1'b1;
    hsu_bank  = BANK_W'(1);
    hsu_we    = 1'b1;
    hsu_addr  = ADDR_W'(22);
    hsu_wdata = 16'hBBBB;

    tr_req    = 1'b1;
    tr_bank   = BANK_W'(3);
    tr_we     = 1'b1;
    tr_addr   = ADDR_W'(99);
    tr_wdata  = 16'hCCCC;
    #1;

    if (!mem_req)                    $fatal(1, "Test2: mem_req should be high");
    if (mem_bank !== BANK_W'(1))     $fatal(1, "Test2: HSU should win");
    if (mem_addr !== ADDR_W'(22))    $fatal(1, "Test2: wrong mem_addr");
    if (mem_wdata !== 16'hBBBB)      $fatal(1, "Test2: wrong mem_wdata");
    if (hsu_stall !== 1'b0)          $fatal(1, "Test2: HSU should not stall");
    if (tr_stall !== 1'b1)           $fatal(1, "Test2: Transcoder should stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 3: PAU and HSU request together -> PAU wins
    // ------------------------------------------------------------
    pau_req   = 1'b1;
    pau_bank  = BANK_W'(0);
    pau_we    = 1'b1;
    pau_addr  = ADDR_W'(7);
    pau_wdata = 16'h1111;

    hsu_req   = 1'b1;
    hsu_bank  = BANK_W'(2);
    hsu_we    = 1'b1;
    hsu_addr  = ADDR_W'(33);
    hsu_wdata = 16'h2222;
    #1;

    if (!mem_req)                    $fatal(1, "Test3: mem_req should be high");
    if (mem_bank !== BANK_W'(0))     $fatal(1, "Test3: PAU should win");
    if (mem_addr !== ADDR_W'(7))     $fatal(1, "Test3: wrong mem_addr");
    if (mem_wdata !== 16'h1111)      $fatal(1, "Test3: wrong mem_wdata");
    if (pau_stall !== 1'b0)          $fatal(1, "Test3: PAU should not stall");
    if (hsu_stall !== 1'b1)          $fatal(1, "Test3: HSU should stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 4: all three request together -> PAU wins
    // ------------------------------------------------------------
    pau_req   = 1'b1;
    pau_bank  = BANK_W'(3);
    pau_we    = 1'b1;
    pau_addr  = ADDR_W'(10);
    pau_wdata = 16'h1234;

    hsu_req   = 1'b1;
    hsu_bank  = BANK_W'(1);
    hsu_we    = 1'b1;
    hsu_addr  = ADDR_W'(20);
    hsu_wdata = 16'h5678;

    tr_req    = 1'b1;
    tr_bank   = BANK_W'(2);
    tr_we     = 1'b1;
    tr_addr   = ADDR_W'(30);
    tr_wdata  = 16'h9ABC;
    #1;

    if (!mem_req)                    $fatal(1, "Test4: mem_req should be high");
    if (mem_bank !== BANK_W'(3))     $fatal(1, "Test4: PAU should win");
    if (mem_addr !== ADDR_W'(10))    $fatal(1, "Test4: wrong mem_addr");
    if (mem_wdata !== 16'h1234)      $fatal(1, "Test4: wrong mem_wdata");
    if (pau_stall !== 1'b0)          $fatal(1, "Test4: PAU should not stall");
    if (hsu_stall !== 1'b1)          $fatal(1, "Test4: HSU should stall");
    if (tr_stall !== 1'b1)           $fatal(1, "Test4: Transcoder should stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 5: selected PAU gets downstream memory stall
    // ------------------------------------------------------------
    pau_req         = 1'b1;
    pau_bank        = BANK_W'(1);
    pau_we          = 1'b0;
    pau_addr        = ADDR_W'(44);
    pau_wdata       = 16'h0000;
    mem_pau_stall_i = 1'b1;
    #1;

    if (!mem_req)                    $fatal(1, "Test5: mem_req should be high");
    if (mem_bank !== BANK_W'(1))     $fatal(1, "Test5: PAU should still be selected");
    if (pau_stall !== 1'b1)          $fatal(1, "Test5: PAU stall should reflect memory stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 6: selected HSU gets downstream memory stall
    // ------------------------------------------------------------
    hsu_req         = 1'b1;
    hsu_bank        = BANK_W'(2);
    hsu_we          = 1'b0;
    hsu_addr        = ADDR_W'(12);
    hsu_wdata       = 16'h0000;
    mem_hsu_stall_i = 1'b1;
    #1;

    if (!mem_req)                    $fatal(1, "Test6: mem_req should be high");
    if (mem_bank !== BANK_W'(2))     $fatal(1, "Test6: HSU should be selected");
    if (hsu_stall !== 1'b1)          $fatal(1, "Test6: HSU stall should reflect memory stall");

    clear_all();

    // ------------------------------------------------------------
    // Test 7: selected Transcoder gets downstream memory stall
    // ------------------------------------------------------------
    tr_req         = 1'b1;
    tr_bank        = BANK_W'(0);
    tr_we          = 1'b0;
    tr_addr        = ADDR_W'(88);
    tr_wdata       = 16'h0000;
    mem_tr_stall_i = 1'b1;
    #1;

    if (!mem_req)                    $fatal(1, "Test7: mem_req should be high");
    if (mem_bank !== BANK_W'(0))     $fatal(1, "Test7: Transcoder should be selected");
    if (tr_stall !== 1'b1)           $fatal(1, "Test7: Transcoder stall should reflect memory stall");

    clear_all();

    $display("TB PASS");
    $finish;
  end

endmodule
