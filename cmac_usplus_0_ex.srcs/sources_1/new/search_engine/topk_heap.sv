// topk_heap.sv — Top-K minimum-distance heap (max-heap representation)
// Root holds the LARGEST of the K smallest distances seen so far.
// New distance < root: replace root, sift-down.
// Heap not full yet: insert at end, sift-up.
module topk_heap #(
    parameter int MAX_K   = 256,
    parameter int ID_BITS = 32
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
    localparam logic [1:0] S_IDLE    = 2'd0;
    localparam logic [1:0] S_SIFT_UP = 2'd1;
    localparam logic [1:0] S_SIFT_DN = 2'd2;

    reg [31:0]              heap_dist [MAX_K];
    reg [ID_BITS-1:0]       heap_id   [MAX_K];
    reg [7:0]               heap_size;
    reg [7:0]               read_ptr;
    reg [1:0]               state;
    reg [7:0]               sift_i;

    // Saved original values for swap
    reg [31:0]              save_dist;
    reg [ID_BITS-1:0]       save_id;

    // sift-up helpers
    wire [7:0] parent       = (sift_i - 1) >> 1;
    wire       parent_valid = (sift_i > 0);
    wire       parent_smaller = parent_valid && (heap_dist[parent] < save_dist);

    // sift-down helpers
    wire [7:0] left         = (sift_i << 1) + 1;
    wire [7:0] right        = (sift_i << 1) + 2;
    wire       left_valid   = (left  < heap_size);
    wire       right_valid  = (right < heap_size);
    wire       left_bigger  = left_valid  && (heap_dist[left]  > save_dist);
    wire       right_bigger = right_valid && (heap_dist[right] > save_dist);
    // Pick the larger child (or left if equal)
    wire       go_left      = left_bigger && (!right_valid || (heap_dist[left] >= heap_dist[right]));
    wire       go_right     = right_valid && right_bigger && (!left_valid || (heap_dist[right] > heap_dist[left]));

    always @(posedge clk) begin
        if (rst) begin
            heap_size <= 0;
            read_ptr  <= 0;
            state     <= S_IDLE;
            sift_i    <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (i_push) begin
                        if (heap_size < i_k && heap_size < MAX_K) begin
                            // Insert at end, then sift-up
                            heap_dist[heap_size] <= i_distance;
                            heap_id[heap_size]   <= i_vector_id;
                            save_dist <= i_distance;
                            save_id   <= i_vector_id;
                            sift_i    <= heap_size;
                            state     <= S_SIFT_UP;
                            heap_size <= heap_size + 1;
                        end else if (i_distance < heap_dist[0]) begin
                            // Replace root, then sift-down
                            save_dist <= i_distance;
                            save_id   <= i_vector_id;
                            sift_i    <= 0;
                            state     <= S_SIFT_DN;
                        end
                    end
                end

                S_SIFT_UP: begin
                    if (parent_smaller) begin
                        // Move parent down, continue sifting up
                        heap_dist[sift_i] <= heap_dist[parent];
                        heap_id[sift_i]   <= heap_id[parent];
                        sift_i <= parent;
                    end else begin
                        // Place saved value at current position
                        heap_dist[sift_i] <= save_dist;
                        heap_id[sift_i]   <= save_id;
                        state <= S_IDLE;
                    end
                end

                S_SIFT_DN: begin
                    if (go_left) begin
                        // Move left child up, continue sifting down through left
                        heap_dist[sift_i] <= heap_dist[left];
                        heap_id[sift_i]   <= heap_id[left];
                        sift_i <= left;
                    end else if (go_right) begin
                        // Move right child up, continue sifting down through right
                        heap_dist[sift_i] <= heap_dist[right];
                        heap_id[sift_i]   <= heap_id[right];
                        sift_i <= right;
                    end else begin
                        // Place saved value at current position
                        heap_dist[sift_i] <= save_dist;
                        heap_id[sift_i]   <= save_id;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase

            // Readout pointer
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
