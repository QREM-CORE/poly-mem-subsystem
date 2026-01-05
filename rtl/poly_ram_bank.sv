
module poly_ram_bank #(
  parameter int N      = 256,
  parameter int W      = 16,
  parameter int ADDR_W = $clog2(N)
)(
  input  logic              clk,
  input  logic              rst_n,

  // Port A
  input  logic              a_we,
  input  logic [ADDR_W-1:0] a_addr,
  input  logic [W-1:0]      a_wdata,
  output logic [W-1:0]      a_rdata,

  // Port B
  input  logic              b_we,
  input  logic [ADDR_W-1:0] b_addr,
  input  logic [W-1:0]      b_wdata,
  output logic [W-1:0]      b_rdata
);

  logic [W-1:0] mem [0:N-1];

  always_ff @(posedge clk) begin
    if (a_we) mem[a_addr] <= a_wdata;
    a_rdata <= mem[a_addr];
  end

  always_ff @(posedge clk) begin
    if (b_we) mem[b_addr] <= b_wdata;
    b_rdata <= mem[b_addr];
  end

endmodule
