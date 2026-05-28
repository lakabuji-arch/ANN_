`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: rx_demux
// 功能描述: 接收数据分类器（时序优化版：全寄存器输出）
// 详细说明:
//           该模块用于解析接收到的以太网帧，并分发到不同的输出通道。
//           支持 VLAN 解析及错误包丢弃。
//
//           【时序优化核心】：
//           针对 322MHz/512-bit 的严苛时序，将原本组合逻辑直接输出的
//           多路选择器，改造成了 1 级流水线（Output Pipeline）。
//           由于 MAC RX 侧无需处理反压（无 tready），直接打拍是最优雅、
//           最省资源的时序收敛方案。
//
// 时钟域: usr_mac_clk
// 复位: 异步复位（低电平有效）
////////////////////////////////////////////////////////////////////////////////

module rx_demux (
    // 时钟和复位
    input  wire         clk,        
    input  wire         rst_n,           

    // 配置信号
    input  wire         cfg_vlan_enable, 
    input  wire [47:0]  cfg_local_mac,
    input  wire [31:0]  cfg_local_ip,

    // 输入 AXI-Stream 接口（来自 CMAC，无 tready）
    input  wire [511:0] s_axis_tdata,     
    input  wire [63:0]  s_axis_tkeep,    
    input  wire         s_axis_tvalid,    
    input  wire         s_axis_tlast,     
    input  wire         s_axis_rx_err,    

    // 输出通道 0: ARP（只传输数据，不需要 tkeep）
    output reg  [511:0] m0_axis_tdata,    
    output reg          m0_axis_tvalid,   
    output reg          m0_axis_tlast,    

    // 输出通道 1: ICMP（需要 tkeep）
    output reg  [511:0] m1_axis_tdata,    
    output reg  [63:0]  m1_axis_tkeep,    
    output reg          m1_axis_tvalid,   
    output reg          m1_axis_tlast,    

    // 输出通道 2: UDP 端口 8000 → Deframer / 数据面
    output reg  [511:0] m2_axis_tdata,
    output reg  [63:0]  m2_axis_tkeep,
    output reg          m2_axis_tvalid,
    output reg          m2_axis_tlast,

    // 输出通道 3: UDP 端口 8001 → 命令解析器 / 控制面 (新增)
    output reg  [511:0] m3_axis_tdata,
    output reg  [63:0]  m3_axis_tkeep,
    output reg          m3_axis_tvalid,
    output reg          m3_axis_tlast,

    // 统计脉冲输出
    output reg          o_stat_rx_arp,
    output reg          o_stat_rx_icmp,
    output reg          o_stat_rx_udp,
    output reg          o_stat_rx_cmd,    // UDP 命令通道统计 (新增)
    output reg          o_stat_rx_drop,
    output reg          o_stat_rx_err
);

    // =========================================================================
    // 以太网帧头及 IP 协议解析 (保持组合逻辑，因为后续会被寄存)
    // =========================================================================
    wire [15:0] eth_outer = {s_axis_tdata[103:96], s_axis_tdata[111:104]};
    wire [15:0] eth_inner = {s_axis_tdata[135:128], s_axis_tdata[143:136]};
    wire        has_vlan  = cfg_vlan_enable && (eth_outer == 16'h8100);

    wire [7:0]  ip_proto  = has_vlan ? s_axis_tdata[223:216] : s_axis_tdata[191:184];
    wire [15:0] eth_type_class = has_vlan ? eth_inner : eth_outer;
    wire [47:0] dst_mac = {
        s_axis_tdata[7:0],
        s_axis_tdata[15:8],
        s_axis_tdata[23:16],
        s_axis_tdata[31:24],
        s_axis_tdata[39:32],
        s_axis_tdata[47:40]
    };
    wire [31:0] dst_ip = has_vlan ? {
        s_axis_tdata[279:272],
        s_axis_tdata[287:280],
        s_axis_tdata[295:288],
        s_axis_tdata[303:296]
    } : {
        s_axis_tdata[247:240],
        s_axis_tdata[255:248],
        s_axis_tdata[263:256],
        s_axis_tdata[271:264]
    };
    wire        ipv4_to_local = (dst_mac == cfg_local_mac) && (dst_ip == cfg_local_ip);

    // UDP 目的端口提取 (端口 8000=数据面, 8001=控制面)
    // 网络大端序: byte[N]=MSB, byte[N+1]=LSB
    wire [15:0] udp_dst_port = has_vlan
        ? {s_axis_tdata[327:320], s_axis_tdata[335:328]}   // byte40=MSB, byte41=LSB
        : {s_axis_tdata[295:288], s_axis_tdata[303:296]};  // byte36=MSB, byte37=LSB
    wire        is_udp_cmd = (udp_dst_port == 16'h1F41); // 8001 = 0x1F41

    // =========================================================================
    // 状态机与错误处理定义
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        PASS_M0 = 3'd1,   // ARP
        PASS_M1 = 3'd2,   // ICMP
        PASS_M2 = 3'd3,   // UDP 数据 (port 8000)
        PASS_M3 = 3'd5,   // UDP 命令 (port 8001), 新增
        DRAIN   = 3'd4    // 错误或不支持的包
    } state_t;
    
    state_t state, route_target;

    reg rx_err_hold;
    always_ff @(posedge clk) begin
        if (!rst_n)
            rx_err_hold <= 1'b0;
        else if (s_axis_tvalid && s_axis_tlast)
            rx_err_hold <= 1'b0;
        else if (s_axis_tvalid && s_axis_rx_err)
            rx_err_hold <= 1'b1;
    end

    wire err_in_frame = rx_err_hold || (s_axis_tvalid && s_axis_rx_err);
    wire block_out    = err_in_frame || (state == DRAIN);

    // =========================================================================
    // 路由目标判定逻辑 (纯组合逻辑)
    // =========================================================================
    always_comb begin
        if (state == IDLE) begin
            if (s_axis_tvalid) begin
                if (err_in_frame)
                    route_target = IDLE;
                else if (eth_type_class == 16'h0806)
                    route_target = PASS_M0;
                else if (eth_type_class == 16'h0800 && ip_proto == 8'h01 && ipv4_to_local)
                    route_target = PASS_M1;
                else if (eth_type_class == 16'h0800 && ip_proto == 8'h11 && ipv4_to_local) begin
                    if (is_udp_cmd)       route_target = PASS_M3;
                    else                  route_target = PASS_M2;
                end
                else
                    route_target = IDLE;
            end else begin
                route_target = IDLE;
            end
        end else if (state == DRAIN) begin
            route_target = IDLE;
        end else begin
            route_target = state;
        end
    end

    // =========================================================================
    // 状态更新逻辑
    // =========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            if (s_axis_tvalid && s_axis_tlast) begin
                state <= IDLE;
            end else if (s_axis_tvalid && state == IDLE) begin
                if (err_in_frame)
                    state <= DRAIN;
                else if (eth_type_class == 16'h0806)
                    state <= PASS_M0;
                else if (eth_type_class == 16'h0800 && ip_proto == 8'h01 && ipv4_to_local)
                    state <= PASS_M1;
                else if (eth_type_class == 16'h0800 && ip_proto == 8'h11 && ipv4_to_local) begin
                    if (is_udp_cmd)       state <= PASS_M3;
                    else                  state <= PASS_M2;
                end
                else
                    state <= DRAIN;
            end
        end
    end

    // =========================================================================
    // 【核心时序优化】：流水线化输出多路选择器 (Output Pipeline)
    // 将原本的 always_comb 改为 always_ff，利用 1 拍延迟换取极致的时序裕量
    // =========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m0_axis_tvalid <= 1'b0;
            m1_axis_tvalid <= 1'b0;
            m2_axis_tvalid <= 1'b0;
            m3_axis_tvalid <= 1'b0;
        end else begin
            m0_axis_tvalid <= 1'b0;
            m1_axis_tvalid <= 1'b0;
            m2_axis_tvalid <= 1'b0;
            m3_axis_tvalid <= 1'b0;

            m0_axis_tdata  <= s_axis_tdata;
            m0_axis_tlast  <= s_axis_tlast;

            m1_axis_tdata  <= s_axis_tdata;
            m1_axis_tkeep  <= s_axis_tkeep;
            m1_axis_tlast  <= s_axis_tlast;

            m2_axis_tdata  <= s_axis_tdata;
            m2_axis_tkeep  <= s_axis_tkeep;
            m2_axis_tlast  <= s_axis_tlast;

            m3_axis_tdata  <= s_axis_tdata;
            m3_axis_tkeep  <= s_axis_tkeep;
            m3_axis_tlast  <= s_axis_tlast;

            if (s_axis_tvalid && !block_out) begin
                case (route_target)
                    PASS_M0: m0_axis_tvalid <= 1'b1;
                    PASS_M1: m1_axis_tvalid <= 1'b1;
                    PASS_M2: m2_axis_tvalid <= 1'b1;
                    PASS_M3: m3_axis_tvalid <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 统计脉冲生成逻辑 (保持不变，已与数据输出完美对齐)
    // =========================================================================
    wire [3:0] c_idle_class =
        err_in_frame ? 4'd0 :
        (eth_type_class == 16'h0806) ? 4'd1 :
        (eth_type_class == 16'h0800 && ip_proto == 8'h01 && ipv4_to_local) ? 4'd2 :
        (eth_type_class == 16'h0800 && ip_proto == 8'h11 && ipv4_to_local) ?
            (is_udp_cmd ? 4'd5 : 4'd3) : 4'd4;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            o_stat_rx_arp   <= 1'b0;
            o_stat_rx_icmp  <= 1'b0;
            o_stat_rx_udp   <= 1'b0;
            o_stat_rx_cmd   <= 1'b0;
            o_stat_rx_drop  <= 1'b0;
            o_stat_rx_err   <= 1'b0;
        end else begin
            o_stat_rx_arp   <= 1'b0;
            o_stat_rx_icmp  <= 1'b0;
            o_stat_rx_udp   <= 1'b0;
            o_stat_rx_cmd   <= 1'b0;
            o_stat_rx_drop  <= 1'b0;
            o_stat_rx_err   <= 1'b0;

            if (s_axis_tvalid && s_axis_tlast) begin
                if (err_in_frame)
                    o_stat_rx_err <= 1'b1;
                else if (state == IDLE) begin
                    case (c_idle_class)
                        4'd1: o_stat_rx_arp   <= 1'b1;
                        4'd2: o_stat_rx_icmp  <= 1'b1;
                        4'd3: o_stat_rx_udp   <= 1'b1;
                        4'd5: o_stat_rx_cmd   <= 1'b1;
                        4'd4: o_stat_rx_drop  <= 1'b1;
                        default: ;
                    endcase
                end else begin
                    case (state)
                        PASS_M0: o_stat_rx_arp   <= 1'b1;
                        PASS_M1: o_stat_rx_icmp  <= 1'b1;
                        PASS_M2: o_stat_rx_udp   <= 1'b1;
                        PASS_M3: o_stat_rx_cmd   <= 1'b1;
                        DRAIN:   o_stat_rx_drop  <= 1'b1;
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule