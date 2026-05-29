module index_manager #(
    parameter int NCLUSTERS  = 1024,
    parameter logic [31:0] ZONE_SIZE  = 32'h4000_0000   // 1GB per zone
) (
    input  wire         clk,
    input  wire         rst,

    // Zone control
    input  wire         i_reindex_switch,     // pulse: swap active zone
    output wire         o_active_zone,         // 0=A, 1=B
    output wire [31:0]  o_active_base,         // DDR4 base of active zone

    // Cluster table write (from PC during REINDEX import)
    input  wire         i_cluster_wr_en,
    input  wire [9:0]   i_cluster_wr_idx,      // 0-1023
    input  wire [31:0]  i_cluster_wr_base,
    input  wire [15:0]  i_cluster_wr_size,

    // Cluster table read (for coarse search / scanner)
    input  wire [9:0]   i_cluster_rd_idx,
    output wire [31:0]  o_cluster_rd_base,
    output wire [15:0]  o_cluster_rd_size,

    // INSERT handling
    input  wire         i_insert_req,          // pulse: new vector to store
    input  wire [511:0] i_insert_data,         // vector data (16×Q16.16)
    output wire         o_insert_ready,
    output wire [31:0]  o_insert_wr_addr,      // DDR4 write address
    output wire [31:0]  o_pending_count,       // vectors in standby zone tail

    // INSERT write control (to ddr4_arbiter)
    output wire [511:0] m_insert_wdata,
    output wire         m_insert_wvalid,
    input  wire         m_insert_wready,

    // EXPORT info
    output wire [31:0]  o_export_base,
    output wire [31:0]  o_export_len
);
    // Zone management
    reg active_zone;                          // 0=A, 1=B
    reg [31:0] standby_tail;                  // write pointer in standby zone

    localparam logic [31:0] ZONE_A_BASE = 32'h0000_0000;
    localparam logic [31:0] ZONE_B_BASE = 32'h4000_0000;

    wire [31:0] active_base  = active_zone ? ZONE_B_BASE : ZONE_A_BASE;
    wire [31:0] standby_base = active_zone ? ZONE_A_BASE : ZONE_B_BASE;

    // URAM cluster table: dual-zone, 1024 entries each
    // Simple register-based for now (URAM inference needs explicit attributes)
    reg [31:0] cluster_base_a [NCLUSTERS];
    reg [15:0] cluster_size_a [NCLUSTERS];
    reg [31:0] cluster_base_b [NCLUSTERS];
    reg [15:0] cluster_size_b [NCLUSTERS];

    wire [31:0] wr_base_ptr    = active_zone ? cluster_base_a[i_cluster_wr_idx] : cluster_base_b[i_cluster_wr_idx];
    wire [15:0] wr_size_ptr    = active_zone ? cluster_size_a[i_cluster_wr_idx] : cluster_size_b[i_cluster_wr_idx];

    // Read: always from active zone
    assign o_cluster_rd_base = active_zone ? cluster_base_b[i_cluster_rd_idx] : cluster_base_a[i_cluster_rd_idx];
    assign o_cluster_rd_size = active_zone ? cluster_size_b[i_cluster_rd_idx] : cluster_size_a[i_cluster_rd_idx];

    always @(posedge clk) begin
        if (rst) begin
            active_zone <= 0;
            standby_tail <= ZONE_B_BASE;
        end else begin
            // Cluster table write (goes to STANDBY zone during REINDEX import)
            if (i_cluster_wr_en) begin
                if (active_zone) begin  // writing to B? then standby is A
                    cluster_base_a[i_cluster_wr_idx] <= i_cluster_wr_base;
                    cluster_size_a[i_cluster_wr_idx] <= i_cluster_wr_size;
                end else begin
                    cluster_base_b[i_cluster_wr_idx] <= i_cluster_wr_base;
                    cluster_size_b[i_cluster_wr_idx] <= i_cluster_wr_size;
                end
            end

            // Zone switch: new standby = old active
            if (i_reindex_switch) begin
                active_zone <= ~active_zone;
                standby_tail <= active_zone ? ZONE_B_BASE : ZONE_A_BASE;
            end

            // INSERT: write to standby zone tail, increment
            if (i_insert_req && (standby_tail + 64 < standby_base + ZONE_SIZE)) begin
                standby_tail <= standby_tail + 64;  // 512b = 64 bytes per write
            end
        end
    end

    assign o_active_zone    = active_zone;
    assign o_active_base    = active_base;
    assign o_insert_wr_addr = standby_tail;
    assign o_insert_ready   = (standby_tail + 64 < standby_base + ZONE_SIZE);
    assign o_pending_count  = (standby_tail - standby_base) >> 6;  // /64 bytes per vector

    // INSERT write pass-through
    assign m_insert_wdata   = i_insert_data;
    assign m_insert_wvalid  = i_insert_req && o_insert_ready;

    // EXPORT: export active zone entirely
    assign o_export_base = active_base;
    assign o_export_len  = ZONE_SIZE;
endmodule
