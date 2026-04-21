`timescale 1ns/1ps

module mem_arbiter_tb;

  logic pau_req_i;
  logic hsu_req_i;
  logic tr_req_i;
  logic mem_ready_i;

  logic grant_pau_o;
  logic grant_hsu_o;
  logic grant_tr_o;
  logic pau_stall_o;
  logic hsu_stall_o;
  logic tr_stall_o;

  mem_arbiter dut (
    .pau_req_i   (pau_req_i),
    .hsu_req_i   (hsu_req_i),
    .tr_req_i    (tr_req_i),
    .mem_ready_i (mem_ready_i),
    .grant_pau_o (grant_pau_o),
    .grant_hsu_o (grant_hsu_o),
    .grant_tr_o  (grant_tr_o),
    .pau_stall_o (pau_stall_o),
    .hsu_stall_o (hsu_stall_o),
    .tr_stall_o  (tr_stall_o)
  );

  task automatic clear_all;
    begin
      pau_req_i   = 1'b0;
      hsu_req_i   = 1'b0;
      tr_req_i    = 1'b0;
      mem_ready_i = 1'b1;
    end
  endtask

  initial begin
    clear_all();

    // ----------------------------------------------------------
    // Test 1: PAU wins everything below it
    // ----------------------------------------------------------
    pau_req_i = 1'b1;
    hsu_req_i = 1'b1;
    tr_req_i  = 1'b1;
    #1;

    if (!grant_pau_o || grant_hsu_o || grant_tr_o)
      $fatal(1, "Test1: PAU should be sole grant");
    if (pau_stall_o !== 1'b0)
      $fatal(1, "Test1: PAU should not stall when memory is ready");
    if (hsu_stall_o !== 1'b1 || tr_stall_o !== 1'b1)
      $fatal(1, "Test1: lower-priority requesters must stall");

    clear_all();

    // ----------------------------------------------------------
    // Test 2: HSU beats Transcoder
    // ----------------------------------------------------------
    hsu_req_i = 1'b1;
    tr_req_i  = 1'b1;
    #1;

    if (!grant_hsu_o || grant_pau_o || grant_tr_o)
      $fatal(1, "Test2: HSU should be sole grant");
    if (hsu_stall_o !== 1'b0)
      $fatal(1, "Test2: HSU should not stall when memory is ready");
    if (tr_stall_o !== 1'b1)
      $fatal(1, "Test2: Transcoder should stall behind HSU");

    clear_all();

    // ----------------------------------------------------------
    // Test 3: Transcoder alone gets the slot
    // ----------------------------------------------------------
    tr_req_i = 1'b1;
    #1;

    if (!grant_tr_o || grant_pau_o || grant_hsu_o)
      $fatal(1, "Test3: Transcoder should be sole grant");
    if (tr_stall_o !== 1'b0)
      $fatal(1, "Test3: Transcoder should not stall when memory is ready");

    clear_all();

    // ----------------------------------------------------------
    // Test 4: Selected client sees downstream not-ready as stall
    // ----------------------------------------------------------
    pau_req_i   = 1'b1;
    mem_ready_i = 1'b0;
    #1;

    if (!grant_pau_o)
      $fatal(1, "Test4: PAU should still hold grant when memory is busy");
    if (pau_stall_o !== 1'b1)
      $fatal(1, "Test4: selected client should see downstream stall");

    clear_all();

    // ----------------------------------------------------------
    // Test 5: No requests -> no grants or stalls
    // ----------------------------------------------------------
    #1;
    if (grant_pau_o || grant_hsu_o || grant_tr_o)
      $fatal(1, "Test5: no grants expected");
    if (pau_stall_o || hsu_stall_o || tr_stall_o)
      $fatal(1, "Test5: no stalls expected");

    $display("TB PASS");
    $finish;
  end

endmodule
