`timescale 1ns/1ps

module seed_ram_tb;

  localparam int DEPTH  = 16;
  localparam int W      = 64;
  localparam int ADDR_W = $clog2(DEPTH);

  logic              clk;
  logic              rst_n;
  logic              we;
  logic [ADDR_W-1:0] addr;
  logic [W-1:0]      wdata;
  logic [W-1:0]      rdata;

  seed_ram #(
    .DEPTH(DEPTH),
    .W(W),
    .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .we(we),
    .addr(addr),
    .wdata(wdata),
    .rdata(rdata)
  );

  // clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    we    = 1'b0;
    addr  = '0;
    wdata = '0;

    // reset phase
    repeat (3) tick();
    rst_n = 1'b1;
    tick();

    // --------------------------
    // Write a few 64-bit values
    // --------------------------
    we    = 1'b1;
    addr  = 0;
    wdata = 64'h1122334455667788;
    tick();

    addr  = 1;
    wdata = 64'hAABBCCDDEEFF0011;
    tick();

    addr  = 2;
    wdata = 64'h123456789ABCDEF0;
    tick();

    we    = 1'b0;

    // --------------------------
    // Read them back
    // synchronous read:
    // present addr in cycle N
    // observe rdata after next posedge
    // --------------------------
    addr = 0;
    tick();
    if (rdata !== 64'h1122334455667788) begin
      $fatal(1, "Seed RAM read mismatch at addr 0. got=%h exp=%h",
             rdata, 64'h1122334455667788);
    end

    addr = 1;
    tick();
    if (rdata !== 64'hAABBCCDDEEFF0011) begin
      $fatal(1, "Seed RAM read mismatch at addr 1. got=%h exp=%h",
             rdata, 64'hAABBCCDDEEFF0011);
    end

    addr = 2;
    tick();
    if (rdata !== 64'h123456789ABCDEF0) begin
      $fatal(1, "Seed RAM read mismatch at addr 2. got=%h exp=%h",
             rdata, 64'h123456789ABCDEF0);
    end

    // --------------------------
    // Overwrite one location
    // --------------------------
    we    = 1'b1;
    addr  = 1;
    wdata = 64'h0F0E0D0C0B0A0908;
    tick();
    we    = 1'b0;

    addr = 1;
    tick();
    if (rdata !== 64'h0F0E0D0C0B0A0908) begin
      $fatal(1, "Seed RAM overwrite mismatch at addr 1. got=%h exp=%h",
             rdata, 64'h0F0E0D0C0B0A0908);
    end

    $display("TB PASS");
    $finish;
  end

endmodule
