// distance_compute_unit.sv — Pipelined vector distance calculator
// Q16.16 fixed-point, DSP-inferred, 4-stage pipeline
module distance_compute_unit #(
    parameter MAX_DIM = 1536
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         i_start,
    input  wire [10:0]  i_dim,           // actual dimension count (1-1536)
    input  wire [1:0]   i_metric,        // 0=L2, 1=cosine, 2=IP
    input  wire [511:0] i_vec_a_tdata,   // 16 x Q16.16 values
    input  wire         i_vec_a_tvalid,
    output wire         o_vec_a_tready,
    input  wire [511:0] i_vec_b_tdata,
    input  wire         i_vec_b_tvalid,
    output wire         o_vec_b_tready,
    output wire         o_valid,
    output wire [31:0]  o_distance
);
    localparam ST_IDLE    = 3'd0;
    localparam ST_COMPUTE = 3'd1;
    localparam ST_FLUSH   = 3'd2;
    localparam ST_DONE    = 3'd3;

    reg [2:0]  state = ST_IDLE;
    reg [10:0] dim_cnt;
    reg [63:0] accum;          // 64-bit internal accumulator
    reg [31:0] result_reg;

    // Unpack 512b into 16 x 32b
    wire signed [31:0] a_val [0:15];
    wire signed [31:0] b_val [0:15];
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_unpack
            assign a_val[g] = i_vec_a_tdata[g*32 +: 32];
            assign b_val[g] = i_vec_b_tdata[g*32 +: 32];
        end
    endgenerate

    // Pipeline registers: stage1 = subtraction, stage2 = multiply, stage3 = pairwise add
    reg signed [31:0] s1_diff [0:15];
    reg signed [31:0] s2_prod [0:15];
    reg signed [31:0] s3_sum  [0:7];
    reg signed [31:0] s4_sum  [0:3];
    reg signed [31:0] s5_sum  [0:1];
    reg signed [31:0] s6_total;
    reg         pipe_valid [0:6];  // valid bit per pipeline stage

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            dim_cnt <= 0;
            accum <= 0;
            result_reg <= 0;
            for (i = 0; i < 7; i = i + 1) pipe_valid[i] <= 0;
        end else begin
            // Pipeline shift
            pipe_valid[0] <= (state == ST_COMPUTE) && i_vec_a_tvalid && i_vec_b_tvalid;
            pipe_valid[1] <= pipe_valid[0];
            pipe_valid[2] <= pipe_valid[1];
            pipe_valid[3] <= pipe_valid[2];
            pipe_valid[4] <= pipe_valid[3];
            pipe_valid[5] <= pipe_valid[4];
            pipe_valid[6] <= pipe_valid[5];

            // Stage 0: subtraction
            if (pipe_valid[0]) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (dim_cnt * 16 + i < i_dim)
                        s1_diff[i] <= a_val[i] - b_val[i];
                    else
                        s1_diff[i] <= 0;
                end
            end

            // Stage 1: multiply
            if (pipe_valid[1]) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (i_metric == 2'b10)  // IP: just multiply
                        s2_prod[i] <= ($signed(s1_diff[i]) * $signed({32'd0})) >>> 16;
                    else  // L2/Cosine: square the diff
                        s2_prod[i] <= ($signed(s1_diff[i]) * $signed(s1_diff[i])) >>> 16;
                end
            end

            // Stage 2: 16→8 pairwise add
            if (pipe_valid[2]) begin
                for (i = 0; i < 8; i = i + 1)
                    s3_sum[i] <= s2_prod[i*2] + s2_prod[i*2+1];
            end

            // Stage 3: 8→4
            if (pipe_valid[3]) begin
                for (i = 0; i < 4; i = i + 1)
                    s4_sum[i] <= s3_sum[i*2] + s3_sum[i*2+1];
            end

            // Stage 4: 4→2
            if (pipe_valid[4]) begin
                for (i = 0; i < 2; i = i + 1)
                    s5_sum[i] <= s4_sum[i*2] + s4_sum[i*2+1];
            end

            // Stage 5: 2→1
            if (pipe_valid[5])
                s6_total <= s5_sum[0] + s5_sum[1];

            // Stage 6: accumulate
            if (pipe_valid[6])
                accum <= accum + { {32{s6_total[31]}}, s6_total };

            // State machine
            case (state)
                ST_IDLE: begin
                    if (i_start) begin
                        state <= ST_COMPUTE;
                        dim_cnt <= 0;
                        accum <= 0;
                    end
                end

                ST_COMPUTE: begin
                    if (i_vec_a_tvalid && i_vec_b_tvalid) begin
                        dim_cnt <= dim_cnt + 1;
                        if (dim_cnt + 1 >= (i_dim + 15) / 16)
                            state <= ST_FLUSH;
                    end
                end

                ST_FLUSH: begin
                    if (!pipe_valid[0] && !pipe_valid[1] && !pipe_valid[2] &&
                        !pipe_valid[3] && !pipe_valid[4] && !pipe_valid[5] && !pipe_valid[6])
                        state <= ST_DONE;
                end

                ST_DONE: begin
                    result_reg <= accum[47:16];  // scale back to Q16.16
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    assign o_valid = (state == ST_DONE);
    assign o_distance = result_reg;
    assign o_vec_a_tready = (state == ST_COMPUTE);
    assign o_vec_b_tready = (state == ST_COMPUTE);
endmodule
