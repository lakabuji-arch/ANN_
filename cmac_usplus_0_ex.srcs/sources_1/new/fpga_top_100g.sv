`timescale 1ns / 1ps

module fpga_top_100g (
    input  wire         clk_50m_in,
    input  wire         sys_rst_pad_in,
    input  wire         gt_ref_clk_p,    
    input  wire         gt_ref_clk_n,    
    input  wire [3:0]   gt_rxp_in,
    input  wire [3:0]   gt_rxn_in,
    output wire [3:0]   gt_txp_out,
    output wire [3:0]   gt_txn_out,

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
    input  wire         diff_clock_rtl_0_clk_p,
    input  wire         diff_clock_rtl_0_clk_n,
    
    output wire [3:0]   led_out
);

    wire clk_100m, usr_mac_clk, c0_ddr4_ui_clk, usr_mac_rst_n;
    wire datamover_rst_n, tx_loop_rst_n;
    wire clk_100m_locked;
    wire ddr4_calib_complete;
    wire [11:0] rx_cdc_wr_count, tx_cdc_wr_count;
    wire rx_cdc_full;

    wire [511:0] axis_rx_tdata, axis_tx_tdata;
    wire [63:0]  axis_rx_tkeep, axis_tx_tkeep;
    wire         axis_rx_tvalid, axis_rx_tready, axis_rx_tlast;
    wire axis_tx_tvalid, axis_tx_tready, axis_tx_tlast;

    wire [71:0] mm2s_cmd_tdata;
    wire [71:0]  s2mm_cmd_tdata;
    wire         s2mm_cmd_tvalid, s2mm_cmd_tready;
    wire mm2s_cmd_tvalid, mm2s_cmd_tready;

    wire         rx_payload_cmd_valid_322m;
    wire [15:0]  rx_payload_bytes_322m;
    wire [15:0]  tx_framer_bytes_333m;
    wire         mac_link_up;
    wire s2mm_err, mm2s_err;
    wire         tx_meta_rd_en_framer; // Framer 发出的元数据推进脉冲

    // 命令控制 CDC (usr_mac_clk → c0_ddr4_ui_clk): 电平信号, 2-FF 安全
    wire        ctrl_start_rec, ctrl_stop_rec, ctrl_start_play, ctrl_stop_play;
    wire        ctrl_soft_reset;
    wire [31:0] ctrl_base_addr;
    reg         rec_active_322 = 1'b0, play_active_322 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rec_active_sync = 2'd0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] play_active_sync = 2'd0;
    wire        ext_rec_active  = rec_active_sync[1];
    wire        ext_play_active = play_active_sync[1];

    // 状态回传 (c0_ddr4_ui_clk → usr_mac_clk): 多比特用 Gray 码, 单比特用 2-FF
    wire [15:0] stat_s2mm_cmd_cnt_333, stat_mm2s_cmd_cnt_333;
    wire [11:0] stat_rx_wr_count_333, stat_tx_wr_count_333;
    wire        stat_s2mm_err_333, stat_mm2s_err_333;
    wire [15:0] stat_s2mm_cmd_cnt_322, stat_mm2s_cmd_cnt_322;
    wire [11:0] stat_rx_wr_count_322,  stat_tx_wr_count_322;
    wire        stat_s2mm_err_322,     stat_mm2s_err_322;

    // S2MM / MM2S STS 诊断
    wire [7:0]   s2mm_sts_tdata, mm2s_sts_tdata;
    wire s2mm_sts_tvalid;
    wire         mm2s_sts_tvalid;

    // =========================================================================
    // 诊断信号 (ILA Set Up Debug 可连接)
    // =========================================================================
    wire [31:0] diag_rx_fifo_count, diag_tx_fifo_count;
    wire [15:0] diag_s2mm_cmd_cnt, diag_mm2s_cmd_cnt;
    wire        diag_lb_fifo_empty, diag_rx_meta_waiting;
    wire [7:0]  diag_s2mm_sts_tdata;
    wire        diag_s2mm_sts_tvalid, diag_s2mm_err;
    wire [7:0]  diag_mm2s_sts_tdata;
    wire        diag_mm2s_sts_tvalid, diag_mm2s_err;

    // =========================================================================
    // 接收侧 CDC: 长度信息 (322MHz -> 333MHz)
    // =========================================================================
    wire        rx_meta_empty;
    wire [15:0] rx_meta_len;
    wire        rx_meta_rd_en;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("distributed"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(16),
        .READ_MODE("fwft"),
        .READ_DATA_WIDTH(16),
        .WRITE_DATA_WIDTH(16),
        .CDC_SYNC_STAGES(3)
    ) u_rx_meta_fifo (
        .rst(~usr_mac_rst_n),
        .wr_clk(usr_mac_clk),
        .wr_en(rx_payload_cmd_valid_322m),
        .din(rx_payload_bytes_322m),
        .rd_clk(c0_ddr4_ui_clk),
        .rd_en(rx_meta_rd_en),
        .dout(rx_meta_len),
        .empty(rx_meta_empty),
        .sleep(1'b0)
    );

    // =========================================================================
    // 发送侧 CDC: 长度精准绑定 FIFO (333MHz -> 322MHz)
    // =========================================================================
    wire tx_meta_empty;
    wire [15:0] tx_meta_len_322m;
    wire        tx_meta_rd_en;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("distributed"),
        .FIFO_READ_LATENCY(0), 
        .FIFO_WRITE_DEPTH(64),
        .READ_MODE("fwft"),
        .READ_DATA_WIDTH(16),
        .WRITE_DATA_WIDTH(16),
        .CDC_SYNC_STAGES(3)
    ) u_tx_meta_fifo (
        .rst    (~tx_loop_rst_n),
        .wr_clk (c0_ddr4_ui_clk),
        .wr_en  (mm2s_cmd_tvalid && mm2s_cmd_tready),
        .din    (tx_framer_bytes_333m), 
        .rd_clk (usr_mac_clk),
        .rd_en  (tx_meta_rd_en),
        .dout   (tx_meta_len_322m),
        .empty  (tx_meta_empty),
        .sleep  (1'b0)
    );

    assign tx_meta_rd_en = tx_meta_rd_en_framer;

    // =========================================================================
    // 命令控制 CDC: 电平信号 (usr_mac_clk → c0_ddr4_ui_clk)
    // START=置位, STOP=清零, 2-FF 同步到 DDR4 域
    // =========================================================================
    always_ff @(posedge usr_mac_clk) begin
        if (!usr_mac_rst_n) begin
            rec_active_322  <= 1'b0;
            play_active_322 <= 1'b0;
        end else begin
            if (ctrl_soft_reset) begin
                rec_active_322  <= 1'b0;  // 软复位: 立即停止录播
                play_active_322 <= 1'b0;
            end else begin
                if (ctrl_start_rec)  rec_active_322  <= 1'b1;
                if (ctrl_stop_rec)   rec_active_322  <= 1'b0;
                if (ctrl_start_play) play_active_322 <= 1'b1;
                if (ctrl_stop_play)  play_active_322 <= 1'b0;
            end
        end
    end

    always_ff @(posedge c0_ddr4_ui_clk) begin
        rec_active_sync  <= {rec_active_sync[0], rec_active_322};
        play_active_sync <= {play_active_sync[0], play_active_322};
    end

    // =========================================================================
    // 软复位 CDC (usr_mac_clk → c0_ddr4_ui_clk)
    // ctrl_soft_reset 是单周期脉冲，转为 toggle 后跨时钟域同步，
    // 在 c0_ddr4_ui_clk 域产生 ~16 周期的 rst_n 低脉冲复位 datamover_ctrl
    // =========================================================================
    reg        soft_rst_toggle_322 = 1'b0;
    always_ff @(posedge usr_mac_clk) begin
        if (!usr_mac_rst_n)
            soft_rst_toggle_322 <= 1'b0;
        else if (ctrl_soft_reset)
            soft_rst_toggle_322 <= ~soft_rst_toggle_322;
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] soft_rst_toggle_sync = 2'd0;
    reg        soft_rst_toggle_333_d = 1'b0;
    reg        soft_rst_active = 1'b0;
    reg [3:0]  soft_rst_cnt = 4'd0;

    always_ff @(posedge c0_ddr4_ui_clk) begin
        soft_rst_toggle_sync <= {soft_rst_toggle_sync[0], soft_rst_toggle_322};
        soft_rst_toggle_333_d <= soft_rst_toggle_sync[1];

        // 边沿检测 → 启动复位脉冲
        if (soft_rst_toggle_sync[1] != soft_rst_toggle_333_d) begin
            soft_rst_active <= 1'b1;
            soft_rst_cnt    <= 4'd15;
        end else if (soft_rst_active) begin
            if (soft_rst_cnt > 0)
                soft_rst_cnt <= soft_rst_cnt - 1'b1;
            else
                soft_rst_active <= 1'b0;
        end
    end

    // datamover_ctrl 有效复位 = 正常复位 & 非软复位激活
    wire datamover_rst_n_eff = datamover_rst_n && !soft_rst_active;

    // 状态回传 CDC:
    //   多比特计数器 → xpm_cdc_gray (Gray码, 每次只变1bit, 杜绝偏斜)
    //   单比特 err   → 2-FF ASYNC_REG (单bit安全)
    xpm_cdc_gray #(.DEST_SYNC_FF(3), .SIM_ASSERT_CHK(0), .WIDTH(16)) u_cdc_s2mm_cnt (
        .src_clk(c0_ddr4_ui_clk),  .src_in_bin(stat_s2mm_cmd_cnt_333),
        .dest_clk(usr_mac_clk),    .dest_out_bin(stat_s2mm_cmd_cnt_322)
    );
    xpm_cdc_gray #(.DEST_SYNC_FF(3), .SIM_ASSERT_CHK(0), .WIDTH(16)) u_cdc_mm2s_cnt (
        .src_clk(c0_ddr4_ui_clk),  .src_in_bin(stat_mm2s_cmd_cnt_333),
        .dest_clk(usr_mac_clk),    .dest_out_bin(stat_mm2s_cmd_cnt_322)
    );
    xpm_cdc_gray #(.DEST_SYNC_FF(3), .SIM_ASSERT_CHK(0), .WIDTH(12)) u_cdc_rx_wr_cnt (
        .src_clk(c0_ddr4_ui_clk),  .src_in_bin(stat_rx_wr_count_333),
        .dest_clk(usr_mac_clk),    .dest_out_bin(stat_rx_wr_count_322)
    );
    xpm_cdc_gray #(.DEST_SYNC_FF(3), .SIM_ASSERT_CHK(0), .WIDTH(12)) u_cdc_tx_wr_cnt (
        .src_clk(c0_ddr4_ui_clk),  .src_in_bin(stat_tx_wr_count_333),
        .dest_clk(usr_mac_clk),    .dest_out_bin(stat_tx_wr_count_322)
    );

    // 单比特 err 信号: 2-FF 同步安全
    (* ASYNC_REG = "TRUE" *) reg [1:0] stat_s2mm_err_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] stat_mm2s_err_sync;
    always_ff @(posedge usr_mac_clk) begin
        stat_s2mm_err_sync <= {stat_s2mm_err_sync[0], stat_s2mm_err_333};
        stat_mm2s_err_sync <= {stat_mm2s_err_sync[0], stat_mm2s_err_333};
    end
    assign stat_s2mm_err_322 = stat_s2mm_err_sync[1];
    assign stat_mm2s_err_322 = stat_mm2s_err_sync[1];

    // =========================================================================
    // clk_wiz_0: 50MHz → 100MHz (CMAC init_clk)
    // =========================================================================
    clk_wiz_0 u_clk_wiz (
        .clk_out1 (clk_100m),
        .clk_out2 (),
        .reset    (sys_rst_pad_in),
        .locked   (clk_100m_locked),
        .clk_in1  (clk_50m_in)
    );

    // =========================================================================
    // 模块例化
    // =========================================================================
    cmac_100g_wrapper u_cmac_wrapper (
        .gt_ref_clk_p        (gt_ref_clk_p),     .gt_ref_clk_n        (gt_ref_clk_n),
        .gt_rxp_in           (gt_rxp_in),        .gt_rxn_in           (gt_rxn_in),
        .gt_txp_out          (gt_txp_out),       .gt_txn_out          (gt_txn_out),
        .init_clk            (clk_100m),         .sys_reset           (sys_rst_pad_in),
        .usr_mac_clk         (usr_mac_clk),      .usr_mac_rst_n       (usr_mac_rst_n),
        .mac_link_up         (mac_link_up),      

        .m_axis_rx_tdata     (axis_rx_tdata),    .m_axis_rx_tkeep     (axis_rx_tkeep),
        .m_axis_rx_tvalid    (axis_rx_tvalid),   .m_axis_rx_tlast     (axis_rx_tlast),
        .m_axis_rx_tready    (axis_rx_tready),
        .o_payload_cmd_valid (rx_payload_cmd_valid_322m),
        .o_payload_bytes     (rx_payload_bytes_322m),

        .s_axis_tx_tdata     (axis_tx_tdata),    .s_axis_tx_tkeep     (axis_tx_tkeep),
        .s_axis_tx_tvalid    (axis_tx_tvalid),   .s_axis_tx_tlast     (axis_tx_tlast),
        .s_axis_tx_tready    (axis_tx_tready),
        .i_tx_payload_bytes  (tx_meta_len_322m),
        .tx_meta_empty       (tx_meta_empty),
        .o_tx_meta_rd_en     (tx_meta_rd_en_framer),
        .tx_pause_req        (9'd0),
        .ctrl_start_rec      (ctrl_start_rec),
        .ctrl_stop_rec       (ctrl_stop_rec),
        .ctrl_start_play     (ctrl_start_play),
        .ctrl_stop_play      (ctrl_stop_play),
        .ctrl_base_addr      (ctrl_base_addr),
        .ctrl_soft_reset     (ctrl_soft_reset),
        .stat_s2mm_cmd_cnt   (stat_s2mm_cmd_cnt_322),
        .stat_mm2s_cmd_cnt   (stat_mm2s_cmd_cnt_322),
        .stat_rx_wr_count    (stat_rx_wr_count_322),
        .stat_tx_wr_count    (stat_tx_wr_count_322),
        .stat_s2mm_err       (stat_s2mm_err_322),
        .stat_mm2s_err       (stat_mm2s_err_322)
    );

    ddr4_subsystem_top u_bd_wrapper (
        .usr_mac_clk             (usr_mac_clk),
        .usr_mac_rst_n           (usr_mac_rst_n),
        .c0_ddr4_ui_clk          (c0_ddr4_ui_clk),
        .sys_rst                 (sys_rst_pad_in),
        .dm_rst_n                (datamover_rst_n),
        .c0_init_calib_complete  (ddr4_calib_complete),       
        
        .diff_clock_rtl_0_clk_p  (diff_clock_rtl_0_clk_p), .diff_clock_rtl_0_clk_n  (diff_clock_rtl_0_clk_n),
        .ddr4_rtl_0_act_n        (ddr4_rtl_0_act_n),     .ddr4_rtl_0_adr          (ddr4_rtl_0_adr),
        .ddr4_rtl_0_ba           (ddr4_rtl_0_ba),        .ddr4_rtl_0_bg           (ddr4_rtl_0_bg),
        .ddr4_rtl_0_ck_c         (ddr4_rtl_0_ck_c),      .ddr4_rtl_0_ck_t         (ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke          (ddr4_rtl_0_cke),       .ddr4_rtl_0_cs_n         (ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_dm_n         (ddr4_rtl_0_dm_n),      .ddr4_rtl_0_dq           (ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c        (ddr4_rtl_0_dqs_c),     .ddr4_rtl_0_dqs_t        (ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_odt          (ddr4_rtl_0_odt),       .ddr4_rtl_0_reset_n      (ddr4_rtl_0_reset_n),

        .M_AXIS_CH3_tdata        (ch3_tdata_322),
        .M_AXIS_CH3_tkeep        (ch3_tkeep_322),
        .M_AXIS_CH3_tvalid       (ch3_tvalid_322),
        .M_AXIS_CH3_tlast        (ch3_tlast_322),
        .M_AXIS_CH3_tready       (ch3_tready_322),
        .M_AXIS_CH4_tdata        (ch4_tdata_322),
        .M_AXIS_CH4_tkeep        (ch4_tkeep_322),
        .M_AXIS_CH4_tvalid       (ch4_tvalid_322),
        .M_AXIS_CH4_tlast        (ch4_tlast_322),
        .M_AXIS_CH4_tready       (ch4_tready_322),

        .S_AXI_SEARCH_araddr     (search_m_axi_araddr),
        .S_AXI_SEARCH_arvalid    (search_m_axi_arvalid),
        .S_AXI_SEARCH_arready    (search_m_axi_arready),
        .S_AXI_SEARCH_rdata      (search_m_axi_rdata),
        .S_AXI_SEARCH_rvalid     (search_m_axi_rvalid),
        .S_AXI_SEARCH_rready     (search_m_axi_rready),
        .S_AXI_SEARCH_awaddr     (search_m_axi_awaddr),
        .S_AXI_SEARCH_awvalid    (search_m_axi_awvalid),
        .S_AXI_SEARCH_awready    (search_m_axi_awready),
        .S_AXI_SEARCH_wdata      (search_m_axi_wdata),
        .S_AXI_SEARCH_wvalid     (search_m_axi_wvalid),
        .S_AXI_SEARCH_wready     (search_m_axi_wready),

        .S_AXIS_RX_tdata         (axis_rx_tdata),        .S_AXIS_RX_tkeep         (axis_rx_tkeep),
        .S_AXIS_RX_tvalid        (axis_rx_tvalid),       .S_AXIS_RX_tlast         (axis_rx_tlast),
        .S_AXIS_RX_tready        (axis_rx_tready),

        .M_AXIS_TX_tdata         (axis_tx_tdata),        .M_AXIS_TX_tkeep         (axis_tx_tkeep),
        .M_AXIS_TX_tvalid        (axis_tx_tvalid),       .M_AXIS_TX_tlast         (axis_tx_tlast),
        .M_AXIS_TX_tready        (axis_tx_tready),

        .S_AXIS_S2MM_CMD_0_tdata (s2mm_cmd_tdata),       .S_AXIS_S2MM_CMD_0_tvalid(s2mm_cmd_tvalid),
        .S_AXIS_S2MM_CMD_0_tready(s2mm_cmd_tready),
        .M_AXIS_S2MM_STS_0_tdata (s2mm_sts_tdata),
        .M_AXIS_S2MM_STS_0_tvalid(s2mm_sts_tvalid),
        .M_AXIS_S2MM_STS_0_tready(1'b1),
        .S_AXIS_MM2S_CMD_0_tdata (mm2s_cmd_tdata),       .S_AXIS_MM2S_CMD_0_tvalid(mm2s_cmd_tvalid),
        .S_AXIS_MM2S_CMD_0_tready(mm2s_cmd_tready),
        .M_AXIS_MM2S_STS_0_tdata (mm2s_sts_tdata),
        .M_AXIS_MM2S_STS_0_tvalid(mm2s_sts_tvalid),
        .M_AXIS_MM2S_STS_0_tready(1'b1),
        
        .s2mm_err_0              (s2mm_err),
        .mm2s_err_0              (mm2s_err),
        .rx_cdc_wr_count         (rx_cdc_wr_count),
        .tx_cdc_wr_count         (tx_cdc_wr_count),
        .rx_fifo_full            (rx_cdc_full)
    );

    // =========================================================================
    // CDC: sys_rst_pad_in → c0_ddr4_ui_clk 域复位同步器
    // =========================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] ddr4_rst_sync_ff = 3'b111;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        ddr4_rst_sync_ff <= {ddr4_rst_sync_ff[1:0], sys_rst_pad_in};
    end
    wire ddr4_rst_n = ~ddr4_rst_sync_ff[2];

    // =========================================================================
    // CDC: clk_100m_locked → c0_ddr4_ui_clk 域两级同步
    // =========================================================================
    (* ASYNC_REG = "TRUE" *) reg [1:0] locked_sync_ff = 2'b00;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!ddr4_rst_n) begin
            locked_sync_ff <= 2'b00;
        end else begin
            locked_sync_ff <= {locked_sync_ff[0], clk_100m_locked};
        end
    end
    wire clk_100m_locked_sync = locked_sync_ff[1];

    // =========================================================================
    // 【DDR4 冷启动等待】：1秒延时 + DDR4 calib + clk_wiz locked
    // =========================================================================
    wire ddr4_ready = ddr4_calib_complete && clk_100m_locked_sync;
    reg [28:0] ddr4_ready_cnt = 29'd0;
    reg        dm_rst_n_reg = 1'b0;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!ddr4_rst_n) begin
            ddr4_ready_cnt <= 29'd0;
            dm_rst_n_reg   <= 1'b0;
        end else begin
            if (ddr4_ready_cnt < 29'h13E0_0000)
                ddr4_ready_cnt <= ddr4_ready_cnt + 1'b1;
            else
                dm_rst_n_reg <= ddr4_ready;
        end
    end
    assign datamover_rst_n = dm_rst_n_reg;
    assign tx_loop_rst_n = datamover_rst_n & usr_mac_rst_n;

    assign diag_rx_fifo_count = {20'd0, rx_cdc_wr_count};
    assign diag_tx_fifo_count = {20'd0, tx_cdc_wr_count};

    datamover_ctrl u_dm_ctrl (
        .clk                  (c0_ddr4_ui_clk),
        .rst_n                (datamover_rst_n_eff),

        .rx_fifo_empty        (rx_meta_empty),
        .rx_fifo_len          (rx_meta_len),
        .rx_fifo_rd_en        (rx_meta_rd_en),

        .s2mm_cmd_tdata       (s2mm_cmd_tdata),
        .s2mm_cmd_tvalid      (s2mm_cmd_tvalid),
        .s2mm_cmd_tready      (s2mm_cmd_tready),
        .s2mm_sts_tvalid      (s2mm_sts_tvalid),
        .s2mm_err             (s2mm_err),

        .tx_trigger_pulse     (1'b0),
        .tx_request_bytes     (16'd0),
        .o_framer_tx_bytes    (tx_framer_bytes_333m),

        .mm2s_cmd_tdata       (mm2s_cmd_tdata),
        .mm2s_cmd_tvalid      (mm2s_cmd_tvalid),
        .mm2s_cmd_tready      (mm2s_cmd_tready),

        .cfg_rx_base_addr     (32'h0000_0000),
        .cfg_tx_base_addr     (32'h4000_0000),

        .ext_rec_active       (ext_rec_active),
        .ext_play_active      (ext_play_active),

        .o_diag_s2mm_cmd_cnt  (diag_s2mm_cmd_cnt),
        .o_diag_mm2s_cmd_cnt  (diag_mm2s_cmd_cnt),
        .o_diag_lb_fifo_empty (diag_lb_fifo_empty),
        .o_diag_rx_meta_waiting(diag_rx_meta_waiting),
        .o_diag_rec_active    (),
        .o_diag_play_active   ()
    );

    assign diag_s2mm_sts_tdata  = s2mm_sts_tdata;
    assign diag_s2mm_sts_tvalid = s2mm_sts_tvalid;
    assign diag_s2mm_err        = s2mm_err;
    assign diag_mm2s_sts_tdata  = mm2s_sts_tdata;
    assign diag_mm2s_sts_tvalid = mm2s_sts_tvalid;

    // 状态 → CDC → cmd_parser
    assign stat_s2mm_cmd_cnt_333 = diag_s2mm_cmd_cnt;
    assign stat_mm2s_cmd_cnt_333 = diag_mm2s_cmd_cnt;
    assign stat_rx_wr_count_333  = rx_cdc_wr_count;
    assign stat_tx_wr_count_333  = tx_cdc_wr_count;
    assign stat_s2mm_err_333     = s2mm_err;
    assign stat_mm2s_err_333     = mm2s_err;
    assign diag_mm2s_err        = mm2s_err;

    // =========================================================================
    // LED 状态逻辑
    // 0: 系统心跳
    // 1: MAC Link 状态 (亮=Link Up)
    // 2: S2MM 状态 (闪烁=有数据写入DDR4, 常亮=S2MM报错)
    // 3: MM2S 状态 (闪烁=有数据读出DDR4, 常亮=MM2S报错)
    // =========================================================================
    reg [25:0] hb_cnt = 0;
    always_ff @(posedge clk_50m_in) hb_cnt <= hb_cnt + 1'b1;
    assign led_out[0] = hb_cnt[25];

    assign led_out[1] = mac_link_up;

    // DDR4 域心跳 (用于 LED 诊断)
    reg [25:0] ddr4_hb_cnt = 0;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!ddr4_rst_n)
            ddr4_hb_cnt <= 26'd0;
        else
            ddr4_hb_cnt <= ddr4_hb_cnt + 1'b1;
    end

    // S2MM 错误锁存
    reg s2mm_err_latch;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!datamover_rst_n)
            s2mm_err_latch <= 1'b0;
        else if (s2mm_err)
            s2mm_err_latch <= 1'b1;
    end

    // S2MM 活动脉冲展宽 (any activity → ON → hold ~200ms)
    reg s2mm_act_led;
    reg [25:0] s2mm_hold_cnt;  // 26-bit @333MHz ≈ 200ms hold
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!datamover_rst_n) begin
            s2mm_act_led   <= 1'b0;
            s2mm_hold_cnt  <= 26'd0;
        end else if (s2mm_sts_tvalid) begin
            s2mm_act_led   <= 1'b1;
            s2mm_hold_cnt  <= 26'h3FFFFFF;  // ~200ms
        end else if (s2mm_hold_cnt > 0) begin
            s2mm_hold_cnt  <= s2mm_hold_cnt - 1'b1;
            if (s2mm_hold_cnt == 1)
                s2mm_act_led <= 1'b0;
        end
    end
    // LED2: DDR4 未就绪→快闪, 就绪→S2MM活动(亮200ms), 常亮=err
    assign led_out[2] = !datamover_rst_n ? ddr4_hb_cnt[22] :
                        s2mm_err_latch ? 1'b1 : s2mm_act_led;

    // MM2S 错误锁存 (收到第一个包、S2MM 写过 DDR4 之后才使能)
    reg mm2s_err_latch;
    reg rx_pkt_seen;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!datamover_rst_n) begin
            mm2s_err_latch <= 1'b0;
            rx_pkt_seen    <= 1'b0;
        end else begin
            if (s2mm_sts_tvalid && !s2mm_err)
                rx_pkt_seen <= 1'b1;
            if (mm2s_err && rx_pkt_seen)
                mm2s_err_latch <= 1'b1;
        end
    end

    // MM2S 活动脉冲展宽 (any activity → ON → hold ~200ms)
    reg mm2s_act_led;
    reg [25:0] mm2s_hold_cnt;
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (!datamover_rst_n) begin
            mm2s_act_led  <= 1'b0;
            mm2s_hold_cnt <= 26'd0;
        end else if (mm2s_cmd_tvalid && mm2s_cmd_tready) begin
            mm2s_act_led  <= 1'b1;
            mm2s_hold_cnt <= 26'h3FFFFFF;
        end else if (mm2s_hold_cnt > 0) begin
            mm2s_hold_cnt <= mm2s_hold_cnt - 1'b1;
            if (mm2s_hold_cnt == 1)
                mm2s_act_led <= 1'b0;
        end
    end
    assign led_out[3] = mm2s_err_latch ? 1'b1 : mm2s_act_led;

    // =========================================================================
    // Vector Search Engine Integration
    // =========================================================================
    //
    // Ch3 (UDP:8001) = control plane: SEARCH/INSERT/REINDEX/GET_STATUS
    // Ch4 (UDP:8002) = data plane: bulk vector transfer
    //
    // Both route through xpm_fifo_async CDC (322MHz → 333MHz for commands,
    // 333MHz → 322MHz for responses)

    wire [511:0] ch3_tdata_322, ch4_tdata_322;
    wire [63:0]  ch3_tkeep_322, ch4_tkeep_322;
    wire         ch3_tvalid_322, ch4_tvalid_322;
    wire         ch3_tlast_322,  ch4_tlast_322;
    wire         ch3_tready_322, ch4_tready_322;

    // ─── CDC: Ch3 command (322→333) ───
    wire [511:0] search_cmd_tdata_333;
    wire         search_cmd_tvalid_333;
    wire         search_cmd_tready_333;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(32), .READ_MODE("fwft"),
        .READ_DATA_WIDTH(512), .WRITE_DATA_WIDTH(512), .CDC_SYNC_STAGES(3)
    ) u_search_cmd_cdc (
        .rst(~usr_mac_rst_n),
        .wr_clk(usr_mac_clk),    .wr_en(ch3_tvalid_322 && ch3_tready_322),
        .din(ch3_tdata_322),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(search_cmd_tready_333),
        .dout(search_cmd_tdata_333),
        .empty(!search_cmd_tvalid_333),
        .sleep(1'b0)
    );
    assign ch3_tready_322 = 1'b1;  // always ready to accept Ch3

    // ─── CDC: Ch4 data (322→333) ───
    wire [511:0] search_data_tdata_333;
    wire         search_data_tvalid_333;
    wire         search_data_tready_333;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(128), .READ_MODE("fwft"),
        .READ_DATA_WIDTH(512), .WRITE_DATA_WIDTH(512), .CDC_SYNC_STAGES(3)
    ) u_search_data_cdc (
        .rst(~usr_mac_rst_n),
        .wr_clk(usr_mac_clk),    .wr_en(ch4_tvalid_322 && ch4_tready_322),
        .din(ch4_tdata_322),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(search_data_tready_333),
        .dout(search_data_tdata_333),
        .empty(!search_data_tvalid_333),
        .sleep(1'b0)
    );
    assign ch4_tready_322 = 1'b1;

    // ─── CDC: Response (333→322) ───
    wire [511:0] search_resp_tdata_333, search_resp_tdata_322;
    wire         search_resp_tvalid_333, search_resp_tvalid_322;
    wire         search_resp_tready_333;
    wire         search_resp_empty_322;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(32), .READ_MODE("fwft"),
        .READ_DATA_WIDTH(512), .WRITE_DATA_WIDTH(512), .CDC_SYNC_STAGES(3)
    ) u_search_resp_cdc (
        .rst(~ddr4_rst_n),
        .wr_clk(c0_ddr4_ui_clk), .wr_en(search_resp_tvalid_333 && search_resp_tready_333),
        .din(search_resp_tdata_333),
        .rd_clk(usr_mac_clk),    .rd_en(!search_resp_empty_322),
        .dout(search_resp_tdata_322),
        .empty(search_resp_empty_322),
        .sleep(1'b0)
    );
    assign search_resp_tvalid_322 = !search_resp_empty_322;

    // ─── Search Engine Instantiation (c0_ddr4_ui_clk domain) ───
    wire [31:0]  search_m_axi_araddr, search_m_axi_awaddr;
    wire         search_m_axi_arvalid, search_m_axi_awvalid;
    wire         search_m_axi_arready, search_m_axi_awready;
    wire [511:0] search_m_axi_rdata, search_m_axi_wdata;
    wire         search_m_axi_rvalid, search_m_axi_wvalid;
    wire         search_m_axi_rready, search_m_axi_wready;
    wire [31:0]  search_status_monitor;
    wire         search_active;

    search_engine_top u_search_engine (
        .ddr4_ui_clk         (c0_ddr4_ui_clk),
        .ddr4_ui_rst         (!ddr4_rst_n),

        // AXI → ddr4_subsystem_top
        .m_axi_araddr        (search_m_axi_araddr),
        .m_axi_arvalid       (search_m_axi_arvalid),
        .m_axi_arready       (search_m_axi_arready),
        .m_axi_rdata         (search_m_axi_rdata),
        .m_axi_rvalid        (search_m_axi_rvalid),
        .m_axi_rready        (search_m_axi_rready),
        .m_axi_awaddr        (search_m_axi_awaddr),
        .m_axi_awvalid       (search_m_axi_awvalid),
        .m_axi_awready       (search_m_axi_awready),
        .m_axi_wdata         (search_m_axi_wdata),
        .m_axi_wvalid        (search_m_axi_wvalid),
        .m_axi_wready        (search_m_axi_wready),

        // CDC: command from UDP:8001
        .s_axis_cmd_tdata    (search_cmd_tdata_333),
        .s_axis_cmd_tvalid   (search_cmd_tvalid_333),
        .s_axis_cmd_tready   (search_cmd_tready_333),
        .m_axis_resp_tdata   (search_resp_tdata_333),
        .m_axis_resp_tvalid  (search_resp_tvalid_333),
        .m_axis_resp_tready  (search_resp_tready_333),

        // CDC: data from UDP:8002
        .s_axis_data_tdata   (search_data_tdata_333),
        .s_axis_data_tvalid  (search_data_tvalid_333),
        .s_axis_data_tready  (search_data_tready_333),
        .m_axis_data_tdata   (),  // data plane output (unused for now)
        .m_axis_data_tvalid  (),
        .m_axis_data_tready  (1'b1),

        .o_status_monitor    (search_status_monitor),
        .o_search_active     (search_active)
    );

endmodule