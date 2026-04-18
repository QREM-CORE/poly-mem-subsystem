`timescale 1ns/1ps

module seed_ram_tb;

  localparam int DEPTH  = 32;
  localparam int W      = 64;
  localparam int ADDR_W = $clog2(DEPTH);

  logic              clk;
  logic              rst;

  logic              a_we;
  logic [ADDR_W-1:0] a_addr;
  logic [W-1:0]      a_wdata;
  logic [W-1:0]      a_rdata;

  logic              b_we;
  logic [ADDR_W-1:0] b_addr;
  logic [W-1:0]      b_wdata;
  logic [W-1:0]      b_rdata;

  seed_ram #(
    .DEPTH  (DEPTH),
    .W      (W),
    .ADDR_W (ADDR_W)
  ) dut (
    .clk    (clk),
    .rst    (rst),
    .a_we   (a_we),
    .a_addr (a_addr),
    .a_wdata(a_wdata),
    .a_rdata(a_rdata),
    .b_we   (b_we),
    .b_addr (b_addr),
    .b_wdata(b_wdata),
    .b_rdata(b_rdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    rst    = 1'b1;
    a_we   = 1'b0;
    a_addr = '0;
    a_wdata = '0;
    b_we   = 1'b0;
    b_addr = '0;
    b_wdata = '0;

    repeat (2) tick();
    rst = 1'b0;
    tick();

    // ----------------------------------------------------------
    // Dual-port writes in the same cycle
    // ----------------------------------------------------------
    a_we    = 1'b1;
    a_addr  = ADDR_W'(1);
    a_wdata = 64'h1111_2222_3333_4444;
    b_we    = 1'b1;
    b_addr  = ADDR_W'(2);
    b_wdata = 64'hAAAA_BBBB_CCCC_DDDD;
    tick();
    a_we = 1'b0;
    b_we = 1'b0;

    // ----------------------------------------------------------
    // Dual-port reads in the same cycle
    // ----------------------------------------------------------
    a_addr = ADDR_W'(1);
    b_addr = ADDR_W'(2);
    tick();

    if (a_rdata !== 64'h1111_2222_3333_4444)
      $fatal(1, "Port A read mismatch. got=%h", a_rdata);
    if (b_rdata !== 64'hAAAA_BBBB_CCCC_DDDD)
      $fatal(1, "Port B read mismatch. got=%h", b_rdata);

    // ----------------------------------------------------------
    // Cross-port independence: A reads while B overwrites
    // ----------------------------------------------------------
    a_addr  = ADDR_W'(1);
    b_we    = 1'b1;
    b_addr  = ADDR_W'(3);
    b_wdata = 64'hDEAD_BEEF_0123_4567;
    tick();
    b_we = 1'b0;

    if (a_rdata !== 64'h1111_2222_3333_4444)
      $fatal(1, "Port A should not be disturbed by Port B write");

    b_addr = ADDR_W'(3);
    tick();
    if (b_rdata !== 64'hDEAD_BEEF_0123_4567)
      $fatal(1, "Port B overwrite/readback mismatch. got=%h", b_rdata);

    $display("TB PASS");
    $finish;
  end

endmodule
