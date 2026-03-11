module seed_ram #(
  parameter int DEPTH   = 16,
  parameter int W       = 64,
  parameter int ADDR_W  = $clog2(DEPTH)
)(
  input  logic              clk,
  input  logic              rst_n,

  input  logic              we,
  input  logic [ADDR_W-1:0] addr,
  input  logic [W-1:0]      wdata,
  output logic [W-1:0]      rdata
);

  logic [W-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (we)
      mem[addr] <= wdata;

    rdata <= mem[addr];
  end

endmodule