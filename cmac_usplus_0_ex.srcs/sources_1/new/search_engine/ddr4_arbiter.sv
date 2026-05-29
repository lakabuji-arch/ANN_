// ddr4_arbiter.sv — DDR4 AXI 读写仲裁
// 三端口: 搜索扫描读(最高优先), INSERT写, EXPORT读(最低)
// 读写通道独立: 读不会阻塞写, 写不会阻塞读
module ddr4_arbiter (
    input  wire         clk,
    input  wire         rst,

    // === AXI to MIG ===
    // Read Address
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    // Read Data
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,
    // Write Address
    output wire [31:0]  m_axi_awaddr,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    // Write Data
    output wire [511:0] m_axi_wdata,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // === Scanner read (priority 0: highest) ===
    input  wire [31:0]  s_scan_araddr,
    input  wire         s_scan_arvalid,
    output wire         s_scan_arready,
    output wire [511:0] s_scan_rdata,
    output wire         s_scan_rvalid,
    input  wire         s_scan_rready,

    // === INSERT write (priority 1) ===
    input  wire [31:0]  s_insert_awaddr,
    input  wire         s_insert_awvalid,
    output wire         s_insert_awready,
    input  wire [511:0] s_insert_wdata,
    input  wire         s_insert_wvalid,
    output wire         s_insert_wready,

    // === EXPORT read (priority 2: lowest) ===
    input  wire [31:0]  s_export_araddr,
    input  wire         s_export_arvalid,
    output wire         s_export_arready,
    output wire [511:0] s_export_rdata,
    output wire         s_export_rvalid,
    input  wire         s_export_rready
);

    // ─── Read channel arbitration: scanner > export ───
    // Track which port owns the current read burst
    reg read_is_scan;

    assign m_axi_araddr  = s_scan_arvalid ? s_scan_araddr  : s_export_araddr;
    assign m_axi_arvalid = s_scan_arvalid | s_export_arvalid;
    assign s_scan_arready   = m_axi_arready &&  s_scan_arvalid;
    assign s_export_arready = m_axi_arready && !s_scan_arvalid && s_export_arvalid;

    // Track burst ownership
    always @(posedge clk) begin
        if (rst)
            read_is_scan <= 0;
        else if (m_axi_arvalid && m_axi_arready)
            read_is_scan <= s_scan_arvalid;
    end

    // Route read data back to the correct port
    assign s_scan_rdata   = m_axi_rdata;
    assign s_export_rdata = m_axi_rdata;

    assign s_scan_rvalid   = m_axi_rvalid &&  read_is_scan;
    assign s_export_rvalid = m_axi_rvalid && !read_is_scan;

    assign m_axi_rready = read_is_scan ? s_scan_rready : s_export_rready;

    // ─── Write channel: INSERT only ───
    assign m_axi_awaddr   = s_insert_awaddr;
    assign m_axi_awvalid  = s_insert_awvalid;
    assign s_insert_awready = m_axi_awready;

    assign m_axi_wdata    = s_insert_wdata;
    assign m_axi_wvalid   = s_insert_wvalid;
    assign s_insert_wready = m_axi_wready;

endmodule
