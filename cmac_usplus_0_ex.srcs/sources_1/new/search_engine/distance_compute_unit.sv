// distance_compute_unit.sv — Pipelined vector distance calculator
// Q16.16 fixed-point, DSP-inferred, 4-stage pipeline
module distance_compute_unit #(
    parameter int MAX_DIM = 1536
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
    localparam logic [2:0] STIDLE    = 3'd0;
    localparam logic [2:0] STCOMPUTE = 3'd1;
    localparam logic [2:0] STFLUSH   = 3'd2;
    localparam logic [2:0] STDONE    = 3'd3;

    reg [2:0]  state = STIDLE;
    reg [10:0] dim_cnt;
    reg [63:0] accum;          // 64-bit internal accumulator
    reg [31:0] result_reg;
    reg        o_valid_reg;

    // Unpack 512b into 16 x 32b
    wire signed [31:0] a_val [16];
    wire signed [31:0] b_val [16];
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_unpack
            assign a_val[g] = i_vec_a_tdata[g*32 +: 32];
            assign b_val[g] = i_vec_b_tdata[g*32 +: 32];
        end
    endgenerate

    // Pipeline registers
    reg signed [31:0] s1_a    [16];   // stage 0: registered a_val
    reg signed [31:0] s1_b    [16];   // stage 0: registered b_val
    reg signed [31:0] s2_prod [16];   // stage 1: multiply result
    reg signed [31:0] s3_sum  [8];    // stage 2: 16→8 adder
    reg signed [31:0] s4_sum  [4];    // stage 3: 8→4 adder
    reg signed [31:0] s5_sum  [2];    // stage 4: 4→2 adder
    reg signed [31:0] s6_total;       // stage 5: 2→1 adder
    reg         pipe_valid [7];       // valid bit per pipeline stage

    // Combinational: is valid data entering the pipeline RIGHT NOW?
    wire pipe_in = (state == STCOMPUTE) && i_vec_a_tvalid && i_vec_b_tvalid;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state <= STIDLE;
            dim_cnt <= 0;
            accum <= 0;
            result_reg <= 0;
            o_valid_reg <= 0;
            for (i = 0; i < 7; i = i + 1) pipe_valid[i] <= 0;
        end else begin
            // Pipeline shift: stage 0 uses combinational pipe_in for data capture
            pipe_valid[0] <= pipe_in;
            pipe_valid[1] <= pipe_valid[0];
            pipe_valid[2] <= pipe_valid[1];
            pipe_valid[3] <= pipe_valid[2];
            pipe_valid[4] <= pipe_valid[3];
            pipe_valid[5] <= pipe_valid[4];
            pipe_valid[6] <= pipe_valid[5];

            // Stage 0: register a_val and b_val (use combinational pipe_in)
            if (pipe_in) begin
                for (i = 0; i < 16; i = i + 1) begin
                    s1_a[i] <= a_val[i];
                    s1_b[i] <= b_val[i];
                end
            end

            // Stage 1: compute diff^2 (L2/cosine) or a*b (IP)
            if (pipe_valid[1]) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (i_metric == 2'b10)  // IP: a * b
                        s2_prod[i] <= (($signed(s1_a[i]) * $signed(s1_b[i])) >>> 16);
                    else begin  // L2/Cosine: (a-b)^2
                        reg signed [63:0] diff64;
                        diff64 = $signed(s1_a[i]) - $signed(s1_b[i]);
                        s2_prod[i] <= ((diff64 * diff64) >>> 16);
                    end
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
                STIDLE: begin
                    o_valid_reg <= 1'b0;
                    if (i_start) begin
                        state <= STCOMPUTE;
                        dim_cnt <= 0;
                        accum <= 0;
                    end
                end

                STCOMPUTE: begin
                    if (i_vec_a_tvalid && i_vec_b_tvalid) begin
                        dim_cnt <= dim_cnt + 1;
                        if (dim_cnt + 1 >= (i_dim + 15) / 16)
                            state <= STFLUSH;
                    end
                end

                STFLUSH: begin
                    if (!pipe_valid[0] && !pipe_valid[1] && !pipe_valid[2] &&
                        !pipe_valid[3] && !pipe_valid[4] && !pipe_valid[5] && !pipe_valid[6])
                        state <= STDONE;
                end

                STDONE: begin
                    result_reg <= accum[31:0];   // extract Q16.16 result
                    o_valid_reg <= 1'b1;
                    state <= STIDLE;
                end
                default: ;
            endcase
        end
    end

    assign o_valid = o_valid_reg;
    assign o_distance = result_reg;
    assign o_vec_a_tready = (state == STCOMPUTE);
    assign o_vec_b_tready = (state == STCOMPUTE);
endmodule
