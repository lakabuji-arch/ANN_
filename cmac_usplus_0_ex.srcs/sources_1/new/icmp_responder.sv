`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: icmp_responder
// 功能描述: ICMP Echo Request 响应器（Ping 回复器 - 时序优化与安全防护升级版）
// 详细说明:
//           该模块用于接收 ICMP Echo Request（Ping 请求）并自动生成 Reply。
//           支持以下功能：
//           - 解析 VLAN 标签（802.1Q）或非 VLAN 帧
//           - 验证目标 IP 地址是否与本地 IP 匹配
//           - 验证 ICMP 类型是否为 Echo Request (Type=8)
//           - 自动交换源/目的 MAC 地址和 IP 地址
//           - 【时序优化】：多周期计算 ICMP 校验和，切断进位长链
//           - 【Bug修复】：修复了带 VLAN 时修改 Payload 偏移量错位的问题
//           - 【安全升级】：防范 Ping of Death，超大巨型帧将被安全截断排干，防数组越界
//           - 支持最大 24 个 beat 的数据包缓存（约 1536 字节）
//
// 时钟域: usr_mac_clk
// 复位: 异步复位（低电平有效）
////////////////////////////////////////////////////////////////////////////////

module icmp_responder (
    // 时钟和复位信号
    input  wire         clk,              // 时钟信号（usr_mac_clk 域）
    input  wire         rst_n,            // 异步复位，低电平有效
    
    // 配置信号
    input  wire         cfg_vlan_enable,  // VLAN 解析使能
    input  wire [31:0]  local_ip,         // 本地 IP 地址

    // AXI-Stream 接收接口（输入）
    input  wire [511:0] s_axis_rx_tdata,  
    input  wire [63:0]  s_axis_rx_tkeep,  
    input  wire         s_axis_rx_tvalid, 
    input  wire         s_axis_rx_tlast,  

    // AXI-Stream 发送接口（输出）- ICMP Reply
    output reg  [511:0] m_axis_tx_tdata,  
    output reg  [63:0]  m_axis_tx_tkeep,  
    output reg          m_axis_tx_tvalid, 
    output reg          m_axis_tx_tlast,  
    input  wire         m_axis_tx_tready  
);

    // =========================================================================
    // 数据包解析逻辑：根据 VLAN 使能状态解析以太网帧头
    // =========================================================================
    
    wire [15:0] eth_outer = {s_axis_rx_tdata[103:96], s_axis_rx_tdata[111:104]};
    wire        has_vlan  = cfg_vlan_enable && (eth_outer == 16'h8100);
    
    wire [15:0] eth_type  = has_vlan ? {s_axis_rx_tdata[135:128], s_axis_rx_tdata[143:136]} : eth_outer;
    wire [7:0]  ip_proto  = has_vlan ? s_axis_rx_tdata[223:216] : s_axis_rx_tdata[191:184];
    
    wire [31:0] target_ip = has_vlan
        ? {s_axis_rx_tdata[279:272], s_axis_rx_tdata[287:280], s_axis_rx_tdata[295:288], s_axis_rx_tdata[303:296]}
        : {s_axis_rx_tdata[247:240], s_axis_rx_tdata[255:248], s_axis_rx_tdata[263:256], s_axis_rx_tdata[271:264]};

    wire [7:0] icmp_type  = has_vlan ? s_axis_rx_tdata[311:304] : s_axis_rx_tdata[279:272];

    // =========================================================================
    // 数据包起始检测逻辑 (确保只在报文首拍触发)
    // =========================================================================
    reg pkt_mid;
    always_ff @(posedge clk) begin
        if (!rst_n)
            pkt_mid <= 1'b0;
        else if (s_axis_rx_tvalid)
            pkt_mid <= !s_axis_rx_tlast;
    end
    wire first_beat = s_axis_rx_tvalid && !pkt_mid;

    wire icmp_req_match = first_beat && (eth_type == 16'h0800) &&
                          (ip_proto == 8'h01) && (target_ip == local_ip) && (icmp_type == 8'h08);

    // =========================================================================
    // ICMP 校验和重新计算 (拆分为流水线，解决 WNS 时序违例)
    // =========================================================================
    wire [15:0] old_icmp_cs = has_vlan
        ? {s_axis_rx_tdata[327:320], s_axis_rx_tdata[335:328]}
        : {s_axis_rx_tdata[295:288], s_axis_rx_tdata[303:296]};

    // 第一级计算 (组合逻辑较短)
    wire [17:0] csum_wide = {2'b0, ~old_icmp_cs} + {2'b0, ~16'h0800} + 18'h0000;
    
    // 用于跨周期打拍的寄存器
    reg [17:0] r_csum_wide;
    reg        r_has_vlan;

    // 第二级计算 (在 CALC_CSUM 状态独立的一个周期内完成，保障时序完美)
    wire [16:0] calc_csum_fold = r_csum_wide[15:0] + r_csum_wide[16] + r_csum_wide[17];
    wire [15:0] calc_final_chk = ~(calc_csum_fold[15:0] + calc_csum_fold[16]);

    // =========================================================================
    // 数据包缓存与状态机
    // =========================================================================
    reg [511:0] pkt_buf [0:23];
    reg [63:0]  keep_buf [0:23];
    reg [4:0]   rx_cnt;
    reg [4:0]   tx_cnt;
    reg [4:0]   pkt_len;

    typedef enum logic [1:0] {IDLE=2'd0, RX_GATHER=2'd1, CALC_CSUM=2'd2, TX_REPLY=2'd3} state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            m_axis_tx_tvalid <= 1'b0;
            rx_cnt <= 0;
        end else begin
            case (state)
                // ------------------------------------------------------------------
                // IDLE 状态：等待 ICMP Echo Request
                // ------------------------------------------------------------------
                IDLE: begin
                    if (icmp_req_match) begin
                        pkt_buf[0]  <= s_axis_rx_tdata;
                        keep_buf[0] <= s_axis_rx_tkeep;

                        // 1. MAC 地址交换 (位置固定)
                        pkt_buf[0][47:0]   <= s_axis_rx_tdata[95:48];  // Dst = Src
                        pkt_buf[0][95:48]  <= s_axis_rx_tdata[47:0];   // Src = Dst
                        
                        // 2. IP 和 ICMP 字段修改 (严格区分有无 VLAN)
                        if (has_vlan) begin
                            pkt_buf[0][271:240] <= s_axis_rx_tdata[303:272]; // Src IP <- Dst IP
                            pkt_buf[0][303:272] <= s_axis_rx_tdata[271:240]; // Dst IP <- Src IP
                            pkt_buf[0][311:304] <= 8'h00;                    // 修改 ICMP Type 为 Reply
                        end else begin
                            pkt_buf[0][239:208] <= s_axis_rx_tdata[271:240]; // Src IP <- Dst IP
                            pkt_buf[0][271:240] <= s_axis_rx_tdata[239:208]; // Dst IP <- Src IP
                            pkt_buf[0][279:272] <= 8'h00;                    // 修改 ICMP Type 为 Reply
                        end

                        // 3. 锁存中间状态，用于下一拍计算
                        r_has_vlan  <= has_vlan;
                        r_csum_wide <= csum_wide;

                        if (s_axis_rx_tlast) begin
                            pkt_len <= 5'd1;
                            state   <= CALC_CSUM; // 重点：不直接发送，先去算校验和
                        end else begin
                            rx_cnt  <= 5'd1;
                            state   <= RX_GATHER;
                        end
                    end
                end

                // ------------------------------------------------------------------
                // RX_GATHER 状态：安全接收剩余 beats，防范巨型帧 (Ping of Death)
                // ------------------------------------------------------------------
                RX_GATHER: begin
                    if (s_axis_rx_tvalid) begin
                        // 1. 数组越界绝对防护：超出缓存深度的载荷将被丢弃，不写入内存
                        if (rx_cnt < 5'd24) begin
                            pkt_buf[rx_cnt]  <= s_axis_rx_tdata;
                            keep_buf[rx_cnt] <= s_axis_rx_tkeep;
                        end
                        
                        // 2. 报文结束判断，只有看到 tlast 才允许进入下一步
                        if (s_axis_rx_tlast) begin
                            // 如果是巨型帧被截断，只发前 24 拍；否则发送实际拍数
                            pkt_len <= (rx_cnt < 5'd24) ? (rx_cnt + 5'd1) : 5'd24;
                            state   <= CALC_CSUM; // 接收完毕，去算校验和
                        end else begin
                            // 3. 计数器饱和保护：防止 rx_cnt 溢出卷绕 (Wrap-around)
                            if (rx_cnt < 5'd31) begin
                                rx_cnt <= rx_cnt + 5'd1;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------------
                // CALC_CSUM 状态：【时序优化核心】单用一拍计算校验和并打补丁
                // ------------------------------------------------------------------
                CALC_CSUM: begin
                    if (r_has_vlan) begin
                        pkt_buf[0][327:320] <= calc_final_chk[15:8]; // 高字节
                        pkt_buf[0][335:328] <= calc_final_chk[7:0];  // 低字节
                    end else begin
                        pkt_buf[0][295:288] <= calc_final_chk[15:8]; 
                        pkt_buf[0][303:296] <= calc_final_chk[7:0];  
                    end
                    
                    state  <= TX_REPLY; // 补丁打完，启动发送
                    tx_cnt <= 5'd0;
                end

                // ------------------------------------------------------------------
                // TX_REPLY 状态：发送修改后的数据包 (完美时序对齐版)
                // ------------------------------------------------------------------
                TX_REPLY: begin
                    // 核心逻辑：如果当前没有发出有效数据，或者数据刚刚被成功握手接收
                    // 那么就立即准备下一个 Beat 的数据
                    if (!m_axis_tx_tvalid || (m_axis_tx_tvalid && m_axis_tx_tready)) begin
                        if (tx_cnt < pkt_len) begin
                            m_axis_tx_tvalid <= 1'b1;
                            m_axis_tx_tdata  <= pkt_buf[tx_cnt];
                            m_axis_tx_tkeep  <= keep_buf[tx_cnt];
                            m_axis_tx_tlast  <= (tx_cnt == pkt_len - 5'd1);
                            tx_cnt           <= tx_cnt + 5'd1;
                        end else begin
                            // 所有 Beat 发送完毕，收尾并回到监听状态
                            m_axis_tx_tvalid <= 1'b0;
                            m_axis_tx_tlast  <= 1'b0;
                            state            <= IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule