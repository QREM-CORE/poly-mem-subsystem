module cmi_tb;

cmi DUT (
    .clk                    (),
    .rst                    (),
    .coeff_idx_i            (),
    .coeff_valid_i          (),
    .poly_id_i              (),
    .v_i                    (),
    .rd_en_i                (),
    .wr_en_i                (),
    .wr_data_i              (),
    .coeff_o                (),
    .ready_o                (),
    .mem_poly_id_o          (),
    .mem_v_o                (),
    .mem_rd_en_o            (),
    .mem_rd_idx_o           (),
    .mem_rd_lane_valid_o    (),
    .mem_wr_en_o            (),
    .mem_wr_idx_o           (),
    .mem_wr_data_o          (),
    .mem_rd_valid_i         (),
    .mem_rd_poly_id_i       (),
    .mem_rd_idx_i           (),
    .mem_rd_lane_valid_i    (),
    .mem_rd_data_i          (),
    .mem_ready_i            ()
);

endmodule;