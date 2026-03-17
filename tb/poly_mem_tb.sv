
module tb_poly_mem;

  localparam int NUM_BANKS = 4;
  localparam int N         = 256;
  localparam int W         = 16;
  localparam int ADDR_W    = $clog2(N);
  localparam int BANK_W    = $clog2(NUM_BANKS);

  logic clk, rst_n;

  // NTT
  logic ntt_req;
  logic [BANK_W-1:0] ntt_bank;
  logic ntt_we;
  logic [ADDR_W-1:0] ntt_addr;
  logic [W-1:0] ntt_wdata;
  logic [W-1:0] ntt_rdata;
  logic ntt_stall;

  // PolyMul
  logic pm_req;
  logic [BANK_W-1:0] pm_bank_r0, pm_bank_r1, pm_bank_w;
  logic [ADDR_W-1:0] pm_addr_r0, pm_addr_r1, pm_addr_w;
  logic pm_we;
  logic [W-1:0] pm_wdata;
  logic [W-1:0] pm_rdata_r0, pm_rdata_r1;
  logic pm_stall;

  // Pack/Unpack
  logic pu_req;
  logic [BANK_W-1:0] pu_bank;
  logic pu_we;
  logic [ADDR_W-1:0] pu_addr;
  logic [W-1:0] pu_wdata;
  logic [W-1:0] pu_rdata;
  logic pu_stall;

  poly_mem_subsystem #(
    .NUM_BANKS(NUM_BANKS),
    .N(N),
    .W(W),
    .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk), .rst_n(rst_n),

    .ntt_req(ntt_req), .ntt_bank(ntt_bank), .ntt_we(ntt_we),
    .ntt_addr(ntt_addr), .ntt_wdata(ntt_wdata),
    .ntt_rdata(ntt_rdata), .ntt_stall(ntt_stall),

    .pm_req(pm_req),
    .pm_bank_r0(pm_bank_r0), .pm_addr_r0(pm_addr_r0), .pm_rdata_r0(pm_rdata_r0),
    .pm_bank_r1(pm_bank_r1), .pm_addr_r1(pm_addr_r1), .pm_rdata_r1(pm_rdata_r1),
    .pm_bank_w(pm_bank_w), .pm_we(pm_we), .pm_addr_w(pm_addr_w), .pm_wdata(pm_wdata),
    .pm_stall(pm_stall),

    .pu_req(pu_req), .pu_bank(pu_bank), .pu_we(pu_we),
    .pu_addr(pu_addr), .pu_wdata(pu_wdata),
    .pu_rdata(pu_rdata), .pu_stall(pu_stall)
  );

  // Clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic reset_all();
    begin
      rst_n = 1'b0;

      ntt_req=0; ntt_bank='0; ntt_we=0; ntt_addr='0; ntt_wdata='0;
      pm_req=0;  pm_bank_r0='0; pm_bank_r1='0; pm_bank_w='0; pm_we=0;
      pm_addr_r0='0; pm_addr_r1='0; pm_addr_w='0; pm_wdata='0;
      pu_req=0;  pu_bank='0; pu_we=0; pu_addr='0; pu_wdata='0;

      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic write_ramp(input int bank, input int count);
    int i;
    begin
      for (i=0; i<count; i++) begin
        @(posedge clk);
        ntt_req   <= 1;
        ntt_bank  <= BANK_W'(bank);
        ntt_we    <= 1;
        ntt_addr  <= ADDR_W'(i);
        ntt_wdata <= W'(i*3 + 7);
      end
      @(posedge clk);
      ntt_req <= 0; ntt_we <= 0;
    end
  endtask

  task automatic basic_dual_access(input int bank);
    int i;
    begin
      for (i=0; i<8; i++) begin
        @(posedge clk);
        ntt_req  <= 1;
        ntt_bank <= BANK_W'(bank);
        ntt_we   <= 0;
        ntt_addr <= ADDR_W'(i);

        pm_req     <= 1;
        pm_bank_r0 <= BANK_W'(bank);
        pm_addr_r0 <= ADDR_W'(i+8);

        pm_bank_r1 <= BANK_W'((bank+1) % NUM_BANKS);
        pm_addr_r1 <= ADDR_W'(i);

        pm_we      <= 0;
      end
      @(posedge clk);
      ntt_req <= 0;
      pm_req  <= 0;
    end
  endtask

  task automatic ntt_like_strides(input int bank);
    int stride, k;
    begin
      stride = 1;
      repeat (4) begin
        for (k=0; k<16; k++) begin
          @(posedge clk);
          ntt_req  <= 1;
          ntt_bank <= BANK_W'(bank);
          ntt_we   <= 0;
          ntt_addr <= ADDR_W'(k*stride);
        end
        stride *= 2;
      end
      @(posedge clk);
      ntt_req <= 0;
    end
  endtask

  task automatic force_same_bank_read_conflict(input int bank);
    begin
      @(posedge clk);
      pm_req     <= 1;
      pm_bank_r0 <= BANK_W'(bank);
      pm_addr_r0 <= ADDR_W'(1);
      pm_bank_r1 <= BANK_W'(bank);   // same bank => should stall
      pm_addr_r1 <= ADDR_W'(2);
      pm_we      <= 0;

      @(posedge clk);
      if (!pm_stall) $fatal(1, "Expected pm_stall on same-bank dual-read conflict!");
      pm_req <= 0;
    end
  endtask

  initial begin
    reset_all();

    write_ramp(0, 32);
    basic_dual_access(0);
    ntt_like_strides(0);
    force_same_bank_read_conflict(0);

    $display("TB PASS");
    $finish;
  end

endmodule
