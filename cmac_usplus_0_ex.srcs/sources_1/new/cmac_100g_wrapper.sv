`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: cmac_100g_wrapper
// 模块用途: CMAC 100G 以太网接口封装
// 说明:
//           本设计实现了 100G 以太网收发及协议处理功能
//           1. CMAC IP 处理 100G 以太网 MAC 层
//           2. GT 支持 4 条链路收发
//           3. UDP 配置通过 AXI4-Lite 完成
//           4. 接收数据通过 Demux 分发到 ARP/ICMP/UDP
//           5. ARP 响应本机 ARP 请求
//           6. ICMP 响应本机 Ping 请求
//           7. UDP 发/收通过 Framer/Deframer 处理 (已升级为动态变长支持)
//           8. TX 发送优先级按 ARP/ICMP/UDP 复用输出
//           9. 提供实时统计功能
//           10. AXI 接口配置 CMAC IP 寄存器
//
// 端口说明:
//   - init_clk: 初始化时钟，用于 AXI 寄存器访问和 CMAC 控制
//   - usr_mac_clk: MAC 数据路径时钟，由 CMAC IP 输出
// 备注: sys_reset 为系统复位输入
////////////////////////////////////////////////////////////////////////////////

module cmac_100g_wrapper (
    // =========================================================================
    // 1. GT 物理接口
    // =========================================================================
    input  wire         gt_ref_clk_p,    // GT 参考时钟正端，156.25 MHz
    input  wire         gt_ref_clk_n,    // GT 参考时钟负端
    input  wire [3:0]   gt_rxp_in,       // GT 接收差分正
    input  wire [3:0]   gt_rxn_in,       // GT 接收差分负
    output wire [3:0]   gt_txp_out,      // GT 发射差分正
    output wire [3:0]   gt_txn_out,      // GT 发射差分负

    // =========================================================================
    // 2. 复位与初始化输入
    // =========================================================================
    input  wire         init_clk,        // 初始化时钟
    input  wire         sys_reset,       // 系统复位输入

    // =========================================================================
    // 3. 用户 MAC 接口
    // =========================================================================
    output wire         usr_mac_clk,     // 用户 MAC 时钟
    output wire         usr_mac_rst_n,   // 用户 MAC 复位，低有效
    output wire         mac_link_up,     // MAC 链路状态，1: 链路正常

    // =========================================================================
    // 4. AXI-Stream 512-bit 数据接口
    // =========================================================================
    // AXI-Stream 发送数据到 MAC
    input  wire [511:0] s_axis_tx_tdata, // 发送数据总线，64 字节/beat
    input  wire [63:0]  s_axis_tx_tkeep, // 字节有效指示，1 表示对应字节有效
    input  wire         s_axis_tx_tvalid,// 发送数据有效
    input  wire         s_axis_tx_tlast, // 发送帧结束标志
    input  wire [15:0]  s_axis_tx_tuser, // 发送用户信号/帧标志
    output wire         s_axis_tx_tready,// 发送通道可接受数据

    // AXI-Stream 接收数据来自 MAC
    output wire [511:0] m_axis_rx_tdata, // 接收数据总线，64 字节/beat
    output wire [63:0]  m_axis_rx_tkeep, // 字节有效指示
    output wire         m_axis_rx_tvalid,// 接收数据有效
    output wire         m_axis_rx_tlast, // 接收帧结束标志
    input  wire         m_axis_rx_tready,// 接收通道可接受数据

    // =========================================================================
    // 5. 动态变长载荷控制接口 (【新增】用于联动 DataMover)
    // =========================================================================
    output wire         o_payload_cmd_valid, // 接收端: 载荷长度有效脉冲
    output wire [15:0]  o_payload_bytes,     // 接收端: 当前包有效载荷字节数
    input  wire [15:0]  i_tx_payload_bytes,  // 发送端: 动态请求发送字节数
    input  wire         tx_meta_empty,       // meta FIFO 空标志，=1 时禁止进入 HEADER
    output wire         o_tx_meta_rd_en,     // Framer 已捕获字节数，上游推进 FIFO

    // =========================================================================
    // 6. TX PAUSE 控制
    // =========================================================================
    input  wire [8:0]   tx_pause_req,    // 发送 PAUSE 请求，9-bit

    // =========================================================================
    // 7. 命令控制接口 (← cmd_parser → datamover_ctrl, 需上层 CDC)
    // =========================================================================
    output wire         ctrl_start_rec,
    output wire         ctrl_stop_rec,
    output wire         ctrl_start_play,
    output wire         ctrl_stop_play,
    output wire [31:0]  ctrl_base_addr,
    output wire         ctrl_soft_reset,  // 命令 0x06: 软复位
    input  wire [15:0]  stat_s2mm_cmd_cnt,
    input  wire [15:0]  stat_mm2s_cmd_cnt,
    input  wire [11:0]  stat_rx_wr_count,
    input  wire [11:0]  stat_tx_wr_count,
    input  wire         stat_s2mm_err,
    input  wire         stat_mm2s_err,

    // =========================================================================
    // 8. Network config exposed (for external rx_demux / search engine)
    // =========================================================================
    output wire [47:0] o_cfg_local_mac,
    output wire [31:0] o_cfg_local_ip,
    output wire        o_cfg_vlan_enable,

    // =========================================================================
    // 9. UDP/配置寄存器 AXI4-Lite 接口
    // =========================================================================
    input  wire [31:0] s_udp_cfg_axi_awaddr,  
    input  wire        s_udp_cfg_axi_awvalid, 
    output wire        s_udp_cfg_axi_awready, 
    input  wire [31:0] s_udp_cfg_axi_wdata,   
    input  wire [3:0]  s_udp_cfg_axi_wstrb,   
    input  wire        s_udp_cfg_axi_wvalid,  
    output wire        s_udp_cfg_axi_wready,  
    output wire [1:0]  s_udp_cfg_axi_bresp,   
    output wire        s_udp_cfg_axi_bvalid,  
    input  wire        s_udp_cfg_axi_bready,  
    input  wire [31:0] s_udp_cfg_axi_araddr,  
    input  wire        s_udp_cfg_axi_arvalid, 
    output wire        s_udp_cfg_axi_arready, 
    output wire [31:0] s_udp_cfg_axi_rdata,   
    output wire [1:0]  s_udp_cfg_axi_rresp,   
    output wire        s_udp_cfg_axi_rvalid,  
    input  wire        s_udp_cfg_axi_rready   
);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    
    // --- CMAC 时钟与复位 ---
    wire cmac_txusrclk2;       // CMAC TX 用户时钟
    wire cmac_usr_tx_reset;    // CMAC TX 复位
    wire cmac_usr_rx_reset;    // CMAC RX 复位

    // --- 网络发送 AXI-Stream 到 CMAC ---
    wire [511:0] net_tx_tdata; // 发送数据
    wire [63:0]  net_tx_tkeep; // 发送字节有效
    wire         net_tx_tvalid;// 发送数据有效
    wire         net_tx_tlast; // 发送帧结束
    wire         net_tx_tready;// CMAC 发送就绪

    // --- 网络接收 AXI-Stream 来自 CMAC ---
    wire [511:0] net_rx_tdata; // 接收数据
    wire [63:0]  net_rx_tkeep; // 接收字节有效
    wire         net_rx_tvalid;// 接收数据有效
    wire         net_rx_tlast; // 接收帧结束
    wire         net_rx_tuser; // 接收错误/状态标志

    // --- CMAC 状态 ---
    wire        stat_rx_aligned;
    wire        stat_rx_aligned_err;
    wire        stat_rx_local_fault;
    wire        stat_rx_remote_fault;
    wire        stat_tx_local_fault;
    wire        stat_rx_status;
    wire        stat_rx_hi_ber;
    wire [19:0] stat_rx_block_lock;
    wire        stat_rx_block_lock_all = &stat_rx_block_lock;
    wire [3:0]  gt_powergoodout;
    wire        mac_tx_ovfout;        // MAC TX 溢出
    wire        mac_tx_unfout;        // MAC TX 欠载

    // --- RS-FEC 状态 ---
    wire        stat_rx_rsfec_lane_alignment_status;
    wire        stat_rx_rsfec_hi_ser;

    // --- AXI4-Lite 到 CMAC 寄存器的连接 ---
    wire [31:0] s_axi_awaddr, s_axi_wdata, s_axi_araddr, s_axi_rdata;
    wire [3:0]  s_axi_wstrb;
    wire [1:0]  s_axi_bresp, s_axi_rresp;
    wire        s_axi_awvalid, s_axi_awready, s_axi_wvalid, s_axi_wready;
    wire        s_axi_bvalid, s_axi_bready, s_axi_arvalid, s_axi_arready;
    wire        s_axi_rvalid, s_axi_rready;
    wire        axi_init_done;  // AXI 初始化完成

    // --- UDP 配置寄存器输出 ---
    wire [47:0] cfg_local_mac;             
    wire [31:0] cfg_local_ip;              
    wire [47:0] cfg_dest_mac;              
    wire [31:0] cfg_dest_ip;               
    wire [15:0] cfg_src_port;              
    wire [15:0] cfg_dest_port;             
    wire [15:0] cfg_udp_payload_beats; // 虽然废弃不用，但保留线网防止 Config Slave 报错
    wire        cfg_vlan_enable;

    assign o_cfg_local_mac   = cfg_local_mac;
    assign o_cfg_local_ip    = cfg_local_ip;
    assign o_cfg_vlan_enable = cfg_vlan_enable;

    // --- 统计信号 ---
    wire [31:0] stat_cnt_rx_arp;
    wire [31:0] stat_cnt_rx_icmp;
    wire [31:0] stat_cnt_rx_udp;
    wire [31:0] stat_cnt_rx_drop;
    wire [31:0] stat_cnt_rx_err;
    wire [31:0] stat_cnt_tx_udp;
    wire [31:0] stat_cnt_tx_len_mismatch;
    wire [31:0] stat_cnt_tx_mac_ovf;
    wire [31:0] stat_cnt_tx_mac_unf;
    wire        stat_clear_pulse;

    // --- Framer 状态 ---
    wire        fr_stat_tx_udp;
    wire        fr_meta_rd_en;            
    wire        fr_stat_tx_len_bad = 1'b0; // 新Framer已无此输出，固定拉低        

    // --- RX Demux 状态 ---
    wire        st_rx_arp_pulse;
    wire        st_rx_icmp_pulse;
    wire        st_rx_udp_pulse;
    wire        st_rx_cmd_pulse;
    wire        st_rx_drop_pulse;
    wire        st_rx_err_pulse;

    // --- CDC 同步器：sys_reset (init_clk 域) -> usr_mac_clk 域 ---
    (* ASYNC_REG = "TRUE" *) reg sys_reset_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg sys_reset_sync = 1'b1;

    // --- MAC 溢出/欠载检测 ---
    reg         mac_ovf_d;                 
    reg         mac_unf_d;                 
    wire        pulse_mac_ovf = mac_tx_ovfout & ~mac_ovf_d;  
    wire        pulse_mac_unf = mac_tx_unfout & ~mac_unf_d;  

    // --- Demux 输出通道 ---
    wire [511:0] demux_m0_tdata; wire demux_m0_vld; wire demux_m0_last;
    wire [511:0] demux_m1_tdata; wire [63:0] demux_m1_tkeep; wire demux_m1_vld; wire demux_m1_last;
    wire [511:0] demux_m2_tdata; wire [63:0] demux_m2_tkeep; wire demux_m2_vld; wire demux_m2_last;
    wire [511:0] demux_m3_tdata; wire [63:0] demux_m3_tkeep; wire demux_m3_vld; wire demux_m3_last;

    // --- TX 多路复用数据 ---
    wire [511:0] arp_tx_tdata, icmp_tx_tdata, udp_tx_tdata, cmd_tx_tdata;
    wire [63:0]  arp_tx_tkeep, icmp_tx_tkeep, udp_tx_tkeep, cmd_tx_tkeep;
    wire         arp_tx_tvalid, icmp_tx_tvalid, udp_tx_tvalid, cmd_tx_tvalid;
    wire         arp_tx_tlast, icmp_tx_tlast, udp_tx_tlast, cmd_tx_tlast;
    wire         arp_tx_tready, icmp_tx_tready, udp_tx_tready, cmd_tx_tready;

    // --- UDP RX 弹性缓冲，隔离无反压 RX 路径与下游 backpressure ---
    wire [511:0] udp_rx_raw_tdata;
    wire [63:0]  udp_rx_raw_tkeep;
    wire         udp_rx_raw_tvalid;
    wire         udp_rx_raw_tlast;
    wire         udp_rx_raw_tready;
    wire [576:0] udp_rx_fifo_dout;
    wire         udp_rx_fifo_empty;
    wire         udp_rx_fifo_full;
    wire         udp_rx_fifo_rd_en;

    // =========================================================================
    // CMAC 时钟与链路状态
    // =========================================================================
    assign usr_mac_clk = cmac_txusrclk2;
    assign mac_link_up = stat_rx_aligned;

    // =========================================================================
    // 链路稳定性检测与复位释放 (含丢对齐去抖)
    // RS-FEC 重对齐可能瞬间丢失 stat_rx_aligned 几个周期，
    // 需要连续 32 周期不对齐才触发复位，防止误清空所有 FIFO
    // =========================================================================
    reg [15:0] link_up_cnt    = 16'd0;
    reg [7:0]  rx_loss_cnt    = 8'd0;
    reg        clean_rst_n    = 1'b0;

    always @(posedge cmac_txusrclk2) begin
        if (cmac_usr_tx_reset | cmac_usr_rx_reset) begin
            link_up_cnt <= 16'd0;
            rx_loss_cnt <= 8'd0;
            clean_rst_n <= 1'b0;
        end else if (stat_rx_aligned) begin
            rx_loss_cnt <= 8'd0;
            if (link_up_cnt < 16'd1000) begin
                link_up_cnt <= link_up_cnt + 1'b1;
                clean_rst_n <= 1'b0;
            end else begin
                clean_rst_n <= 1'b1;
            end
        end else begin
            // 短暂丢对齐: 只计数，不清零 link_up_cnt，不拉复位
            if (rx_loss_cnt < 8'd255)
                rx_loss_cnt <= rx_loss_cnt + 1'b1;
            // 连续 32 周期不对齐 → 确认链路真的断了，才复位
            if (rx_loss_cnt >= 8'd32) begin
                link_up_cnt <= 16'd0;
                clean_rst_n <= 1'b0;
            end
        end
    end

    assign usr_mac_rst_n = clean_rst_n;

    // =========================================================================
    // MAC 溢出/欠载寄存器更新
    // =========================================================================
    always_ff @(posedge usr_mac_clk) begin
        sys_reset_meta <= sys_reset;
        sys_reset_sync <= sys_reset_meta;
    end

    always_ff @(posedge usr_mac_clk) begin
        if (!clean_rst_n) begin
            mac_ovf_d <= 1'b0;
            mac_unf_d <= 1'b0;
        end else begin
            mac_ovf_d <= mac_tx_ovfout;  
            mac_unf_d <= mac_tx_unfout;  
        end
    end

    // =========================================================================
    // UDP 配置 AXI4-Lite 接口
    // =========================================================================
    udp_100g_config_slave u_udp_cfg (
        .s_axi_aclk             (usr_mac_clk),
        .s_axi_aresetn          (~sys_reset_sync), 
        .s_axi_awaddr           (s_udp_cfg_axi_awaddr),
        .s_axi_awvalid          (s_udp_cfg_axi_awvalid),
        .s_axi_awready          (s_udp_cfg_axi_awready),
        .s_axi_wdata            (s_udp_cfg_axi_wdata),
        .s_axi_wstrb            (s_udp_cfg_axi_wstrb),
        .s_axi_wvalid           (s_udp_cfg_axi_wvalid),
        .s_axi_wready           (s_udp_cfg_axi_wready),
        .s_axi_bresp            (s_udp_cfg_axi_bresp),
        .s_axi_bvalid           (s_udp_cfg_axi_bvalid),
        .s_axi_bready           (s_udp_cfg_axi_bready),
        .s_axi_araddr           (s_udp_cfg_axi_araddr),
        .s_axi_arvalid          (s_udp_cfg_axi_arvalid),
        .s_axi_arready          (s_udp_cfg_axi_arready),
        .s_axi_rdata            (s_udp_cfg_axi_rdata),
        .s_axi_rresp            (s_udp_cfg_axi_rresp),
        .s_axi_rvalid           (s_udp_cfg_axi_rvalid),
        .s_axi_rready           (s_udp_cfg_axi_rready),
        .cfg_local_mac          (cfg_local_mac),
        .cfg_local_ip           (cfg_local_ip),
        .cfg_dest_mac           (cfg_dest_mac),
        .cfg_dest_ip            (cfg_dest_ip),
        .cfg_src_port           (cfg_src_port),
        .cfg_dest_port          (cfg_dest_port),
        .cfg_udp_payload_beats  (cfg_udp_payload_beats), // 悬空不用，仅保持连接不报错
        .cfg_vlan_enable        (cfg_vlan_enable),
        .stat_cnt_rx_arp        (stat_cnt_rx_arp),
        .stat_cnt_rx_icmp       (stat_cnt_rx_icmp),
        .stat_cnt_rx_udp        (stat_cnt_rx_udp),
        .stat_cnt_rx_drop       (stat_cnt_rx_drop),
        .stat_cnt_rx_err        (stat_cnt_rx_err),
        .stat_cnt_tx_udp        (stat_cnt_tx_udp),
        .stat_cnt_tx_len_mismatch (stat_cnt_tx_len_mismatch),
        .stat_cnt_tx_mac_ovf    (stat_cnt_tx_mac_ovf),
        .stat_cnt_tx_mac_unf    (stat_cnt_tx_mac_unf),
        .o_stat_clear_pulse     (stat_clear_pulse)
    );

    wire safe_mac_tx_tready = net_tx_tready & (!mac_tx_ovfout) & (!mac_tx_unfout);

    // =========================================================================
    // 接收数据进入 RX Demux
    // =========================================================================
    rx_demux u_demux (
        .clk               (usr_mac_clk),
        .rst_n             (clean_rst_n),
        .cfg_vlan_enable   (cfg_vlan_enable),
        .cfg_local_mac     (cfg_local_mac),
        .cfg_local_ip      (cfg_local_ip),
        .s_axis_tdata      (net_rx_tdata),
        .s_axis_tkeep      (net_rx_tkeep),
        .s_axis_tvalid     (net_rx_tvalid),
        .s_axis_tlast      (net_rx_tlast),
        .s_axis_rx_err     (net_rx_tuser),
        .m0_axis_tdata     (demux_m0_tdata),      
        .m0_axis_tvalid    (demux_m0_vld),
        .m0_axis_tlast     (demux_m0_last),
        .m1_axis_tdata     (demux_m1_tdata),      
        .m1_axis_tkeep     (demux_m1_tkeep),
        .m1_axis_tvalid    (demux_m1_vld),
        .m1_axis_tlast     (demux_m1_last),
        .m2_axis_tdata     (demux_m2_tdata),
        .m2_axis_tkeep     (demux_m2_tkeep),
        .m2_axis_tvalid    (demux_m2_vld),
        .m2_axis_tlast     (demux_m2_last),
        .m3_axis_tdata     (demux_m3_tdata),
        .m3_axis_tkeep     (demux_m3_tkeep),
        .m3_axis_tvalid    (demux_m3_vld),
        .m3_axis_tlast     (demux_m3_last),
        .o_stat_rx_arp     (st_rx_arp_pulse),
        .o_stat_rx_icmp    (st_rx_icmp_pulse),
        .o_stat_rx_udp     (st_rx_udp_pulse),
        .o_stat_rx_cmd     (st_rx_cmd_pulse),
        .o_stat_rx_drop    (st_rx_drop_pulse),
        .o_stat_rx_err     (st_rx_err_pulse)
    );

    // =========================================================================
    // 统计脉冲处理模块
    // =========================================================================
    udp_100g_statistics u_stats (
        .clk                   (usr_mac_clk),
        .rst_n                 (clean_rst_n),
        .pulse_rx_arp          (st_rx_arp_pulse),
        .pulse_rx_icmp         (st_rx_icmp_pulse),
        .pulse_rx_udp          (st_rx_udp_pulse),
        .pulse_rx_drop         (st_rx_drop_pulse),
        .pulse_rx_err          (st_rx_err_pulse),
        .pulse_tx_udp          (fr_stat_tx_udp),
        .pulse_tx_len_mismatch (fr_stat_tx_len_bad),
        .pulse_tx_mac_ovf      (pulse_mac_ovf),
        .pulse_tx_mac_unf      (pulse_mac_unf),
        .clear_all             (stat_clear_pulse),
        .cnt_rx_arp            (stat_cnt_rx_arp),
        .cnt_rx_icmp           (stat_cnt_rx_icmp),
        .cnt_rx_udp            (stat_cnt_rx_udp),
        .cnt_rx_drop           (stat_cnt_rx_drop),
        .cnt_rx_err            (stat_cnt_rx_err),
        .cnt_tx_udp            (stat_cnt_tx_udp),
        .cnt_tx_len_mismatch   (stat_cnt_tx_len_mismatch),
        .cnt_tx_mac_ovf        (stat_cnt_tx_mac_ovf),
        .cnt_tx_mac_unf        (stat_cnt_tx_mac_unf)
    );

    // =========================================================================
    // [1] ARP 响应模块
    // =========================================================================
    arp_responder u_arp (
        .clk              (usr_mac_clk),
        .rst_n            (clean_rst_n),
        .cfg_vlan_enable  (cfg_vlan_enable),
        .local_mac        (cfg_local_mac),
        .local_ip         (cfg_local_ip),
        .s_axis_rx_tdata  (demux_m0_tdata),     
        .s_axis_rx_tvalid (demux_m0_vld),
        .s_axis_rx_tlast  (demux_m0_last),
        .m_axis_tx_tdata  (arp_tx_tdata),
        .m_axis_tx_tkeep  (arp_tx_tkeep),
        .m_axis_tx_tvalid (arp_tx_tvalid),
        .m_axis_tx_tlast  (arp_tx_tlast),
        .m_axis_tx_tready (arp_tx_tready)
    );

    // =========================================================================
    // [2] ICMP (Ping) 响应模块
    // =========================================================================
    icmp_responder u_icmp (
        .clk              (usr_mac_clk),
        .rst_n            (clean_rst_n),
        .cfg_vlan_enable  (cfg_vlan_enable),
        .local_ip         (cfg_local_ip),
        .s_axis_rx_tdata  (demux_m1_tdata),     
        .s_axis_rx_tkeep  (demux_m1_tkeep),
        .s_axis_rx_tvalid (demux_m1_vld),
        .s_axis_rx_tlast  (demux_m1_last),
        .m_axis_tx_tdata  (icmp_tx_tdata),
        .m_axis_tx_tkeep  (icmp_tx_tkeep),
        .m_axis_tx_tvalid (icmp_tx_tvalid),
        .m_axis_tx_tlast  (icmp_tx_tlast),
        .m_axis_tx_tready (icmp_tx_tready)
    );

    // =========================================================================
    // [3] UDP Deframer 模块 (升级版：输出动态长度)
    // =========================================================================
    udp_100g_deframer_pro u_deframer (
        .clk                 (usr_mac_clk),
        .rst_n               (clean_rst_n),
        .s_axis_tdata        (demux_m2_tdata),      
        .s_axis_tkeep        (demux_m2_tkeep),
        .s_axis_tvalid       (demux_m2_vld),
        .s_axis_tlast        (demux_m2_last),
        .s_axis_tready       (),                    
        .m_axis_tdata        (udp_rx_raw_tdata),    
        .m_axis_tkeep        (udp_rx_raw_tkeep),
        .m_axis_tvalid       (udp_rx_raw_tvalid),
        .m_axis_tlast        (udp_rx_raw_tlast),
        .m_axis_tready       (udp_rx_raw_tready),
        // 【修改点】：接入外部新增端口
        .o_payload_cmd_valid (o_payload_cmd_valid),
        .o_payload_bytes     (o_payload_bytes)
    );

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(256),
        .READ_DATA_WIDTH(577),
        .READ_MODE("fwft"),
        .WRITE_DATA_WIDTH(577)
    ) u_udp_rx_fifo (
        .rst(~clean_rst_n),
        .wr_clk(usr_mac_clk),
        .wr_en(udp_rx_raw_tvalid && udp_rx_raw_tready),
        .din({udp_rx_raw_tlast, udp_rx_raw_tkeep, udp_rx_raw_tdata}),
        .full(udp_rx_fifo_full),
        .rd_en(udp_rx_fifo_rd_en),
        .dout(udp_rx_fifo_dout),
        .empty(udp_rx_fifo_empty),
        .sleep(1'b0)
    );

    // =========================================================================
    // [3b] UDP 命令解析器 (端口 8001 控制面)
    // =========================================================================
    udp_cmd_parser u_cmd_parser (
        .clk                (usr_mac_clk),
        .rst_n              (clean_rst_n),
        .s_axis_tdata       (demux_m3_tdata),
        .s_axis_tkeep       (demux_m3_tkeep),
        .s_axis_tvalid      (demux_m3_vld),
        .s_axis_tlast       (demux_m3_last),
        .s_axis_tready      (),
        .m_axis_tdata       (cmd_tx_tdata),
        .m_axis_tkeep       (cmd_tx_tkeep),
        .m_axis_tvalid      (cmd_tx_tvalid),
        .m_axis_tlast       (cmd_tx_tlast),
        .m_axis_tready      (cmd_tx_tready),
        .cfg_local_mac      (cfg_local_mac),
        .cfg_local_ip       (cfg_local_ip),
        .cfg_dest_mac       (cfg_dest_mac),
        .cfg_dest_ip        (cfg_dest_ip),
        .cfg_src_port       (cfg_src_port),
        .cfg_dest_port      (cfg_dest_port),
        .cfg_vlan_enable    (cfg_vlan_enable),
        .ctrl_start_rec     (ctrl_start_rec),
        .ctrl_stop_rec      (ctrl_stop_rec),
        .ctrl_start_play    (ctrl_start_play),
        .ctrl_stop_play     (ctrl_stop_play),
        .ctrl_base_addr     (ctrl_base_addr),
        .ctrl_soft_reset    (ctrl_soft_reset),
        .stat_s2mm_cmd_cnt  (stat_s2mm_cmd_cnt),
        .stat_mm2s_cmd_cnt  (stat_mm2s_cmd_cnt),
        .stat_rx_wr_count   (stat_rx_wr_count),
        .stat_tx_wr_count   (stat_tx_wr_count),
        .stat_s2mm_err      (stat_s2mm_err),
        .stat_mm2s_err      (stat_mm2s_err)
    );

    assign udp_rx_raw_tready = !udp_rx_fifo_full;
    assign udp_rx_fifo_rd_en = m_axis_rx_tready && !udp_rx_fifo_empty;
    assign m_axis_rx_tvalid  = !udp_rx_fifo_empty;
    assign m_axis_rx_tlast   = udp_rx_fifo_dout[576];
    assign m_axis_rx_tkeep   = udp_rx_fifo_dout[575:512];
    assign m_axis_rx_tdata   = udp_rx_fifo_dout[511:0];

    // =========================================================================
    // [4] UDP Framer 模块 (升级版：接收动态长度)
    // =========================================================================
    udp_100g_framer_pro u_framer (
        .clk                   (usr_mac_clk),
        .rst_n                 (clean_rst_n),
        .s_axis_tdata          (s_axis_tx_tdata),    
        .s_axis_tkeep          (s_axis_tx_tkeep),
        .s_axis_tvalid         (s_axis_tx_tvalid),
        .s_axis_tlast          (s_axis_tx_tlast),
//        .s_axis_tuser          (s_axis_tx_tuser),
        .s_axis_tready         (s_axis_tx_tready),
        
        // 【修改点】：动态长度代替原先的 cfg_udp_payload_beats
        .i_tx_payload_bytes    (i_tx_payload_bytes),
        .tx_meta_empty         (tx_meta_empty),
        
        .cfg_dest_mac          (cfg_dest_mac),
        .cfg_local_mac         (cfg_local_mac),
        .cfg_local_ip          (cfg_local_ip),
        .cfg_dest_ip           (cfg_dest_ip),
        .cfg_src_port          (cfg_src_port),
        .cfg_dest_port         (cfg_dest_port),
        
        .m_axis_tdata          (udp_tx_tdata),       
        .m_axis_tkeep          (udp_tx_tkeep),
        .m_axis_tvalid         (udp_tx_tvalid),
        .m_axis_tlast          (udp_tx_tlast),
        .m_axis_tready         (udp_tx_tready),
        .o_stat_tx_udp         (fr_stat_tx_udp),
        .o_meta_rd_en          (fr_meta_rd_en)
    );

    // =========================================================================
    // [5] TX 发送优先级复用
    // =========================================================================
    axis_tx_arbiter u_arbiter (
        .clk             (usr_mac_clk),
        .rst_n           (clean_rst_n),
        .s0_axis_tdata   (arp_tx_tdata),  .s0_axis_tkeep  (arp_tx_tkeep),  .s0_axis_tvalid (arp_tx_tvalid),  .s0_axis_tlast (arp_tx_tlast),  .s0_axis_tready (arp_tx_tready),
        .s1_axis_tdata   (icmp_tx_tdata), .s1_axis_tkeep  (icmp_tx_tkeep), .s1_axis_tvalid (icmp_tx_tvalid), .s1_axis_tlast (icmp_tx_tlast), .s1_axis_tready (icmp_tx_tready),
        .s2_axis_tdata   (udp_tx_tdata),  .s2_axis_tkeep  (udp_tx_tkeep),  .s2_axis_tvalid (udp_tx_tvalid),  .s2_axis_tlast (udp_tx_tlast),  .s2_axis_tready (udp_tx_tready),
        .s3_axis_tdata   (cmd_tx_tdata),  .s3_axis_tkeep  (cmd_tx_tkeep),  .s3_axis_tvalid (cmd_tx_tvalid),  .s3_axis_tlast (cmd_tx_tlast),  .s3_axis_tready (cmd_tx_tready),
        .m_axis_tdata    (net_tx_tdata),  .m_axis_tkeep   (net_tx_tkeep),  .m_axis_tvalid  (net_tx_tvalid),  .m_axis_tlast  (net_tx_tlast),  .m_axis_tready  (safe_mac_tx_tready)
    );

    // =========================================================================
    // AXI 控制 CMAC IP
    // =========================================================================
    cmac_axi_master u_axi_master (
        .s_axi_aclk (init_clk), .s_axi_sreset (sys_reset),
        .s_axi_awaddr (s_axi_awaddr), .s_axi_awvalid (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata (s_axi_wdata), .s_axi_wstrb (s_axi_wstrb), .s_axi_wvalid (s_axi_wvalid), .s_axi_wready (s_axi_wready),
        .s_axi_bresp (s_axi_bresp), .s_axi_bvalid (s_axi_bvalid), .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr), .s_axi_arvalid (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rdata (s_axi_rdata), .s_axi_rresp (s_axi_rresp), .s_axi_rvalid (s_axi_rvalid), .s_axi_rready (s_axi_rready),
        .axi_init_done (axi_init_done)
    );

    // =========================================================================
    // CMAC UltraScale+ IP 实例
    // =========================================================================
    cmac_usplus_0 DUT (
        .gt_txp_out (gt_txp_out),
        .gt_txn_out (gt_txn_out),
        .gt_rxp_in (gt_rxp_in),
        .gt_rxn_in (gt_rxn_in),
        .gt_ref_clk_p (gt_ref_clk_p),
        .gt_ref_clk_n (gt_ref_clk_n),
        .gt_txusrclk2 (cmac_txusrclk2),
        .gt_rxusrclk2 (),
        .gt_loopback_in (12'h000),
        .gt_ref_clk_out (),
        .gt_rxrecclkout (),
        .gt_powergoodout (gt_powergoodout),
        .gtwiz_reset_tx_datapath (1'b0),
        .gtwiz_reset_rx_datapath (1'b0),
        
        .s_axi_aclk (init_clk),
        .s_axi_sreset (sys_reset),
        .pm_tick (1'b0),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata (s_axi_wdata),
        .s_axi_wstrb (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata (s_axi_rdata),
        .s_axi_rresp (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        
        .sys_reset (sys_reset),
        .init_clk (init_clk),
        
        .rx_clk (cmac_txusrclk2),
        .usr_tx_reset (cmac_usr_tx_reset),
        .usr_rx_reset (cmac_usr_rx_reset),
        .core_tx_reset (1'b0),
        .core_rx_reset (1'b0),
        .rx_axis_tvalid (net_rx_tvalid),
        .rx_axis_tdata (net_rx_tdata),
        .rx_axis_tlast (net_rx_tlast),
        .rx_axis_tkeep (net_rx_tkeep),
        .rx_axis_tuser (net_rx_tuser),
        
        .tx_axis_tready (net_tx_tready),
        .tx_axis_tvalid (net_tx_tvalid),
        .tx_axis_tdata (net_tx_tdata),
        .tx_axis_tlast (net_tx_tlast),
        .tx_axis_tkeep (net_tx_tkeep),
        .tx_axis_tuser (1'b0),
        
        .tx_ovfout (mac_tx_ovfout),
        .tx_unfout (mac_tx_unfout),
        .tx_preamblein (56'd0),
        .ctl_tx_send_idle (1'b0),
        .ctl_tx_send_rfi (1'b0),
        .ctl_tx_send_lfi (1'b0),
        .stat_rx_aligned (stat_rx_aligned),
        .stat_rx_aligned_err (stat_rx_aligned_err),
        .stat_rx_status (stat_rx_status),
            .stat_rx_local_fault (stat_rx_local_fault),
            .stat_rx_remote_fault (stat_rx_remote_fault),
            .stat_tx_local_fault (stat_tx_local_fault),
            .stat_rx_hi_ber (stat_rx_hi_ber),
            .stat_rx_block_lock (stat_rx_block_lock),
        
        .ctl_tx_pause_req (tx_pause_req),
        .ctl_tx_resend_pause (1'b0),
        
        .user_reg0 (),

        .stat_rx_rsfec_am_lock0 (),
        .stat_rx_rsfec_am_lock1 (),
        .stat_rx_rsfec_am_lock2 (),
        .stat_rx_rsfec_am_lock3 (),
        .stat_rx_rsfec_corrected_cw_inc (),
        .stat_rx_rsfec_cw_inc (),
        .stat_rx_rsfec_err_count0_inc (),
        .stat_rx_rsfec_err_count1_inc (),
        .stat_rx_rsfec_err_count2_inc (),
        .stat_rx_rsfec_err_count3_inc (),
        .stat_rx_rsfec_hi_ser (stat_rx_rsfec_hi_ser),
        .stat_rx_rsfec_lane_alignment_status (stat_rx_rsfec_lane_alignment_status),
        .stat_rx_rsfec_lane_fill_0 (),
        .stat_rx_rsfec_lane_fill_1 (),
        .stat_rx_rsfec_lane_fill_2 (),
        .stat_rx_rsfec_lane_fill_3 (),
        .stat_rx_rsfec_lane_mapping (),
        .stat_rx_rsfec_uncorrected_cw_inc (),

        .core_drp_reset (1'b0),
        .drp_clk (1'b0),
        .drp_addr (10'd0),
        .drp_di (16'd0),
        .drp_en (1'b0),
        .drp_we (1'b0),
        .drp_do (),
        .drp_rdy ()
    );

    assign o_tx_meta_rd_en = fr_meta_rd_en;

endmodule
