// ddr4_scanner.sv — Fine search: DDR4 sequential scan → DCU → TopK heap
module ddr4_scanner #(
    parameter int MAX_PROBES = 8,
    parameter int MAX_TOPK   = 256,
    parameter int MAX_DIM    = 1536,
    parameter int VEC_BYTES  = 1024    // 256-dim × 4B = 1024B default
) (
    input  wire         clk,
    input  wire         rst,

    // Control
    input  wire         i_start,
    input  wire [10:0]  i_dim,
    input  wire [1:0]   i_metric,
    input  wire [7:0]   i_topk,

    // Cluster list from coarse_search
    input  wire [9:0]   i_cluster_id   [MAX_PROBES],
    input  wire [15:0]  i_cluster_size [MAX_PROBES],
    input  wire [3:0]   i_cluster_count,

    // Cluster base addresses from index_manager
    input  wire [31:0]  i_cluster_base [MAX_PROBES],

    // AXI read (→ ddr4_arbiter)
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    // DCU interface
    output wire         o_dcu_start,
    output wire [10:0]  o_dcu_dim,
    output wire [1:0]   o_dcu_metric,
    output wire [511:0] o_dcu_vec_a,        // query vector for DCU
    output wire         o_dcu_vec_a_valid,
    input  wire         i_dcu_vec_a_ready,

    input  wire [511:0] i_dcu_vec_b,        // unused: DCU reads DDR4 data directly
    output wire         o_dcu_vec_b_valid,
    output wire         o_dcu_vec_b_ready,

    input  wire         i_dcu_valid,
    input  wire [31:0]  i_dcu_distance,

    // TopK heap push
    output wire         o_heap_push,
    output wire [31:0]  o_heap_distance,
    output wire [31:0]  o_heap_vector_id,

    // Done
    output wire         o_done,
    output wire [31:0]  o_vectors_scanned     // diagnostic
);
    localparam logic [2:0] SIDLE      = 3'd0;
    localparam logic [2:0] SNEXTCLUSTER = 3'd1;
    localparam logic [2:0] SSCANVEC  = 3'd2;
    localparam logic [2:0] SDRAIN     = 3'd3;
    localparam logic [2:0] SDONE      = 3'd4;

    reg [2:0]  state;
    reg [3:0]  clu_idx;          // which cluster we're processing
    reg [15:0] vec_in_cluster;   // vector index within current cluster
    reg [31:0] global_vec_id;    // global vector ID counter
    reg [31:0] current_addr;     // current DDR4 read address
    reg [10:0] beat_count;       // beats per vector
    reg [10:0] beats_per_vec;    // ceil(dim/16)
    reg [31:0] vecs_scanned;

    wire [31:0] clu_base = i_cluster_base[clu_idx];
    wire [15:0] clu_size = i_cluster_size[clu_idx];

    always @(posedge clk) begin
        if (rst) begin
            state <= SIDLE;
            clu_idx <= 0;
            vec_in_cluster <= 0;
            global_vec_id <= 0;
            current_addr <= 0;
            beat_count <= 0;
            vecs_scanned <= 0;
        end else begin
            case (state)
                SIDLE: begin
                    if (i_start) begin
                        state <= SNEXTCLUSTER;
                        clu_idx <= 0;
                        vec_in_cluster <= 0;
                        global_vec_id <= 0;
                        beats_per_vec <= (i_dim + 15) >> 4;
                        vecs_scanned <= 0;
                    end
                end

                SNEXTCLUSTER: begin
                    if (clu_idx < i_cluster_count && clu_size > 0) begin
                        current_addr <= clu_base;
                        vec_in_cluster <= 0;
                        state <= SSCANVEC;
                    end else if (clu_idx >= i_cluster_count) begin
                        state <= SDRAIN;
                    end else begin
                        clu_idx <= clu_idx + 1;
                    end
                end

                SSCANVEC: begin
                    // Stream vector data from DDR4 to DCU
                    // 1 vector = beats_per_vec beats of 512b (64B) each
                    if (m_axi_rvalid && m_axi_rready) begin
                        beat_count <= beat_count + 1;

                        if (beat_count + 1 >= beats_per_vec) begin
                            // Done with this vector
                            vec_in_cluster <= vec_in_cluster + 1;
                            global_vec_id <= global_vec_id + 1;
                            vecs_scanned <= vecs_scanned + 1;
                            beat_count <= 0;
                            current_addr <= current_addr + (beats_per_vec << 6);

                            if (vec_in_cluster + 1 >= clu_size) begin
                                clu_idx <= clu_idx + 1;
                                state <= SNEXTCLUSTER;
                            end
                        end
                    end
                end

                SDRAIN: begin
                    // Wait for DCU pipeline + heap sift-downs
                    state <= SDONE;
                end

                SDONE: state <= SIDLE;
                default: ;
            endcase
        end
    end

    // AXI read: sequential burst from current DDR4 address
    assign m_axi_araddr  = current_addr;
    assign m_axi_arvalid = (state == SSCANVEC);
    assign m_axi_rready  = (state == SSCANVEC);

    // DCU: query vector side (preloaded by cmd_dispatcher into DCU buffer)
    // For now: query vector is loaded externally via o_dcu_start pulsed once
    assign o_dcu_start  = (state == SNEXTCLUSTER) && (clu_idx == 0);
    assign o_dcu_dim    = i_dim;
    assign o_dcu_metric = i_metric;

    // DCU vec_b: DDR4 data goes straight to DCU
    assign o_dcu_vec_b_valid = m_axi_rvalid && (state == SSCANVEC);
    assign o_dcu_vec_b_ready = 1'b1;
    assign o_dcu_vec_a_valid = 1'b0;  // query preloaded externally
    assign o_dcu_vec_a       = 512'd0;

    // Heap push
    assign o_heap_push    = i_dcu_valid;
    assign o_heap_distance = i_dcu_distance;
    assign o_heap_vector_id = global_vec_id;

    assign o_done = (state == SDONE);
    assign o_vectors_scanned = vecs_scanned;
endmodule
