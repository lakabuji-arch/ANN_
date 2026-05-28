`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: udp_100g_config_slave
// 功能描述: UDP/以太网参数 AXI4-Lite 从机接口 + 只读统计寄存器
// 详细说明:
//           该模块实现了一个 AXI4-Lite 从机接口，用于：
//           1. 配置 UDP/以太网网络参数（MAC地址、IP地址、端口等）
//           2. 提供只读统计寄存器接口，可读取各种数据包统计信息
//           3. 支持通过写入特定值来清除所有统计计数器
//
// 时钟域: 与 usr_mac_clk 同源（wrapper 内接入）
// 复位: 异步复位（低电平有效）
//
// 寄存器映射（addr[7:0]）：
//   可写寄存器（写操作）：
//     0x00 - 本地 MAC 地址高 16 位 [47:32]
//     0x04 - 本地 MAC 地址低 32 位 [31:0]
//     0x08 - 本地 IP 地址 [31:0]
//     0x0C - 目标 MAC 地址高 16 位 [47:32]
//     0x10 - 目标 MAC 地址低 32 位 [31:0]
//     0x14 - 目标 IP 地址 [31:0]
//     0x18 - 源端口 [31:16] / 目标端口 [15:0]
//     0x1C - UDP payload beats 数 [15:0]
//     0x24 - 控制寄存器：bit0 = cfg_vlan_enable
//            (1=解析 802.1Q VLAN 内层 EthType, 0=不解析)
//
//   只读寄存器（读操作）：
//     0x00 - 本地 MAC 地址高 16 位
//     0x04 - 本地 MAC 地址低 32 位
//     0x08 - 本地 IP 地址
//     0x0C - 目标 MAC 地址高 16 位
//     0x10 - 目标 MAC 地址低 32 位
//     0x14 - 目标 IP 地址
//     0x18 - 源端口 [31:16] / 目标端口 [15:0]
//     0x1C - UDP payload beats 数
//     0x20 - 版本号 (0x0002_0000 = map v2)
//     0x24 - VLAN 使能标志
//     0x28 - 接收 ARP 包计数
//     0x2C - 接收 ICMP 包计数
//     0x30 - 接收 UDP 包计数
//     0x34 - 接收丢弃包计数
//     0x38 - 接收错误包计数
//     0x3C - 发送 UDP 包计数
//     0x40 - 发送长度不匹配计数
//     0x44 - 发送 MAC 溢出计数
//     0x48 - 发送 MAC 下溢计数
//
//   清除统计寄存器：
//     0x54 - 写入 0x5A5A_5A5A 清除全部统计（需 wstrb 全 F）
////////////////////////////////////////////////////////////////////////////////

module udp_100g_config_slave (
    // AXI4-Lite 接口时钟和复位
    input  wire        s_axi_aclk,        // AXI 时钟信号
    input  wire        s_axi_aresetn,     // AXI 复位信号，低电平有效

    // AXI4-Lite 写地址通道
    input  wire [31:0] s_axi_awaddr,      // 写地址
    input  wire        s_axi_awvalid,     // 写地址有效
    output wire        s_axi_awready,     // 写地址就绪

    // AXI4-Lite 写数据通道
    input  wire [31:0] s_axi_wdata,       // 写数据
    input  wire [3:0]  s_axi_wstrb,       // 写数据选通信号（字节使能）
    input  wire        s_axi_wvalid,      // 写数据有效
    output wire        s_axi_wready,      // 写数据就绪

    // AXI4-Lite 写响应通道
    output wire [1:0]  s_axi_bresp,       // 写响应（00=OKAY）
    output reg         s_axi_bvalid,      // 写响应有效
    input  wire        s_axi_bready,      // 写响应就绪

    // AXI4-Lite 读地址通道
    input  wire [31:0] s_axi_araddr,      // 读地址
    input  wire        s_axi_arvalid,     // 读地址有效
    output wire        s_axi_arready,     // 读地址就绪

    // AXI4-Lite 读数据通道
    output reg  [31:0] s_axi_rdata,       // 读数据
    output wire [1:0]  s_axi_rresp,       // 读响应（00=OKAY）
    output reg         s_axi_rvalid,      // 读数据有效
    input  wire        s_axi_rready,      // 读数据就绪

    // 配置参数输出
    output reg  [47:0] cfg_local_mac,            // 本地 MAC 地址
    output reg  [31:0] cfg_local_ip,             // 本地 IP 地址
    output reg  [47:0] cfg_dest_mac,             // 目标 MAC 地址
    output reg  [31:0] cfg_dest_ip,              // 目标 IP 地址
    output reg  [15:0] cfg_src_port,             // UDP 源端口
    output reg  [15:0] cfg_dest_port,            // UDP 目标端口
    output reg  [15:0] cfg_udp_payload_beats,    // UDP payload 的 AXI beats 数
    output reg         cfg_vlan_enable,          // VLAN 解析使能（1=解析 802.1Q 内层 EthType）

    // 统计计数器输入（来自 udp_100g_statistics 模块）
    input wire [31:0] stat_cnt_rx_arp,           // 接收 ARP 包计数
    input wire [31:0] stat_cnt_rx_icmp,          // 接收 ICMP 包计数
    input wire [31:0] stat_cnt_rx_udp,           // 接收 UDP 包计数
    input wire [31:0] stat_cnt_rx_drop,          // 接收丢弃包计数
    input wire [31:0] stat_cnt_rx_err,           // 接收错误包计数
    input wire [31:0] stat_cnt_tx_udp,           // 发送 UDP 包计数
    input wire [31:0] stat_cnt_tx_len_mismatch,  // 发送长度不匹配计数
    input wire [31:0] stat_cnt_tx_mac_ovf,       // 发送 MAC 溢出计数
    input wire [31:0] stat_cnt_tx_mac_unf,       // 发送 MAC 下溢计数

    // 统计计数器清零脉冲输出
    output wire        o_stat_clear_pulse        // 统计计数器清零脉冲（高电平有效一个时钟周期）
);

    // 寄存器映射版本号：0x0003_0414 表示 map v3 (2026-04-14)
    localparam logic [31:0] REGMAP_VERSION = 32'h0003_0414;

    // =========================================================================
    // AXI4-Lite 写通道逻辑
    // =========================================================================
    
    // 写就绪信号：当没有待处理的写响应时，表示准备好接收新写事务
    assign s_axi_awready = ~s_axi_bvalid;
    assign s_axi_wready  = ~s_axi_bvalid;
    assign s_axi_bresp   = 2'b00;  // 写响应始终为 OKAY

    // 写使能信号：地址和数据通道都有效且就绪时，表示一次有效的写操作
    wire wr_en = s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready;

    // 统计清除请求检测：
    // 当写入地址 0x54，数据为 0x5A5A_5A5A，且所有字节选通信号有效时触发
    wire stats_clear_req = wr_en && (s_axi_awaddr[7:0] == 8'h54)
        && (s_axi_wdata == 32'h5A5A_5A5A) && (&s_axi_wstrb);

    // 清零脉冲生成：将清除请求同步为一个时钟周期的脉冲
    reg clr_pulse;
    assign o_stat_clear_pulse = clr_pulse;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            clr_pulse <= 1'b0;
        else
            clr_pulse <= stats_clear_req;  // 清除请求延迟一个时钟周期形成脉冲
    end

    // 配置寄存器更新逻辑：处理 AXI 写操作
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid          <= 1'b0;
            // 配置寄存器复位默认值
            cfg_local_mac         <= 48'h00_0A_35_01_02_03;  // 默认本地 MAC
            cfg_local_ip          <= 32'hC0_A8_01_14;        // 默认本地 IP (192.168.1.20)
            cfg_dest_mac          <= 48'hE4_54_E8_11_22_33;  // 默认目标 MAC
            cfg_dest_ip           <= 32'hC0_A8_01_0A;        // 默认目标 IP (192.168.1.10)
            cfg_src_port          <= 16'h1F40;               // 默认源端口 (8000)
            cfg_dest_port         <= 16'h1F40;               // 默认目标端口 (8000)
            cfg_udp_payload_beats <= 16'd16;                 // 默认 payload beats 数
            cfg_vlan_enable       <= 1'b0;                   // 默认关闭 VLAN（PC 网卡通常不认）
        end else begin
            if (wr_en) begin
                s_axi_bvalid <= 1'b1;  // 置位写响应有效
                case (s_axi_awaddr[7:0])
                    8'h00:  // 本地 MAC 地址高 16 位
                        if (s_axi_wstrb[1] | s_axi_wstrb[0])
                            cfg_local_mac[47:32] <= s_axi_wdata[15:0];
                    8'h04:  // 本地 MAC 地址低 32 位
                        cfg_local_mac[31:0] <= s_axi_wdata;
                    8'h08:  // 本地 IP 地址
                        cfg_local_ip <= s_axi_wdata;
                    8'h0C:  // 目标 MAC 地址高 16 位
                        if (s_axi_wstrb[1] | s_axi_wstrb[0])
                            cfg_dest_mac[47:32] <= s_axi_wdata[15:0];
                    8'h10:  // 目标 MAC 地址低 32 位
                        cfg_dest_mac[31:0] <= s_axi_wdata;
                    8'h14:  // 目标 IP 地址
                        cfg_dest_ip <= s_axi_wdata;
                    8'h18:  // 源端口和目标端口
                        begin
                            if (s_axi_wstrb[3] | s_axi_wstrb[2]) cfg_src_port  <= s_axi_wdata[31:16];
                            if (s_axi_wstrb[1] | s_axi_wstrb[0]) cfg_dest_port <= s_axi_wdata[15:0];
                        end
                    8'h1C:  // UDP payload beats 数
                        cfg_udp_payload_beats <= s_axi_wdata[15:0];
                    8'h24:  // VLAN 解析使能
                        if (s_axi_wstrb[0]) cfg_vlan_enable <= s_axi_wdata[0];
                    8'h54:  // 统计清除寄存器（已在 stats_clear_req 中处理）
                        ;  // 空操作，清除逻辑已在前面的 clr_pulse 中处理
                    default: ;  // 其他地址不做处理
                endcase
            end else if (s_axi_bready && s_axi_bvalid) begin
                // 主机已接收写响应，清除写响应有效信号
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite 读通道逻辑
    // =========================================================================
    
    // 读就绪信号：当没有待处理的读数据时，表示准备好接收新读事务
    assign s_axi_arready = ~s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;  // 读响应始终为 OKAY

    // 读使能信号：地址通道有效且就绪时，表示一次有效的读操作
    wire rd_en = s_axi_arvalid && s_axi_arready;

    // 读数据输出逻辑：根据读地址返回相应寄存器或统计计数器的值
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else begin
            if (rd_en) begin
                s_axi_rvalid <= 1'b1;  // 置位读数据有效
                case (s_axi_araddr[7:0])
                    // 配置寄存器读取
                    8'h00: s_axi_rdata <= {16'd0, cfg_local_mac[47:32]};      // 本地 MAC 高 16 位
                    8'h04: s_axi_rdata <= cfg_local_mac[31:0];                // 本地 MAC 低 32 位
                    8'h08: s_axi_rdata <= cfg_local_ip;                       // 本地 IP
                    8'h0C: s_axi_rdata <= {16'd0, cfg_dest_mac[47:32]};      // 目标 MAC 高 16 位
                    8'h10: s_axi_rdata <= cfg_dest_mac[31:0];                // 目标 MAC 低 32 位
                    8'h14: s_axi_rdata <= cfg_dest_ip;                       // 目标 IP
                    8'h18: s_axi_rdata <= {cfg_src_port, cfg_dest_port};     // 源端口/目标端口
                    8'h1C: s_axi_rdata <= {16'd0, cfg_udp_payload_beats};    // UDP payload beats
                    8'h20: s_axi_rdata <= REGMAP_VERSION;                    // 版本号
                    8'h24: s_axi_rdata <= {31'd0, cfg_vlan_enable};          // VLAN 使能标志
                    // 统计计数器读取
                    8'h28: s_axi_rdata <= stat_cnt_rx_arp;                   // 接收 ARP 计数
                    8'h2C: s_axi_rdata <= stat_cnt_rx_icmp;                  // 接收 ICMP 计数
                    8'h30: s_axi_rdata <= stat_cnt_rx_udp;                   // 接收 UDP 计数
                    8'h34: s_axi_rdata <= stat_cnt_rx_drop;                  // 接收丢弃计数
                    8'h38: s_axi_rdata <= stat_cnt_rx_err;                   // 接收错误计数
                    8'h3C: s_axi_rdata <= stat_cnt_tx_udp;                   // 发送 UDP 计数
                    8'h40: s_axi_rdata <= stat_cnt_tx_len_mismatch;          // 发送长度不匹配计数
                    8'h44: s_axi_rdata <= stat_cnt_tx_mac_ovf;              // 发送 MAC 溢出计数
                    8'h48: s_axi_rdata <= stat_cnt_tx_mac_unf;              // 发送 MAC 下溢计数
                    default: s_axi_rdata <= 32'hDEAD_BEEF;                 // 未定义地址返回标记值
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                // 主机已接收读数据，清除读数据有效信号
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
