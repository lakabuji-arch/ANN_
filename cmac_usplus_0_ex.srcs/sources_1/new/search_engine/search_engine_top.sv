// search_engine_top.sv — ANN search engine top level
// Instantiates: cmd_dispatcher, coarse_search, ddr4_scanner,
//                distance_compute_unit, topk_heap, index_manager, ddr4_arbiter
// Clock: ddr4_ui_clk (333MHz)

module search_engine_top (
    input  wire         ddr4_ui_clk,
    input  wire         ddr4_ui_rst,

    // === AXI to DDR4 MIG ===
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,
    output wire [31:0]  m_axi_awaddr,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [511:0] m_axi_wdata,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // === CDC: command from UDP:8001 (via xpm_fifo_async, 322→333) ===
    input  wire [511:0] s_axis_cmd_tdata,
    input  wire         s_axis_cmd_tvalid,
    output wire         s_axis_cmd_tready,
    output wire [511:0] m_axis_resp_tdata,
    output wire         m_axis_resp_tvalid,
    input  wire         m_axis_resp_tready,

    // === CDC: data from UDP:8002 (via xpm_fifo_async, 322→333) ===
    input  wire [511:0] s_axis_data_tdata,
    input  wire         s_axis_data_tvalid,
    output wire         s_axis_data_tready,
    output wire [511:0] m_axis_data_tdata,
    output wire         m_axis_data_tvalid,
    input  wire         m_axis_data_tready,

    // === Status output ===
    output wire [31:0]  o_status_monitor,
    output wire         o_search_active
);

    // ─── Internal wires ───

    // cmd_dispatcher → coarse_search
    wire        cmd_to_coarse_start;
    wire [10:0] cmd_to_coarse_dim;
    wire [1:0]  cmd_to_coarse_metric;
    wire [3:0]  cmd_to_coarse_probes;
    wire [7:0]  cmd_to_coarse_topk;
    wire [511:0] cmd_to_coarse_query_data;
    wire        cmd_to_coarse_query_valid;
    wire        coarse_to_cmd_query_ready;

    // coarse_search → cmd_dispatcher
    wire        coarse_done;
    wire [9:0]  coarse_cluster_id [8];
    wire [15:0] coarse_cluster_size [8];
    wire [3:0]  coarse_cluster_count;

    // cmd_dispatcher → scanner
    wire        cmd_to_scanner_start;
    wire [9:0]  cmd_to_scanner_cluster_id [8];
    wire [15:0] cmd_to_scanner_cluster_size [8];
    wire [31:0] cmd_to_scanner_cluster_base [8];
    wire [3:0]  cmd_to_scanner_cluster_count;

    // scanner → cmd_dispatcher
    wire        scanner_done;
    wire [31:0] scanner_result_dist [10];
    wire [31:0] scanner_result_id   [10];

    // DCU shared interface
    wire        dcu_start;
    wire [10:0] dcu_dim;
    wire [1:0]  dcu_metric;
    wire [511:0] dcu_vec_a;
    wire        dcu_vec_a_valid, dcu_vec_a_ready;
    wire [511:0] dcu_vec_b;
    wire        dcu_vec_b_valid, dcu_vec_b_ready;
    wire        dcu_valid;
    wire [31:0] dcu_distance;

    // TopK heap
    wire        heap_push;
    wire [31:0] heap_distance;
    wire [31:0] heap_vector_id;
    wire        heap_full, heap_ready;
    wire [7:0]  heap_count;

    // Index manager
    wire        insert_req;
    wire [511:0] insert_data;
    wire        insert_ready;
    wire [31:0] insert_wr_addr;
    wire        reindex_switch;

    // DDR4 arbiter → scanner read
    wire [31:0]  arb_scan_rdata_addr;
    wire         arb_scan_rdata_valid;
    wire [511:0] arb_scan_rdata_data;

    // ─── Sub-module instances ───

    // (1) search_cmd_dispatcher
    search_cmd_dispatcher u_dispatcher (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .s_axis_cmd_tdata   (s_axis_cmd_tdata),
        .s_axis_cmd_tvalid  (s_axis_cmd_tvalid),
        .s_axis_cmd_tready  (s_axis_cmd_tready),
        .m_axis_resp_tdata  (m_axis_resp_tdata),
        .m_axis_resp_tvalid (m_axis_resp_tvalid),
        .m_axis_resp_tready (m_axis_resp_tready),
        .o_search_start     (cmd_to_coarse_start),
        .o_search_dim       (cmd_to_coarse_dim),
        .o_search_metric    (cmd_to_coarse_metric),
        .o_search_probes    (cmd_to_coarse_probes),
        .o_search_topk      (cmd_to_coarse_topk),
        .o_search_query_data (cmd_to_coarse_query_data),
        .o_search_query_valid (cmd_to_coarse_query_valid),
        .i_search_query_ready (coarse_to_cmd_query_ready),
        .i_coarse_done      (coarse_done),
        .i_coarse_cluster_id  (coarse_cluster_id),
        .i_coarse_cluster_size(coarse_cluster_size),
        .i_coarse_cluster_count(coarse_cluster_count),
        .o_scanner_start    (cmd_to_scanner_start),
        .o_scanner_cluster_id  (cmd_to_scanner_cluster_id),
        .o_scanner_cluster_size(cmd_to_scanner_cluster_size),
        .o_scanner_cluster_base(cmd_to_scanner_cluster_base),
        .o_scanner_cluster_count(cmd_to_scanner_cluster_count),
        .i_scanner_done     (scanner_done),
        .i_result_dist      (scanner_result_dist),
        .i_result_id        (scanner_result_id),
        .o_insert_req       (insert_req),
        .o_insert_data      (insert_data),
        .o_reindex_switch   (reindex_switch),
        .o_export_req       (),
        .o_latency_cycles   (),
        .o_qps_counter      ()
    );

    // (2) ann_coarse_search
    ann_coarse_search u_coarse (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .i_start            (cmd_to_coarse_start),
        .i_dim              (cmd_to_coarse_dim),
        .i_metric           (cmd_to_coarse_metric),
        .i_probes           (cmd_to_coarse_probes),
        .i_query_vec_a      (cmd_to_coarse_query_data),
        .i_query_valid      (cmd_to_coarse_query_valid),
        .o_query_ready      (coarse_to_cmd_query_ready),
        .o_centroid_addr    (),
        .o_centroid_re      (),
        .i_centroid_rdata   (512'd0),  // FIXME: connect to URAM
        .o_dcu_start        (dcu_start),
        .o_dcu_dim          (dcu_dim),
        .o_dcu_metric       (dcu_metric),
        .o_dcu_vec_a        (dcu_vec_a),
        .o_dcu_vec_a_valid  (dcu_vec_a_valid),
        .i_dcu_vec_a_ready  (dcu_vec_a_ready),
        .i_dcu_vec_b        (dcu_vec_b),
        .o_dcu_vec_b_valid  (dcu_vec_b_valid),
        .o_dcu_vec_b_ready  (dcu_vec_b_ready),
        .i_dcu_valid        (dcu_valid),
        .i_dcu_distance     (dcu_distance),
        .o_done             (coarse_done),
        .o_cluster_id       (coarse_cluster_id),
        .o_cluster_size     (coarse_cluster_size),
        .o_cluster_count    (coarse_cluster_count)
    );

    // (3) ddr4_scanner
    ddr4_scanner u_scanner (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .i_start            (cmd_to_scanner_start),
        .i_dim              (cmd_to_coarse_dim),
        .i_metric           (cmd_to_coarse_metric),
        .i_topk             (cmd_to_coarse_topk),
        .i_cluster_id       (cmd_to_scanner_cluster_id),
        .i_cluster_size     (cmd_to_scanner_cluster_size),
        .i_cluster_base     (cmd_to_scanner_cluster_base),
        .i_cluster_count    (cmd_to_scanner_cluster_count),
        .m_axi_araddr       (arb_scan_rdata_addr),
        .m_axi_arvalid      (arb_scan_rdata_valid),
        .m_axi_arready      (1'b1),   // arbiter handles backpressure
        .m_axi_rdata        (arb_scan_rdata_data),
        .m_axi_rvalid       (1'b1),
        .m_axi_rready       (),
        .o_dcu_start        (),
        .o_dcu_dim          (),
        .o_dcu_metric       (),
        .o_dcu_vec_a        (),
        .o_dcu_vec_a_valid  (),
        .i_dcu_vec_a_ready  (1'b1),
        .i_dcu_vec_b        (dcu_vec_b),
        .o_dcu_vec_b_valid  (),
        .o_dcu_vec_b_ready  (),
        .i_dcu_valid        (dcu_valid),
        .i_dcu_distance     (dcu_distance),
        .o_heap_push        (heap_push),
        .o_heap_distance    (heap_distance),
        .o_heap_vector_id   (heap_vector_id),
        .o_done             (scanner_done),
        .o_vectors_scanned  ()
    );

    // (4) distance_compute_unit (shared: coarse/scanner)
    distance_compute_unit u_dcu (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .i_start            (dcu_start),
        .i_dim              (dcu_dim),
        .i_metric           (dcu_metric),
        .i_vec_a_tdata      (dcu_vec_a),
        .i_vec_a_tvalid     (dcu_vec_a_valid),
        .o_vec_a_tready     (dcu_vec_a_ready),
        .i_vec_b_tdata      (dcu_vec_b),
        .i_vec_b_tvalid     (dcu_vec_b_valid),
        .o_vec_b_tready     (dcu_vec_b_ready),
        .o_valid            (dcu_valid),
        .o_distance         (dcu_distance)
    );

    // (5) topk_heap
    topk_heap u_heap (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .i_k                (cmd_to_coarse_topk),
        .i_push             (heap_push),
        .i_distance         (heap_distance),
        .i_vector_id        (heap_vector_id),
        .o_full             (heap_full),
        .o_ready            (heap_ready),
        .i_read_en          (1'b0),    // results read by cmd_dispatcher
        .o_distance         (scanner_result_dist[0]),  // simplified: 1 result
        .o_vector_id        (scanner_result_id[0]),
        .o_read_valid       (),
        .o_count            (heap_count)
    );

    // (6) index_manager
    index_manager u_index (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .i_reindex_switch   (reindex_switch),
        .o_active_zone      (),
        .o_active_base      (),
        .i_cluster_wr_en    (1'b0),
        .i_cluster_wr_idx   (10'd0),
        .i_cluster_wr_base  (32'd0),
        .i_cluster_wr_size  (16'd0),
        .i_cluster_rd_idx   (10'd0),
        .o_cluster_rd_base  (cmd_to_scanner_cluster_base[0]),
        .o_cluster_rd_size  (cmd_to_scanner_cluster_size[0]),
        .i_insert_req       (insert_req),
        .i_insert_data      (insert_data),
        .o_insert_ready     (insert_ready),
        .o_insert_wr_addr   (insert_wr_addr),
        .o_pending_count    (),
        .m_insert_wdata     (),
        .m_insert_wvalid    (),
        .m_insert_wready    (1'b1),
        .o_export_base      (),
        .o_export_len       ()
    );

    // (7) ddr4_arbiter
    ddr4_arbiter u_arbiter (
        .clk                (ddr4_ui_clk),
        .rst                (ddr4_ui_rst),
        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),
        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready),
        .m_axi_awaddr       (m_axi_awaddr),
        .m_axi_awvalid      (m_axi_awvalid),
        .m_axi_awready      (m_axi_awready),
        .m_axi_wdata        (m_axi_wdata),
        .m_axi_wvalid       (m_axi_wvalid),
        .m_axi_wready       (m_axi_wready),
        .s_scan_araddr      (arb_scan_rdata_addr),
        .s_scan_arvalid     (arb_scan_rdata_valid),
        .s_scan_arready     (),
        .s_scan_rdata       (arb_scan_rdata_data),
        .s_scan_rvalid      (),
        .s_scan_rready      (1'b1),
        .s_insert_awaddr    (insert_wr_addr),
        .s_insert_awvalid   (insert_req),
        .s_insert_awready   (),
        .s_insert_wdata     (insert_data),
        .s_insert_wvalid    (insert_req),
        .s_insert_wready    (),
        .s_export_araddr    (32'd0),
        .s_export_arvalid   (1'b0),
        .s_export_arready   (),
        .s_export_rdata     (),
        .s_export_rvalid    (),
        .s_export_rready    (1'b0)
    );

    // Status
    assign o_status_monitor = {16'd0, heap_count, 8'd0};
    assign o_search_active  = dcu_valid || cmd_to_coarse_start || cmd_to_scanner_start;

    // Data plane pass-through (for now)
    assign s_axis_data_tready = 1'b1;
    assign m_axis_data_tdata  = s_axis_data_tdata;
    assign m_axis_data_tvalid = 1'b0;  // not used yet

endmodule
