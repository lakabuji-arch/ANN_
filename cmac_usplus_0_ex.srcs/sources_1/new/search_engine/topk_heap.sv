module topk_heap #(
    parameter MAX_K   = 256,
    parameter ID_BITS = 32
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [7:0]   i_k,
    input  wire         i_push,
    input  wire [31:0]  i_distance,
    input  wire [ID_BITS-1:0] i_vector_id,
    output wire         o_full,
    output wire         o_ready,
    input  wire         i_read_en,
    output wire [31:0]  o_distance,
    output wire [ID_BITS-1:0] o_vector_id,
    output wire         o_read_valid,
    output wire [7:0]   o_count
);
    localparam S_IDLE = 2'd0, S_SIFT = 2'd1;

    reg [31:0]              heap_dist [0:MAX_K-1];
    reg [ID_BITS-1:0]       heap_id   [0:MAX_K-1];
    reg [7:0]               heap_size;
    reg [7:0]               read_ptr;
    reg [1:0]               state;
    reg [7:0]               sift_i;
    wire [7:0]              left  = (sift_i << 1) + 1;
    wire [7:0]              right = (sift_i << 1) + 2;
    wire                    left_valid  = (left  < heap_size);
    wire                    right_valid = (right < heap_size);
    wire                    left_bigger  = left_valid  && (heap_dist[left]  > heap_dist[sift_i]);
    wire                    right_bigger = right_valid && (heap_dist[right] > heap_dist[sift_i]);
    wire                    right_bigger_than_left = right_valid &&
                                (heap_dist[right] > heap_dist[left]);

    always @(posedge clk) begin
        if (rst) begin
            heap_size <= 0; state <= S_IDLE; read_ptr <= 0; sift_i <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (i_push) begin
                        if (heap_size < i_k && heap_size < MAX_K) begin
                            heap_dist[heap_size] <= i_distance;
                            heap_id[heap_size]   <= i_vector_id;
                            // sift-up
                            sift_i <= heap_size;
                            state <= S_SIFT;
                            heap_size <= heap_size + 1;
                        end else if (i_distance < heap_dist[0]) begin
                            heap_dist[0] <= i_distance;
                            heap_id[0]   <= i_vector_id;
                            sift_i <= 0;
                            state <= S_SIFT;
                        end
                    end
                end

                S_SIFT: begin
                    if (left_valid && left_bigger && !right_bigger_than_left) begin
                        heap_dist[sift_i] <= heap_dist[left];
                        heap_id[sift_i]   <= heap_id[left];
                        heap_dist[left]   <= heap_dist[sift_i];
                        heap_id[left]     <= heap_id[sift_i];
                        sift_i <= left;
                    end else if (right_valid && right_bigger) begin
                        heap_dist[sift_i] <= heap_dist[right];
                        heap_id[sift_i]   <= heap_id[right];
                        heap_dist[right]  <= heap_dist[sift_i];
                        heap_id[right]    <= heap_id[sift_i];
                        sift_i <= right;
                    end else begin
                        state <= S_IDLE;
                    end
                end
            endcase

            if (i_read_en && read_ptr < heap_size)
                read_ptr <= read_ptr + 1;
            else if (!i_read_en)
                read_ptr <= 0;
        end
    end

    assign o_full       = (heap_size >= i_k);
    assign o_ready      = o_full && (state == S_IDLE);
    assign o_count      = heap_size;
    assign o_read_valid = (read_ptr < heap_size);
    assign o_distance   = o_read_valid ? heap_dist[read_ptr] : 32'd0;
    assign o_vector_id  = o_read_valid ? heap_id[read_ptr]   : {ID_BITS{1'b0}};
endmodule
