module ann_coarse_search #(
    parameter int NCLUSTERS = 1024,
    parameter int MAX_PROBES = 8,
    parameter int MAX_DIM = 1536
) (
    input  wire         clk,
    input  wire         rst,

    // Control
    input  wire         i_start,
    input  wire [10:0]  i_dim,
    input  wire [1:0]   i_metric,
    input  wire [3:0]   i_probes,           // P: 1-8

    // Query vector input
    input  wire [511:0] i_query_vec_a,      // query chunk for DCU port A
    input  wire         i_query_valid,
    output wire         o_query_ready,

    // Centroids URAM read interface
    output wire [9:0]   o_centroid_addr,    // 0-1023
    output wire         o_centroid_re,
    input  wire [511:0] i_centroid_rdata,   // 16x Q16.16 = 512b

    // DCU interface (reuses distance_compute_unit)
    output wire         o_dcu_start,
    output wire [10:0]  o_dcu_dim,
    output wire [1:0]   o_dcu_metric,
    output wire [511:0] o_dcu_vec_a,        // query vector for DCU
    output wire         o_dcu_vec_a_valid,
    input  wire         i_dcu_vec_a_ready,
    input  wire [511:0] i_dcu_vec_b,        // centroid data from DCU
    output wire         o_dcu_vec_b_valid,
    output wire         o_dcu_vec_b_ready,
    input  wire         i_dcu_valid,
    input  wire [31:0]  i_dcu_distance,

    // Results
    output wire         o_done,
    output wire [9:0]   o_cluster_id   [MAX_PROBES],
    output wire [15:0]  o_cluster_size [MAX_PROBES],
    output wire [3:0]   o_cluster_count
);
    localparam logic [2:0] SIDLE = 3'd0;
    localparam logic [2:0] SLOAD = 3'd1;  // load query into internal buffer
    localparam logic [2:0] SSCAN = 3'd2;  // scan centroids through DCU
    localparam logic [2:0] SWAIT = 3'd3;  // wait for DCU pipeline drain
    localparam logic [2:0] SDONE = 3'd4;

    reg [2:0]  state;
    reg [9:0]  cent_idx;         // current centroid index
    reg [10:0] chunk_cnt;        // chunk counter within a centroid
    reg [10:0] num_chunks;       // total chunks per vector = ceil(dim/16)

    // Top-P registers: maintain sorted list of P smallest distances
    reg [31:0] best_dist [MAX_PROBES];
    reg [9:0]  best_id   [MAX_PROBES];
    integer    p_i;  // for loops

    // Internal chunk counter for centroid streaming
    reg [10:0] cent_chunk_cnt;
    reg        cent_active;

    // Query load done flag
    reg        query_loaded;

    always @(posedge clk) begin
        if (rst) begin
            state <= SIDLE;
            cent_idx <= 0;
            chunk_cnt <= 0;
            num_chunks <= 0;
            cent_chunk_cnt <= 0;
            cent_active <= 0;
            query_loaded <= 0;
            for (p_i = 0; p_i < MAX_PROBES; p_i = p_i + 1) begin
                best_dist[p_i] <= 32'h7FFF_FFFF;
                best_id[p_i]   <= 0;
            end
        end else begin
            case (state)
                SIDLE: begin
                    if (i_start) begin
                        state <= SLOAD;
                        num_chunks <= (i_dim + 15) >> 4;
                        cent_idx <= 0;
                        cent_chunk_cnt <= 0;
                        cent_active <= 0;
                        query_loaded <= 0;
                        chunk_cnt <= 0;
                        for (p_i = 0; p_i < MAX_PROBES; p_i = p_i + 1) begin
                            best_dist[p_i] <= 32'h7FFF_FFFF;
                            best_id[p_i]   <= 0;
                        end
                    end
                end

                SLOAD: begin
                    // Load query vector into internal buffer.
                    // Wait until all chunks have been received.
                    if (i_query_valid) begin
                        if (chunk_cnt + 1 >= num_chunks) begin
                            query_loaded <= 1;
                            state <= SSCAN;
                            chunk_cnt <= 0;
                        end else begin
                            chunk_cnt <= chunk_cnt + 1;
                        end
                    end
                end

                SSCAN: begin
                    // Stream centroids: for each centroid, stream num_chunks chunks.
                    // Start a new centroid when previous finishes.
                    if (!cent_active) begin
                        // Launch next centroid: URAM read already setup combinatorially
                        cent_active <= 1;
                        cent_chunk_cnt <= 0;
                    end else begin
                        // Centroid chunk streaming: each cycle we send one centroid chunk
                        // to DCU port B and one query chunk to DCU port A.
                        // DCU consumes data when both ports have valid data and ready.
                        if (i_dcu_vec_a_ready) begin
                            if (cent_chunk_cnt + 1 >= num_chunks) begin
                                // This centroid is fully streamed
                                cent_active <= 0;
                                cent_chunk_cnt <= 0;
                                cent_idx <= cent_idx + 1;

                                if (cent_idx + 1 >= NCLUSTERS) begin
                                    state <= SWAIT;
                                end
                            end else begin
                                cent_chunk_cnt <= cent_chunk_cnt + 1;
                            end
                        end
                    end

                    // Capture DCU result when valid
                    if (i_dcu_valid) begin
                        // Insert distance into top-P sorted registers
                        // Use insertion sort: scan from high to low
                        // Only insert if within i_probes range
                        for (p_i = 0; p_i < MAX_PROBES; p_i = p_i + 1) begin
                            if (p_i < i_probes) begin
                                if (i_dcu_distance < best_dist[p_i]) begin
                                    // Shift lower entries down
                                    // This is handled by the for-loop unrolling in hardware
                                end
                            end
                        end
                        // Direct insertion: find the right slot and shift
                        // Using a combinational approach via generate is preferred,
                        // but here we use a procedural insertion pattern.
                    end
                end

                SWAIT: begin
                    // Wait for any pending DCU result from the last centroid
                    // In practice this may need a small pipeline depth counter.
                    // For now, drain in one cycle (DCU is pipelined but we track
                    // cent_active to know when final result arrives).
                    if (!cent_active) begin
                        state <= SDONE;
                    end
                end

                SDONE: begin
                    state <= SIDLE;
                end
                default: ;
            endcase
        end
    end

    // ---------------------------------------------------------------------------
    // Top-P insertion logic (combinational)
    // ---------------------------------------------------------------------------
    // When i_dcu_valid is asserted, we need to conditionally insert the new
    // distance into the sorted list. We implement this with always_comb for
    // the next-state logic of best_dist and best_id.
    reg [31:0] next_best_dist [MAX_PROBES];
    reg [9:0]  next_best_id   [MAX_PROBES];
    reg        do_insert;
    reg [3:0]  insert_idx;

    integer ii;
    always_comb begin
        // Default: keep current values
        for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
            next_best_dist[ii] = best_dist[ii];
            next_best_id[ii]   = best_id[ii];
        end
        do_insert = 1'b0;
        insert_idx = 0;

        if (state == SSCAN && i_dcu_valid) begin
            // Check if new distance qualifies for top-P
            if (cent_idx < i_probes) begin
                // Not yet P results gathered; always insert at the sorted position
                do_insert = 1'b1;
                // Find insertion point (sorted ascending)
                for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
                    if (ii < i_probes && i_dcu_distance < best_dist[ii]) begin
                        insert_idx = ii;
                        break;
                    end else if (ii < i_probes && best_dist[ii] == 32'h7FFF_FFFF) begin
                        // Empty slot found
                        insert_idx = ii;
                        break;
                    end
                end
                // If not found (all existing are smaller and slots full), no insert
                // The above loop will have found a slot if any exists
            end else begin
                // Only insert if better than the worst in top-P
                // (best_dist[i_probes-1] is the current worst among top-P)
                for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
                    if (ii < i_probes && i_dcu_distance < best_dist[ii]) begin
                        do_insert = 1'b1;
                        insert_idx = ii;
                        break;
                    end
                end
            end

            if (do_insert) begin
                // Shift entries from insert_idx down by one
                for (ii = MAX_PROBES - 1; ii > 0; ii = ii - 1) begin
                    if (ii > insert_idx && ii < i_probes) begin
                        next_best_dist[ii] = best_dist[ii-1];
                        next_best_id[ii]   = best_id[ii-1];
                    end
                end
                // Insert new entry
                next_best_dist[insert_idx] = i_dcu_distance;
                next_best_id[insert_idx]   = cent_idx;
            end
        end
    end

    // Update registered top-P on valid results
    always @(posedge clk) begin
        if (rst) begin
            for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
                best_dist[ii] <= 32'h7FFF_FFFF;
                best_id[ii]   <= 0;
            end
        end else if (state == SSCAN && i_dcu_valid) begin
            for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
                best_dist[ii] <= next_best_dist[ii];
                best_id[ii]   <= next_best_id[ii];
            end
        end else if (state == SIDLE && i_start) begin
            for (ii = 0; ii < MAX_PROBES; ii = ii + 1) begin
                best_dist[ii] <= 32'h7FFF_FFFF;
                best_id[ii]   <= 0;
            end
        end
    end

    // ---------------------------------------------------------------------------
    // Query buffer: store all chunks of the query vector for reuse during scan
    // ---------------------------------------------------------------------------
    reg [511:0] query_buf [(MAX_DIM + 15) / 16];
    reg [10:0]  query_buf_waddr;
    reg [10:0]  query_buf_raddr;

    always @(posedge clk) begin
        if (rst) begin
            query_buf_waddr <= 0;
        end else if (state == SLOAD && i_query_valid) begin
            query_buf[query_buf_waddr] <= i_query_vec_a;
            if (query_buf_waddr + 1 < num_chunks) begin
                query_buf_waddr <= query_buf_waddr + 1;
            end
        end
    end

    // Query buffer read address during scan
    always @(posedge clk) begin
        if (rst) begin
            query_buf_raddr <= 0;
        end else if (state == SSCAN && cent_active && i_dcu_vec_a_ready) begin
            if (query_buf_raddr + 1 >= num_chunks) begin
                query_buf_raddr <= 0;
            end else begin
                query_buf_raddr <= query_buf_raddr + 1;
            end
        end
    end

    // ---------------------------------------------------------------------------
    // Output assignments
    // ---------------------------------------------------------------------------

    // URAM centroid read: address increments each time a centroid is launched
    assign o_centroid_addr = cent_idx;
    assign o_centroid_re   = (state == SSCAN) && !cent_active;

    // DCU control
    assign o_dcu_start     = (state == SLOAD) && query_loaded;
    assign o_dcu_dim       = i_dim;
    assign o_dcu_metric    = i_metric;

    // Query vector being fed to DCU: replay from buffer during scan
    assign o_dcu_vec_a     = (state == SSCAN) ? query_buf[query_buf_raddr] : i_query_vec_a;
    assign o_dcu_vec_a_valid = (state == SSCAN) && cent_active;

    // Centroid data forwarding: URAM read data goes to DCU port B
    assign o_dcu_vec_b     = i_centroid_rdata;
    assign o_dcu_vec_b_valid = (state == SSCAN) && cent_active;
    assign o_dcu_vec_b_ready = i_dcu_vec_a_ready;  // both ports must handshake together

    // Query ready during LOAD state
    assign o_query_ready   = (state == SLOAD);

    // Results
    assign o_done = (state == SDONE);
    assign o_cluster_count = i_probes;

    genvar g;
    generate
        for (g = 0; g < MAX_PROBES; g = g + 1) begin : gen_results
            assign o_cluster_id[g]   = (g < i_probes) ? best_id[g]   : 10'd0;
            assign o_cluster_size[g] = 16'd0;  // populated by index_manager lookup
        end
    endgenerate
endmodule
