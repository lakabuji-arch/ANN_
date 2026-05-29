`timescale 1ns / 1ps

module ddr4_subsystem_top (
    // 时钟 & 复位
    input  wire         usr_mac_clk,
    input  wire         usr_mac_rst_n,
    output wire         c0_ddr4_ui_clk,
    input  wire         sys_rst,
    input  wire         dm_rst_n,               // DDR4域复位 (来自顶层，等calib+locked+1s延时后释放)
    output wire         c0_init_calib_complete, // DDR4校准完成

    // DDR4 参考时钟
    input  wire         diff_clock_rtl_0_clk_p,
    input  wire         diff_clock_rtl_0_clk_n,

    // DDR4 物理接口
    output wire         ddr4_rtl_0_act_n,
    output wire [16:0]  ddr4_rtl_0_adr,
    output wire [1:0]   ddr4_rtl_0_ba,
    output wire [0:0]   ddr4_rtl_0_bg,
    output wire [0:0]   ddr4_rtl_0_ck_c,
    output wire [0:0]   ddr4_rtl_0_ck_t,
    output wire [0:0]   ddr4_rtl_0_cke,
    output wire [0:0]   ddr4_rtl_0_cs_n,
    inout  wire [3:0]   ddr4_rtl_0_dm_n,
    inout  wire [31:0]  ddr4_rtl_0_dq,
    inout  wire [3:0]   ddr4_rtl_0_dqs_c,
    inout  wire [3:0]   ddr4_rtl_0_dqs_t,
    output wire [0:0]   ddr4_rtl_0_odt,
    output wire         ddr4_rtl_0_reset_n,

    // UDP:8001 control plane (rx_demux Ch3), usr_mac_clk domain
    output wire [511:0] M_AXIS_CH3_tdata,
    output wire [63:0]  M_AXIS_CH3_tkeep,
    output wire         M_AXIS_CH3_tvalid,
    output wire         M_AXIS_CH3_tlast,
    input  wire         M_AXIS_CH3_tready,

    // UDP:8002 data plane (rx_demux Ch4), usr_mac_clk domain
    output wire [511:0] M_AXIS_CH4_tdata,
    output wire [63:0]  M_AXIS_CH4_tkeep,
    output wire         M_AXIS_CH4_tvalid,
    output wire         M_AXIS_CH4_tlast,
    input  wire         M_AXIS_CH4_tready,

    // AXI4 for search_engine_top (c0_ddr4_ui_clk domain)
    input  wire [31:0]  S_AXI_SEARCH_araddr,
    input  wire         S_AXI_SEARCH_arvalid,
    output wire         S_AXI_SEARCH_arready,
    output wire [511:0] S_AXI_SEARCH_rdata,
    output wire         S_AXI_SEARCH_rvalid,
    input  wire         S_AXI_SEARCH_rready,
    input  wire [31:0]  S_AXI_SEARCH_awaddr,
    input  wire         S_AXI_SEARCH_awvalid,
    output wire         S_AXI_SEARCH_awready,
    input  wire [511:0] S_AXI_SEARCH_wdata,
    input  wire         S_AXI_SEARCH_wvalid,
    output wire         S_AXI_SEARCH_wready,
    // Write Response
    output wire [1:0]   S_AXI_SEARCH_bresp,
    output wire         S_AXI_SEARCH_bvalid,
    input  wire         S_AXI_SEARCH_bready,
    // Read Response
    output wire [1:0]   S_AXI_SEARCH_rresp,
    input  wire [31:0]  S_AXI_SEARCH_aruser,
    input  wire [31:0]  S_AXI_SEARCH_awuser,

    // AXI-Stream RX (来自CMAC, usr_mac_clk域)
    input  wire [511:0] S_AXIS_RX_tdata,
    input  wire [63:0]  S_AXIS_RX_tkeep,
    input  wire         S_AXIS_RX_tvalid,
    input  wire         S_AXIS_RX_tlast,
    output wire         S_AXIS_RX_tready,

    // AXI-Stream TX (送往CMAC, usr_mac_clk域)
    output wire [511:0] M_AXIS_TX_tdata,
    output wire [63:0]  M_AXIS_TX_tkeep,
    output wire         M_AXIS_TX_tvalid,
    output wire         M_AXIS_TX_tlast,
    input  wire         M_AXIS_TX_tready,

    // S2MM 命令 (c0_ddr4_ui_clk域, BD直通)
    input  wire [71:0]  S_AXIS_S2MM_CMD_0_tdata,
    input  wire         S_AXIS_S2MM_CMD_0_tvalid,
    output wire         S_AXIS_S2MM_CMD_0_tready,

    // S2MM 状态 (c0_ddr4_ui_clk域, BD直通)
    output wire [7:0]   M_AXIS_S2MM_STS_0_tdata,
    output wire         M_AXIS_S2MM_STS_0_tvalid,
    input  wire         M_AXIS_S2MM_STS_0_tready,

    // MM2S 命令 (c0_ddr4_ui_clk域, BD直通)
    input  wire [71:0]  S_AXIS_MM2S_CMD_0_tdata,
    input  wire         S_AXIS_MM2S_CMD_0_tvalid,
    output wire         S_AXIS_MM2S_CMD_0_tready,

    // MM2S 状态 (c0_ddr4_ui_clk域, BD直通)
    output wire [7:0]   M_AXIS_MM2S_STS_0_tdata,
    output wire         M_AXIS_MM2S_STS_0_tvalid,
    input  wire         M_AXIS_MM2S_STS_0_tready,

    // 错误输出
    output wire         s2mm_err_0,
    output wire         mm2s_err_0,

    // CDC FIFO 诊断
    output wire [11:0]  rx_cdc_wr_count,
    output wire [11:0]  tx_cdc_wr_count,
    output wire         rx_fifo_full
);

    // =========================================================================
    // 复位同步: sys_rst → usr_mac_clk 域
    // =========================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] usr_rst_sync_ff = 3'b111;
    always_ff @(posedge usr_mac_clk) begin
        usr_rst_sync_ff <= {usr_rst_sync_ff[1:0], sys_rst};
    end
    wire usr_mac_rst_n_sync = ~usr_rst_sync_ff[2];
    // 使用本地 3-FF 同步后的复位，与 RX CDC FIFO 一致，避免 TX/RX 复位时序偏差
    wire tx_path_rst_n = dm_rst_n & usr_mac_rst_n_sync;

    // =========================================================================
    // CDC FIFO 中间信号
    // =========================================================================
    // RX 侧: usr_mac_clk → c0_ddr4_ui_clk
    wire [576:0] rx_dout;
    wire         rx_fifo_empty;
    wire         bd_s2mm_tvalid, bd_s2mm_tready;
    wire         bd_s2mm_tlast;
    wire [63:0]  bd_s2mm_tkeep;
    wire [511:0] bd_s2mm_tdata;

    // TX 侧: c0_ddr4_ui_clk → usr_mac_clk
    wire bd_mm2s_tvalid;
    wire bd_mm2s_tlast;
    wire         bd_mm2s_tready;
    wire [63:0]  bd_mm2s_tkeep;
    wire [511:0] bd_mm2s_tdata;

    // =========================================================================
    // RX CDC FIFO: usr_mac_clk(322MHz) → c0_ddr4_ui_clk(333MHz)
    // 577bit = {tlast[0], tkeep[63:0], tdata[511:0]}
    // =========================================================================
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (4096),
        .READ_MODE           ("fwft"),
        .WRITE_DATA_WIDTH    (577),
        .READ_DATA_WIDTH     (577),
        .CDC_SYNC_STAGES     (3),
        .WR_DATA_COUNT_WIDTH (12),
        .RD_DATA_COUNT_WIDTH (12),
        .RELATED_CLOCKS      (0)
    ) u_rx_cdc_fifo (
        .rst           (~usr_mac_rst_n_sync),
        .wr_clk        (usr_mac_clk),
        .wr_en         (S_AXIS_RX_tvalid && S_AXIS_RX_tready),
        .din           ({S_AXIS_RX_tlast, S_AXIS_RX_tkeep, S_AXIS_RX_tdata}),
        .full          (rx_fifo_full),
        .almost_full   (),
        .wr_data_count (rx_cdc_wr_count),
        .rd_clk        (c0_ddr4_ui_clk),
        .rd_en         (bd_s2mm_tready && bd_s2mm_tvalid),
        .dout          (rx_dout),
        .empty         (rx_fifo_empty),
        .almost_empty  (),
        .rd_data_count (),
        .sleep         (1'b0)
    );

    assign S_AXIS_RX_tready = !rx_fifo_full;
    assign bd_s2mm_tvalid   = !rx_fifo_empty;
    assign bd_s2mm_tlast    = rx_dout[576];
    assign bd_s2mm_tkeep    = rx_dout[575:512];
    assign bd_s2mm_tdata    = rx_dout[511:0];

    // =========================================================================
    // TX 整包缓冲 + CDC: c0_ddr4_ui_clk(333MHz) → usr_mac_clk(322MHz)
    //
    // 使用 xpm_fifo_axis 的 Packet Mode (PACKET_FIFO="true"):
    //   写侧持续接收 DataMover 吐出的数据（允许含 DDR4 唤醒气泡），
    //   读侧仅在收齐完整的一包 (tlast) 之后才拉高 tvalid，连续无间断
    //   吐出给下游 Framer/CMAC，从根本上杜绝 CMAC TX Underflow。
    //
    // 深度 4096→2048→1024: 每减半一次 BRAM 数量减半, 扇出减半。
    //   1024×64B=64KB 缓冲（~192μs @333MHz, 对 DDR4 回放足够）。
    //   收敛 txoutclk_out[0] (322MHz) 域最后 1 条 -0.020ns 违例。
    // =========================================================================
    wire [10:0] tx_axis_wr_cnt;
    assign tx_cdc_wr_count = {1'b0, tx_axis_wr_cnt[10:0]};

    xpm_fifo_axis #(
        .CDC_SYNC_STAGES     (3),
        .CLOCKING_MODE       ("independent_clock"),
        .FIFO_DEPTH          (1024),
        .FIFO_MEMORY_TYPE    ("block"),
        .PACKET_FIFO         ("true"),
        .TDATA_WIDTH         (512),
        .TUSER_WIDTH         (1),
        .TID_WIDTH           (1),
        .TDEST_WIDTH         (1),
        .WR_DATA_COUNT_WIDTH (11),
        .RD_DATA_COUNT_WIDTH (11)
    ) u_tx_cdc_fifo (
        .s_aresetn      (tx_path_rst_n),
        .s_aclk         (c0_ddr4_ui_clk),
        .s_axis_tvalid  (bd_mm2s_tvalid),
        .s_axis_tready  (bd_mm2s_tready),
        .s_axis_tdata   (bd_mm2s_tdata),
        .s_axis_tkeep   (bd_mm2s_tkeep),
        .s_axis_tlast   (bd_mm2s_tlast),
        .s_axis_tstrb   ({64{1'b1}}),
        .s_axis_tuser   (1'b0),
        .s_axis_tid     (1'b0),
        .s_axis_tdest   (1'b0),

        .m_aclk         (usr_mac_clk),
        .m_axis_tvalid  (M_AXIS_TX_tvalid),
        .m_axis_tready  (M_AXIS_TX_tready),
        .m_axis_tdata   (M_AXIS_TX_tdata),
        .m_axis_tkeep   (M_AXIS_TX_tkeep),
        .m_axis_tlast   (M_AXIS_TX_tlast),
        .m_axis_tstrb   (),
        .m_axis_tuser   (),
        .m_axis_tid     (),
        .m_axis_tdest   (),

        .almost_empty_axis(),
        .almost_full_axis(),
        .prog_empty_axis(),
        .prog_full_axis(),
        .wr_data_count_axis(tx_axis_wr_cnt),
        .rd_data_count_axis(),
        .injectsbiterr_axis(1'b0),
        .injectdbiterr_axis(1'b0),
        .sbiterr_axis(),
        .dbiterr_axis()
    );

    // =========================================================================
    // CMD pipeline 寄存器 (打断 datamover_ctrl → BD 的长组合路径)
    // c0_ddr4_ui_clk 域, 333MHz hold timing 修复
    // =========================================================================
    reg  [71:0] s2mm_cmd_tdata_reg, mm2s_cmd_tdata_reg;
    reg         s2mm_cmd_tvalid_reg, mm2s_cmd_tvalid_reg;

    wire bd_s2mm_cmd_tready, bd_mm2s_cmd_tready;

    // S2MM CMD: 源端 → reg → BD
    assign S_AXIS_S2MM_CMD_0_tready = !s2mm_cmd_tvalid_reg || bd_s2mm_cmd_tready;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!dm_rst_n) begin
            s2mm_cmd_tvalid_reg <= 1'b0;
        end else if (S_AXIS_S2MM_CMD_0_tready) begin
            s2mm_cmd_tvalid_reg <= S_AXIS_S2MM_CMD_0_tvalid;
            s2mm_cmd_tdata_reg  <= S_AXIS_S2MM_CMD_0_tdata;
        end
    end

    // MM2S CMD: 源端 → reg → BD
    assign S_AXIS_MM2S_CMD_0_tready = !mm2s_cmd_tvalid_reg || bd_mm2s_cmd_tready;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!dm_rst_n) begin
            mm2s_cmd_tvalid_reg <= 1'b0;
        end else if (S_AXIS_MM2S_CMD_0_tready) begin
            mm2s_cmd_tvalid_reg <= S_AXIS_MM2S_CMD_0_tvalid;
            mm2s_cmd_tdata_reg  <= S_AXIS_MM2S_CMD_0_tdata;
        end
    end

    // =========================================================================
    // STS pipeline 寄存器 (BD 输出 → reg → 顶层, 打断长路径)
    // =========================================================================
    wire [7:0] bd_s2mm_sts_tdata, bd_mm2s_sts_tdata;
    wire       bd_s2mm_sts_tvalid, bd_mm2s_sts_tvalid;
    wire       bd_s2mm_err, bd_mm2s_err;

    reg  [7:0] s2mm_sts_tdata_r, mm2s_sts_tdata_r;
    reg        s2mm_sts_tvalid_r, mm2s_sts_tvalid_r;
    reg        s2mm_err_r, mm2s_err_r;

    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!dm_rst_n) begin
            s2mm_sts_tdata_r  <= 8'd0;
            s2mm_sts_tvalid_r <= 1'b0;
            s2mm_err_r        <= 1'b0;
            mm2s_sts_tdata_r  <= 8'd0;
            mm2s_sts_tvalid_r <= 1'b0;
            mm2s_err_r        <= 1'b0;
        end else begin
            s2mm_sts_tdata_r  <= bd_s2mm_sts_tdata;
            s2mm_sts_tvalid_r <= bd_s2mm_sts_tvalid;
            s2mm_err_r        <= bd_s2mm_err;
            mm2s_sts_tdata_r  <= bd_mm2s_sts_tdata;
            mm2s_sts_tvalid_r <= bd_mm2s_sts_tvalid;
            mm2s_err_r        <= bd_mm2s_err;
        end
    end

    assign M_AXIS_S2MM_STS_0_tdata  = s2mm_sts_tdata_r;
    assign M_AXIS_S2MM_STS_0_tvalid = s2mm_sts_tvalid_r;
    assign s2mm_err_0               = s2mm_err_r;
    assign M_AXIS_MM2S_STS_0_tdata  = mm2s_sts_tdata_r;
    assign M_AXIS_MM2S_STS_0_tvalid = mm2s_sts_tvalid_r;
    assign mm2s_err_0               = mm2s_err_r;

    // =========================================================================
    // BD wrapper 例化
    // =========================================================================
    ddr4_dma_subsystem_wrapper u_bd (
        .C0_DDR4_0_act_n     (ddr4_rtl_0_act_n),
        .C0_DDR4_0_adr       (ddr4_rtl_0_adr),
        .C0_DDR4_0_ba        (ddr4_rtl_0_ba),
        .C0_DDR4_0_bg        (ddr4_rtl_0_bg),
        .C0_DDR4_0_ck_c      (ddr4_rtl_0_ck_c),
        .C0_DDR4_0_ck_t      (ddr4_rtl_0_ck_t),
        .C0_DDR4_0_cke       (ddr4_rtl_0_cke),
        .C0_DDR4_0_cs_n      (ddr4_rtl_0_cs_n),
        .C0_DDR4_0_dm_n      (ddr4_rtl_0_dm_n),
        .C0_DDR4_0_dq        (ddr4_rtl_0_dq),
        .C0_DDR4_0_dqs_c     (ddr4_rtl_0_dqs_c),
        .C0_DDR4_0_dqs_t     (ddr4_rtl_0_dqs_t),
        .C0_DDR4_0_odt       (ddr4_rtl_0_odt),
        .C0_DDR4_0_reset_n   (ddr4_rtl_0_reset_n),

        .C0_SYS_CLK_0_clk_p  (diff_clock_rtl_0_clk_p),
        .C0_SYS_CLK_0_clk_n  (diff_clock_rtl_0_clk_n),

        .c0_ddr4_ui_clk       (c0_ddr4_ui_clk),
        .c0_init_calib_complete_0 (c0_init_calib_complete),
        .sys_rst               (sys_rst),

        // S2MM 数据: CDC FIFO → BD
        .S_AXIS_S2MM_0_tdata  (bd_s2mm_tdata),
        .S_AXIS_S2MM_0_tkeep  (bd_s2mm_tkeep),
        .S_AXIS_S2MM_0_tlast  (bd_s2mm_tlast),
        .S_AXIS_S2MM_0_tvalid (bd_s2mm_tvalid),
        .S_AXIS_S2MM_0_tready (bd_s2mm_tready),

        // MM2S 数据: BD → CDC FIFO
        .M_AXIS_MM2S_0_tdata  (bd_mm2s_tdata),
        .M_AXIS_MM2S_0_tkeep  (bd_mm2s_tkeep),
        .M_AXIS_MM2S_0_tlast  (bd_mm2s_tlast),
        .M_AXIS_MM2S_0_tvalid (bd_mm2s_tvalid),
        .M_AXIS_MM2S_0_tready (bd_mm2s_tready),

        // S2MM 命令/状态: pipeline reg → BD / BD → intermediate wire
        .S_AXIS_S2MM_CMD_0_tdata  (s2mm_cmd_tdata_reg),
        .S_AXIS_S2MM_CMD_0_tvalid (s2mm_cmd_tvalid_reg),
        .S_AXIS_S2MM_CMD_0_tready (bd_s2mm_cmd_tready),
        .M_AXIS_S2MM_STS_0_tdata  (bd_s2mm_sts_tdata),
        .M_AXIS_S2MM_STS_0_tkeep  (),
        .M_AXIS_S2MM_STS_0_tlast  (),
        .M_AXIS_S2MM_STS_0_tvalid (bd_s2mm_sts_tvalid),
        .M_AXIS_S2MM_STS_0_tready (M_AXIS_S2MM_STS_0_tready),

        // MM2S 命令/状态: pipeline reg → BD / BD → intermediate wire
        .S_AXIS_MM2S_CMD_0_tdata  (mm2s_cmd_tdata_reg),
        .S_AXIS_MM2S_CMD_0_tvalid (mm2s_cmd_tvalid_reg),
        .S_AXIS_MM2S_CMD_0_tready (bd_mm2s_cmd_tready),
        .M_AXIS_MM2S_STS_0_tdata  (bd_mm2s_sts_tdata),
        .M_AXIS_MM2S_STS_0_tkeep  (),
        .M_AXIS_MM2S_STS_0_tlast  (),
        .M_AXIS_MM2S_STS_0_tvalid (bd_mm2s_sts_tvalid),
        .M_AXIS_MM2S_STS_0_tready (M_AXIS_MM2S_STS_0_tready),

        // 错误 → intermediate wire
        .s2mm_err_0 (bd_s2mm_err),
        .mm2s_err_0 (bd_mm2s_err)
    );

    // =========================================================================
    // Search Engine Integration — BD internal wiring (needs Vivado BD update)
    //
    // TODO: In Vivado Block Design:
    //   1. Connect rx_demux m4_axis_* → M_AXIS_CH4_* output ports
    //   2. Add AXI SmartConnect between MIG S_AXI and:
    //      - existing AXI Datamover S_AXI
    //      - new S_AXI_SEARCH_* port
    // =========================================================================

    // Ch3/Ch4 pass-through (temporary: drive as idle until BD is updated)
    assign M_AXIS_CH3_tdata  = 512'd0;
    assign M_AXIS_CH3_tkeep  = 64'd0;
    assign M_AXIS_CH3_tvalid = 1'b0;
    assign M_AXIS_CH3_tlast  = 1'b0;
    assign M_AXIS_CH4_tdata  = 512'd0;
    assign M_AXIS_CH4_tkeep  = 64'd0;
    assign M_AXIS_CH4_tvalid = 1'b0;
    assign M_AXIS_CH4_tlast  = 1'b0;

    // AXI Search — BD-internal SmartConnect S02 connection pending Vivado synthesis
    // In Vivado: Connect S_AXI_SEARCH → smartconnect_0/S02_AXI (see .bd JSON update)
    assign S_AXI_SEARCH_arready = 1'b0;
    assign S_AXI_SEARCH_rdata   = 512'd0;
    assign S_AXI_SEARCH_rvalid  = 1'b0;
    assign S_AXI_SEARCH_rresp   = 2'b00;
    assign S_AXI_SEARCH_awready = 1'b0;
    assign S_AXI_SEARCH_wready  = 1'b0;
    assign S_AXI_SEARCH_bresp   = 2'b00;
    assign S_AXI_SEARCH_bvalid  = 1'b0;

endmodule
