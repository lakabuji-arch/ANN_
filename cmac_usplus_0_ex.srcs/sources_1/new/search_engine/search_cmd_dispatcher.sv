module search_cmd_dispatcher #(
    parameter int MAX_DIM = 1536,
    parameter int MAX_TOPK = 256
) (
    input  wire         clk,
    input  wire         rst,

    // CDC side: from UDP:8001 via xpm_fifo_async
    input  wire [511:0] s_axis_cmd_tdata,
    input  wire         s_axis_cmd_tvalid,
    output wire         s_axis_cmd_tready,

    // CDC side: response to UDP:8001
    output wire [511:0] m_axis_resp_tdata,
    output wire         m_axis_resp_tvalid,
    input  wire         m_axis_resp_tready,

    // → ann_coarse_search
    output wire         o_search_start,
    output wire [10:0]  o_search_dim,
    output wire [1:0]   o_search_metric,
    output wire [3:0]   o_search_probes,
    output wire [7:0]   o_search_topk,
    output wire [511:0] o_search_query_data,
    output wire         o_search_query_valid,
    input  wire         i_search_query_ready,

    // ← coarse_search results (cluster IDs)
    input  wire         i_coarse_done,
    input  wire [9:0]   i_coarse_cluster_id [8],
    input  wire [15:0]  i_coarse_cluster_size [8],
    input  wire [3:0]   i_coarse_cluster_count,

    // → ddr4_scanner
    output wire         o_scanner_start,
    output wire [9:0]   o_scanner_cluster_id [8],
    output wire [15:0]  o_scanner_cluster_size [8],
    output wire [31:0]  o_scanner_cluster_base [8],
    output wire [3:0]   o_scanner_cluster_count,

    // ← scanner results
    input  wire         i_scanner_done,
    input  wire [31:0]  i_result_dist [10],
    input  wire [31:0]  i_result_id   [10],

    // → index_manager
    output wire         o_insert_req,
    output wire [511:0] o_insert_data,
    output wire         o_reindex_switch,
    output wire         o_export_req,

    // Status
    output wire [31:0]  o_latency_cycles,
    output wire [31:0]  o_qps_counter
);
    localparam logic [3:0] SIDLE    = 4'd0;
    localparam logic [3:0] SPARSE   = 4'd1;
    localparam logic [3:0] SSEARCH  = 4'd2;   // orchestrating SEARCH
    localparam logic [3:0] SINSERT  = 4'd3;
    localparam logic [3:0] SREINDEX = 4'd4;
    localparam logic [3:0] SSTATUS  = 4'd5;
    localparam logic [3:0] SRESP    = 4'd6;   // sending response
    localparam logic [3:0] SWAITCOARSE  = 4'd7;
    localparam logic [3:0] SWAITSCANNER = 4'd8;

    reg [3:0]  state;
    reg [7:0]  cmd_code;
    reg [15:0] seq_num;
    reg [10:0] search_dim;
    reg [1:0]  search_metric;
    reg [3:0]  search_probes;
    reg [7:0]  search_topk;

    // Query buffer: store up to 1536-dim = 96 beats of 16 floats
    reg [511:0] query_buffer [96];
    reg [6:0]   query_chunks;
    reg [6:0]   query_idx;

    // Latency measurement
    reg [31:0] search_start_cycle;
    reg [31:0] search_latency;
    reg [31:0] cycle_ctr;
    reg [31:0] qps_ctr;

    // Response buffer
    reg [511:0] resp_data;
    reg         resp_valid;

    // Header parsing
    wire [7:0]  pkt_cmd    = s_axis_cmd_tdata[7:0];
    wire [7:0]  pkt_flags  = s_axis_cmd_tdata[15:8];
    wire [15:0] pkt_seq    = s_axis_cmd_tdata[31:16];
    wire [31:0] pkt_len    = {s_axis_cmd_tdata[39:32], s_axis_cmd_tdata[47:40],
                              s_axis_cmd_tdata[55:48], s_axis_cmd_tdata[63:56]};
    wire [15:0] payload_dim    = {s_axis_cmd_tdata[71:64], s_axis_cmd_tdata[79:72]};
    wire [7:0]  payload_metric = s_axis_cmd_tdata[87:80];
    wire [7:0]  payload_topk   = s_axis_cmd_tdata[95:88];

    always @(posedge clk) begin
        if (rst) begin
            state <= SIDLE;
            cycle_ctr <= 0;
            qps_ctr <= 0;
            search_start_cycle <= 0;
            search_latency <= 0;
        end else begin
            cycle_ctr <= cycle_ctr + 1;

            case (state)
                SIDLE: begin
                    if (s_axis_cmd_tvalid) begin
                        cmd_code <= pkt_cmd;
                        seq_num  <= pkt_seq;
                        state <= SPARSE;
                    end
                end

                SPARSE: begin
                    case (pkt_cmd)
                        8'h01: begin  // SEARCH
                            search_dim    <= payload_dim[10:0];
                            search_metric <= payload_metric[1:0];
                            search_topk   <= payload_topk;
                            search_probes <= 2;  // default nprobe=2
                            search_start_cycle <= cycle_ctr;
                            state <= SSEARCH;
                        end
                        8'h02: begin  // INSERT
                            state <= SINSERT;
                        end
                        8'h04: begin  // REINDEX
                            state <= SREINDEX;
                        end
                        8'h06: begin  // GET_STATUS
                            state <= SSTATUS;
                        end
                        default: state <= SRESP;
                    endcase
                end

                SSEARCH: begin
                    if (i_coarse_done) begin
                        // Route coarse results to scanner
                        state <= SWAITSCANNER;
                    end
                end

                SWAITSCANNER: begin
                    if (i_scanner_done) begin
                        search_latency <= cycle_ctr - search_start_cycle;
                        qps_ctr <= qps_ctr + 1;
                        state <= SRESP;
                    end
                end

                SRESP: begin
                    if (m_axis_resp_tready) begin
                        resp_valid <= 0;
                        state <= SIDLE;
                    end
                end

                default: state <= SIDLE;
            endcase
        end
    end

    // Output assignments
    assign s_axis_cmd_tready = (state == SIDLE);

    assign o_search_start  = (state == SSEARCH);
    assign o_search_dim    = search_dim;
    assign o_search_metric = search_metric;
    assign o_search_probes = search_probes;
    assign o_search_topk   = search_topk;

    assign o_scanner_start = (state == SWAITCOARSE) && i_coarse_done;
    assign o_scanner_cluster_id   = i_coarse_cluster_id;   // pass through
    assign o_scanner_cluster_size = i_coarse_cluster_size;
    assign o_scanner_cluster_count = i_coarse_cluster_count;

    assign o_reindex_switch = (state == SREINDEX);
    assign o_insert_req     = (state == SINSERT) && s_axis_cmd_tvalid;

    assign o_latency_cycles = search_latency;
    assign o_qps_counter    = qps_ctr;

    // Response packing (simplified)
    assign m_axis_resp_tdata  = {504'd0, seq_num, cmd_code | 8'h80};  // ACK
    assign m_axis_resp_tvalid = (state == SRESP);
endmodule
