/*
 * Module Name: cmi (Conflict-Free Memory Interface)
 * Author(s): Mai Komar
 * Target: FIPS 203 (ML-KEM / Kyber) Hardware Accelerator
 *
 * Reference:
 *   "Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"
 *   H. Jung, Q. D. Truong, H. Lee — IEEE OJCAS 2025
 *
 * *** THIS MODULE BELONGS TO THE PAU (Polynomial Arithmetic Unit). ***
 * It is included in this repository to define the interface contract
 * between the PAU and the Memory Subsystem's poly_mem_wrapper_4bank.
 *
 * Description:
 *   Adapter between the PAU controller / AU writeback path and the
 *   Memory Subsystem. The CMI:
 *     - Forwards 4-lane read requests (coefficient indices + valid flags)
 *       to the memory wrapper, which handles CMI bank mapping internally
 *     - Consumes the wrapper's 1-cycle read response and presents
 *       aligned coefficient data to the AU
 *     - Aligns writeback indices via configurable delay pipelines
 *       (2/4/5/9 cycle latency) so write addresses arrive at the memory
 *       wrapper at the same time as AU result data
 *     - Allows write-only cycles (no concurrent read) for drain/final
 *       writeback phases
 *
 * Fixed to match poly_mem_wrapper_4bank.sv:
 * - Wrapper handles bank mapping + read response reordering
 * - Read response latency is 1 cycle
 * - CMI forwards rd_lane_valid to wrapper
 * - CMI consumes wrapper response metadata directly
 * - Writes are allowed even when no new read is being issued
 */

module cmi #(
    parameter int N         = 256,
    parameter int W         = 16,
    parameter int NUM_POLYS = 4,
    parameter int MAX_WB_LAT = 9
)(
    input  logic clk,
    input  logic rst,   // active-high synchronous reset

    // ------------------------------------------------------------
    // From controller / rd_wr_addr_gen
    // ------------------------------------------------------------
    input  logic [3:0][7:0]              coeff_idx_i,
    input  logic [3:0]                   coeff_valid_i,

    // ------------------------------------------------------------
    // Control interface
    // ------------------------------------------------------------
    input  logic [$clog2(NUM_POLYS)-1:0] poly_id_i,
    input  logic                         v_i,
    input  logic                         rd_en_i,
    input  logic [3:0]                   wb_latency_i,

    // ------------------------------------------------------------
    // From AU writeback path
    // ------------------------------------------------------------
    input  logic [3:0]                   wr_en_i,
    input  logic [3:0][W-1:0]            wr_data_i,

    // ------------------------------------------------------------
    // Coefficient output to AU
    // ------------------------------------------------------------
    output logic [3:0][W-1:0]            coeff_o,

    // ------------------------------------------------------------
    // Status back to controller
    // ------------------------------------------------------------
    output logic                         ready_o,

    // ------------------------------------------------------------
    // To poly_mem_wrapper_4bank
    // ------------------------------------------------------------
    output logic [$clog2(NUM_POLYS)-1:0] mem_poly_id_o,
    output logic                         mem_v_o,
    output logic                         mem_rd_en_o,

    output logic [3:0][$clog2(N)-1:0]    mem_rd_idx_o,
    output logic [3:0]                   mem_rd_lane_valid_o,

    output logic [3:0]                   mem_wr_en_o,
    output logic [3:0][$clog2(N)-1:0]    mem_wr_idx_o,
    output logic [3:0][W-1:0]            mem_wr_data_o,

    // ------------------------------------------------------------
    // From poly_mem_wrapper_4bank
    // ------------------------------------------------------------
    input  logic                         mem_rd_valid_i,
    input  logic [$clog2(NUM_POLYS)-1:0] mem_rd_poly_id_i,
    input  logic [3:0][$clog2(N)-1:0]    mem_rd_idx_i,
    input  logic [3:0]                   mem_rd_lane_valid_i,
    input  logic [3:0][W-1:0]            mem_rd_data_i,
    input  logic                         mem_ready_i
);

    // ============================================================
    // READ REQUEST PATH
    // Wrapper already performs bank mapping and returns aligned
    // rd_data_o one cycle later, so CMI only forwards request info.
    // ============================================================
    assign mem_poly_id_o       = poly_id_i;

    // Important fix:
    // allow write-only cycles during drain/final writeback
    assign mem_v_o             = v_i | (|wr_en_i);

    assign mem_rd_en_o         = rd_en_i;
    assign mem_rd_idx_o        = coeff_idx_i;
    assign mem_rd_lane_valid_o = coeff_valid_i;

    // ============================================================
    // READ RESPONSE PATH
    // Wrapper already reorders bank outputs back into logical lanes.
    // So just forward valid lanes into coeff_o.
    // ============================================================
    always_comb begin
        coeff_o = '0;

        if (mem_rd_valid_i) begin
            for (int i = 0; i < 4; i++) begin
                if (mem_rd_lane_valid_i[i]) begin
                    coeff_o[i] = mem_rd_data_i[i];
                end
            end
        end
    end


    // ============================================================
    // WRITEBACK ALIGNMENT
    // Delay read indices and lane-valids by the request-to-writeback
    // latency selected by the controller. This latency is measured
    // from the original read issue cycle.
    // ============================================================
    logic [3:0][$clog2(N)-1:0] wr_idx_pipe   [0:MAX_WB_LAT];
    logic [3:0]                valid_pipe    [0:MAX_WB_LAT];

    generate
        for (genvar i0 = 0; i0 < 4; i0++) begin : G_WB_PIPE_HEAD
            assign wr_idx_pipe[0][i0] = coeff_idx_i[i0];
            assign valid_pipe[0][i0]  = coeff_valid_i[i0];
        end
    endgenerate

    generate
        for (genvar d = 0; d < MAX_WB_LAT; d++) begin : G_WB_PIPE_STAGE
            for (genvar i = 0; i < 4; i++) begin : G_WB_PIPE_LANE
                delay_n #(
                    .DWIDTH ($clog2(N)),
                    .DEPTH  (d+1)
                ) u_idx_delay (
                    .clk    (clk),
                    .rst    (rst),
                    .data_i (coeff_idx_i[i]),
                    .data_o (wr_idx_pipe[d+1][i])
                );

                delay_n #(
                    .DWIDTH (1),
                    .DEPTH  (d+1)
                ) u_valid_delay (
                    .clk    (clk),
                    .rst    (rst),
                    .data_i (coeff_valid_i[i]),
                    .data_o (valid_pipe[d+1][i])
                );
            end
        end
    endgenerate

    logic [3:0][$clog2(N)-1:0] wr_idx_sel;
    logic [3:0]                coeff_valid_sel;

    always_comb begin
        wr_idx_sel      = wr_idx_pipe[2];
        coeff_valid_sel = valid_pipe[2];

        unique case (wb_latency_i)
            4'd2: begin wr_idx_sel = wr_idx_pipe[2]; coeff_valid_sel = valid_pipe[2]; end
            4'd4: begin wr_idx_sel = wr_idx_pipe[4]; coeff_valid_sel = valid_pipe[4]; end
            4'd5: begin wr_idx_sel = wr_idx_pipe[5]; coeff_valid_sel = valid_pipe[5]; end
            4'd9: begin wr_idx_sel = wr_idx_pipe[9]; coeff_valid_sel = valid_pipe[9]; end
            default: begin wr_idx_sel = wr_idx_pipe[2]; coeff_valid_sel = valid_pipe[2]; end
        endcase
    end

    assign mem_wr_en_o   = wr_en_i & coeff_valid_sel;
    assign mem_wr_idx_o  = wr_idx_sel;
    assign mem_wr_data_o = wr_data_i;


    // ============================================================
    // READY
    // ============================================================
    assign ready_o = mem_ready_i;

endmodule
