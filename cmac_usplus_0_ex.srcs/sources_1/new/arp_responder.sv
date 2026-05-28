`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: arp_responder
// 功能描述: ARP 请求响应器（自动生成 ARP 回复）
// 详细说明:
//           该模块用于接收 ARP Request 并自动生成 ARP Reply。
//           支持以下功能：
//           - 解析 VLAN 标签（802.1Q）或非 VLAN 帧
//           - 验证 ARP Request 的目标 IP 是否与本地 IP 匹配
//           - 自动构造 ARP Reply 数据包
//           - 交换源/目的 MAC 地址
//           - 将 ARP Opcode 从 Request (0x0001) 改为 Reply (0x0002)
//           - 单 beat 完成（在一个 512 位 AXI beat 内完成整个 ARP Reply）
//
// 时钟域: usr_mac_clk
// 复位: 异步复位（低电平有效）
////////////////////////////////////////////////////////////////////////////////

module arp_responder (
    // 时钟和复位
    input  wire         clk,              // 时钟信号（usr_mac_clk 域）
    input  wire         rst_n,            // 异步复位，低电平有效
    
    // 配置信号
    input  wire         cfg_vlan_enable,  // VLAN 解析使能
    input  wire [47:0]  local_mac,        // 本地 MAC 地址
    input  wire [31:0]  local_ip,         // 本地 IP 地址

    // AXI-Stream 接收接口（来自 Demux 的 ARP 通道）
    input  wire [511:0] s_axis_rx_tdata,  // 接收数据（512位）
    input  wire         s_axis_rx_tvalid, // 接收数据有效
    input  wire         s_axis_rx_tlast,  // 接收包最后一个 beat

    // AXI-Stream 发送接口（ARP Reply 发送到仲裁器）
    output reg  [511:0] m_axis_tx_tdata,  // 发送数据（512位）
    output reg  [63:0]  m_axis_tx_tkeep,  // 发送字节掩码
    output reg          m_axis_tx_tvalid, // 发送数据有效
    output reg          m_axis_tx_tlast,  // 发送包最后一个 beat
    input  wire         m_axis_tx_tready  // 发送端就绪（来自仲裁器）
);

    // =========================================================================
    // 数据包解析：根据 VLAN 状态解析以太网帧头
    // =========================================================================
    wire [15:0] eth_outer = {s_axis_rx_tdata[103:96], s_axis_rx_tdata[111:104]};
    wire        has_vlan  = cfg_vlan_enable && (eth_outer == 16'h8100);
    wire [15:0] eth_type  = has_vlan ? {s_axis_rx_tdata[135:128], s_axis_rx_tdata[143:136]} : eth_outer;

    // =========================================================================
    // ARP 字段解析
    // =========================================================================
    wire [15:0] arp_opcode = has_vlan
        ? {s_axis_rx_tdata[199:192], s_axis_rx_tdata[207:200]}
        : {s_axis_rx_tdata[167:160], s_axis_rx_tdata[175:168]};

    wire [31:0] target_ip = has_vlan
        ? {s_axis_rx_tdata[343:336], s_axis_rx_tdata[351:344], s_axis_rx_tdata[359:352], s_axis_rx_tdata[367:360]}
        : {s_axis_rx_tdata[311:304], s_axis_rx_tdata[319:312], s_axis_rx_tdata[327:320], s_axis_rx_tdata[335:328]};

    wire [47:0] sender_mac = has_vlan
        ? {s_axis_rx_tdata[215:208], s_axis_rx_tdata[223:216], s_axis_rx_tdata[231:224], s_axis_rx_tdata[239:232],
           s_axis_rx_tdata[247:240], s_axis_rx_tdata[255:248]}
        : {s_axis_rx_tdata[183:176], s_axis_rx_tdata[191:184], s_axis_rx_tdata[199:192], s_axis_rx_tdata[207:200],
           s_axis_rx_tdata[215:208], s_axis_rx_tdata[223:216]};

    wire [31:0] sender_ip = has_vlan
        ? {s_axis_rx_tdata[263:256], s_axis_rx_tdata[271:264], s_axis_rx_tdata[279:272], s_axis_rx_tdata[287:280]}
        : {s_axis_rx_tdata[231:224], s_axis_rx_tdata[239:232], s_axis_rx_tdata[247:240], s_axis_rx_tdata[255:248]};

    // =========================================================================
    // 数据包起始检测逻辑
    // =========================================================================
    reg pkt_mid;
    always_ff @(posedge clk) begin
        if (!rst_n)
            pkt_mid <= 1'b0;
        else if (s_axis_rx_tvalid)
            pkt_mid <= !s_axis_rx_tlast; 
    end

    wire first_beat = s_axis_rx_tvalid && !pkt_mid;

    // =========================================================================
    // ARP Request 匹配检测
    // =========================================================================
    wire arp_req_match = first_beat && (eth_type == 16'h0806) && 
                         (arp_opcode == 16'h0001) && (target_ip == local_ip);

    // =========================================================================
    // ARP Reply 生成逻辑
    // =========================================================================
    reg arp_trigger;            
    reg [47:0] req_sender_mac;  
    reg [31:0] req_sender_ip;   

    always @(posedge clk) begin
        if (!rst_n) begin
            arp_trigger      <= 1'b0;
            m_axis_tx_tvalid <= 1'b0;
        end else begin
            // 阶段 1: 捕获 ARP Request 信息
            if (arp_req_match && !arp_trigger && !m_axis_tx_tvalid) begin
                req_sender_mac <= sender_mac;  
                req_sender_ip  <= sender_ip;   
                arp_trigger    <= 1'b1;        
            end

            // 阶段 2: 构造并发送 ARP Reply
            if (arp_trigger && !m_axis_tx_tvalid) begin
                m_axis_tx_tvalid <= 1'b1;  
                m_axis_tx_tlast  <= 1'b1;  
                
                // 【修复点】：以太网最短帧长要求至少 60 字节载荷 (包含 FCS 为 64 字节)
                // 强制将 tkeep 设置为 60 字节有效 (60个1)，防止被当做 Runt Frame 丢弃
                m_axis_tx_tkeep  <= 64'h0FFF_FFFF_FFFF_FFFF;

                m_axis_tx_tdata  <= {
                    // Padding: 512 - (60*8) = 32 位填充 (配合 tkeep 截断即可)
                    // 原本的 176'd0 足够长，直接复用以补齐后面的 18 字节 0
                    176'd0,  

                    // Target IP 
                    req_sender_ip[7:0], req_sender_ip[15:8], req_sender_ip[23:16], req_sender_ip[31:24],

                    // Target MAC
                    req_sender_mac[7:0], req_sender_mac[15:8], req_sender_mac[23:16], 
                    req_sender_mac[31:24], req_sender_mac[39:32], req_sender_mac[47:40],

                    // Sender IP 
                    local_ip[7:0], local_ip[15:8], local_ip[23:16], local_ip[31:24],

                    // Sender MAC 
                    local_mac[7:0], local_mac[15:8], local_mac[23:16], 
                    local_mac[31:24], local_mac[39:32], local_mac[47:40],

                    // Opcode: Reply (0x0002)
                    8'h02, 8'h00,

                    // Proto Size (4), HW Size (6)
                    8'h04, 8'h06,

                    // Proto Type: IPv4 (0x0800)
                    8'h00, 8'h08,

                    // HW Type: Ethernet (0x0001)
                    8'h01, 8'h00,

                    // EtherType: ARP (0x0806)
                    8'h06, 8'h08,

                    // Source MAC
                    local_mac[7:0], local_mac[15:8], local_mac[23:16], 
                    local_mac[31:24], local_mac[39:32], local_mac[47:40],

                    // Destination MAC
                    req_sender_mac[7:0], req_sender_mac[15:8], req_sender_mac[23:16], 
                    req_sender_mac[31:24], req_sender_mac[39:32], req_sender_mac[47:40]
                };
                
                arp_trigger <= 1'b0;
            end

            // 阶段 3: 发送完成后，清除有效信号
            if (m_axis_tx_tvalid && m_axis_tx_tready) begin
                m_axis_tx_tvalid <= 1'b0;
                m_axis_tx_tlast  <= 1'b0;
            end
        end
    end
endmodule