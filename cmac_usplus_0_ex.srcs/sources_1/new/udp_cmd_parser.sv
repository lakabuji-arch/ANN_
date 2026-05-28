`timescale 1ns / 1ps
//
// udp_cmd_parser — UDP 命令解析器 (端口 8001)
//   接收来自 rx_demux Ch3 的 UDP 命令包，
//   驱动 datamover_ctrl 控制 DDR4 录流/回放，
//   生成状态响应包 → arbiter S3 → CMAC TX
//

module udp_cmd_parser (
    input  wire         clk,
    input  wire         rst_n,

    // RX: 来自 rx_demux Ch3 (UDP port 8001, 完整 Ethernet frame)
    input  wire [511:0] s_axis_tdata,
    input  wire [63:0]  s_axis_tkeep,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,
    output wire         s_axis_tready,

    // TX: 响应包 → arbiter S3
    output reg  [511:0] m_axis_tdata,
    output reg  [63:0]  m_axis_tkeep,
    output reg          m_axis_tvalid,
    output reg          m_axis_tlast,
    input  wire         m_axis_tready,

    // 网络配置 (来自 udp_100g_config_slave, usr_mac_clk 域)
    input  wire [47:0]  cfg_local_mac,
    input  wire [31:0]  cfg_local_ip,
    input  wire [47:0]  cfg_dest_mac,
    input  wire [31:0]  cfg_dest_ip,
    input  wire [15:0]  cfg_src_port,
    input  wire [15:0]  cfg_dest_port,
    input  wire         cfg_vlan_enable,

    // 控制面 → datamover_ctrl (脉冲信号, 需 CDC)
    output reg          ctrl_start_rec,
    output reg          ctrl_stop_rec,
    output reg          ctrl_start_play,
    output reg          ctrl_stop_play,
    output reg  [31:0]  ctrl_base_addr,
    output reg          ctrl_soft_reset,   // 命令 0x06: 软复位 datamover 状态

    // 状态 ← datamover_ctrl (稳定信号, CDC 后)
    input  wire [15:0]  stat_s2mm_cmd_cnt,
    input  wire [15:0]  stat_mm2s_cmd_cnt,
    input  wire [11:0]  stat_rx_wr_count,
    input  wire [11:0]  stat_tx_wr_count,
    input  wire         stat_s2mm_err,
    input  wire         stat_mm2s_err
);

    // =========================================================================
    // 状态机
    // =========================================================================
    typedef enum logic [1:0] {ST_IDLE, ST_PARSE, ST_SEND_RESP} state_t;
    state_t state;

    // 命令寄存器
    reg  [7:0]  cmd_reg;
    reg  [31:0] addr_reg;

    // 响应包组装寄存器
    reg  [47:0]  r_local_mac, r_dest_mac;
    reg  [31:0]  r_local_ip, r_dest_ip;
    reg  [15:0]  r_src_port;       // 本机 UDP 命令端口 (8001)
    reg  [15:0]  r_req_src_port;   // 请求方源端口 → 响应目标端口

    // IP 校验和流水线计算: 第1级 → 寄存器 → 第2级
    // 将 9 项加法拆为两级，打断 322MHz 组合逻辑长链
    wire [31:0] csum_const = 32'h4500 + 32'h002A + 32'h0000 + 32'h4000 + 32'h4011;
    wire [31:0] csum_var   = {16'd0, r_local_ip[31:16]}
                           + {16'd0, r_local_ip[15:0]}
                           + {16'd0, r_dest_ip[31:16]}
                           + {16'd0, r_dest_ip[15:0]};
    reg  [31:0] csum_var_reg = 32'd0;
    always_ff @(posedge clk) csum_var_reg <= csum_var;

    wire [31:0] csum_acc   = csum_const + csum_var_reg;
    wire [19:0] csum_fold1 = csum_acc[15:0] + csum_acc[31:16];
    wire [15:0] csum_fold2 = csum_fold1[15:0] + csum_fold1[19:16];
    wire [15:0] ip_hdr_csum = ~csum_fold2;

    // 网络配置持续更新，不再锁死
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_local_mac <= 48'd0;
            r_dest_mac  <= 48'd0;
            r_local_ip  <= 32'd0;
            r_dest_ip   <= 32'd0;
            r_src_port  <= 16'h1F41;  // 8001 — cmd_parser 专用命令端口
        end else begin
            r_local_mac <= cfg_local_mac;
            r_dest_mac  <= cfg_dest_mac;
            r_local_ip  <= cfg_local_ip;
            r_dest_ip   <= cfg_dest_ip;
            r_src_port  <= 16'h1F41;  // 8001 — cmd_parser 专用命令端口
        end
    end

    // VLAN 偏移: 无VLAN=0, 有VLAN=4 (802.1Q tag)
    wire [5:0] vlan_off = cfg_vlan_enable ? 6'd4 : 6'd0;
    wire [5:0] cmd_off  = 6'd42 + vlan_off;   // UDP payload byte 0 = CMD
    wire [5:0] adr_off  = 6'd44 + vlan_off;   // UDP payload byte 2~5 = ADDR[31:0]
    wire [5:0] sp_off   = 6'd34 + vlan_off;   // UDP src port LSB = byte 34/38

    wire [7:0]  cmd_byte  = s_axis_tdata[{cmd_off[5:0], 3'd0} +: 8];
    wire [31:0] addr_byte = {s_axis_tdata[{adr_off[5:0], 3'd0} +: 8],
                             s_axis_tdata[{(adr_off+6'd1), 3'd0} +: 8],
                             s_axis_tdata[{(adr_off+6'd2), 3'd0} +: 8],
                             s_axis_tdata[{(adr_off+6'd3), 3'd0} +: 8]};
    // 请求源端口 (网络字节序: byte34=MSB, byte35=LSB → {MSB,LSB}=逻辑值)
    wire [15:0] req_src_port_raw = {s_axis_tdata[{sp_off[5:0], 3'd0} +: 8],
                                    s_axis_tdata[{(sp_off+6'd1), 3'd0} +: 8]};

    // rx_demux 无反压通道, cmd_parser 始终就绪
    assign s_axis_tready = 1'b1;

    // 命令仅在第一拍有效: byte[42]=CMD, byte[46:49]=ADDR
    wire cmd_valid = s_axis_tvalid && (state == ST_IDLE);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            m_axis_tvalid  <= 1'b0;
            ctrl_start_rec <= 1'b0;
            ctrl_stop_rec  <= 1'b0;
            ctrl_start_play<= 1'b0;
            ctrl_stop_play <= 1'b0;
            ctrl_base_addr <= 32'd0;
            ctrl_soft_reset <= 1'b0;
        end else begin
            ctrl_start_rec  <= 1'b0;
            ctrl_stop_rec   <= 1'b0;
            ctrl_start_play <= 1'b0;
            ctrl_stop_play  <= 1'b0;
            ctrl_soft_reset <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    if (cmd_valid) begin
                        cmd_reg         <= cmd_byte;
                        addr_reg        <= addr_byte;
                        r_req_src_port  <= req_src_port_raw;
                        state <= ST_PARSE;
                    end
                end

                ST_PARSE: begin
                    case (cmd_reg)
                        8'h01: begin ctrl_base_addr <= addr_reg; ctrl_start_rec  <= 1'b1; end
                        8'h02: ctrl_stop_rec  <= 1'b1;
                        8'h03: begin ctrl_base_addr <= addr_reg; ctrl_start_play <= 1'b1; end
                        8'h04: ctrl_stop_play <= 1'b1;
                        8'h06: ctrl_soft_reset <= 1'b1;
                        default: ;
                    endcase
                    state <= ST_SEND_RESP;
                end

                ST_SEND_RESP: begin
                    if (!m_axis_tvalid || m_axis_tready) begin
                        // Ethernet header: 大端序 = MSB 在低 byte 索引
                        m_axis_tdata[47:0]    <= {r_dest_mac[7:0], r_dest_mac[15:8], r_dest_mac[23:16], r_dest_mac[31:24], r_dest_mac[39:32], r_dest_mac[47:40]};
                        m_axis_tdata[95:48]   <= {r_local_mac[7:0], r_local_mac[15:8], r_local_mac[23:16], r_local_mac[31:24], r_local_mac[39:32], r_local_mac[47:40]};
                        m_axis_tdata[111:96]  <= 16'h0008;  // EtherType IPv4 = 0x0800 → 线上 byte12=08, byte13=00

                        // IP header (单 byte 字段无需翻转)
                        m_axis_tdata[119:112] <= 8'h45;     // ver/ihl
                        m_axis_tdata[127:120] <= 8'h00;     // dscp/ecn
                        m_axis_tdata[143:128] <= 16'h2A00;  // total_len=42 (0x002A→0x2A00)
                        m_axis_tdata[159:144] <= 16'h0000;  // identification
                        m_axis_tdata[175:160] <= 16'h0040;  // flags/frag (0x4000→0x0040)
                        m_axis_tdata[183:176] <= 8'h40;     // TTL=64
                        m_axis_tdata[191:184] <= 8'h11;     // proto=UDP
                        m_axis_tdata[207:192] <= {ip_hdr_csum[7:0], ip_hdr_csum[15:8]};
                        m_axis_tdata[239:208] <= {r_local_ip[7:0], r_local_ip[15:8], r_local_ip[23:16], r_local_ip[31:24]};
                        m_axis_tdata[271:240] <= {r_dest_ip[7:0], r_dest_ip[15:8], r_dest_ip[23:16], r_dest_ip[31:24]};

                        // UDP header (16-bit 字段全部翻转)
                        m_axis_tdata[287:272] <= {r_src_port[7:0], r_src_port[15:8]};
                        m_axis_tdata[303:288] <= {r_req_src_port[7:0], r_req_src_port[15:8]};
                        m_axis_tdata[319:304] <= 16'h1600;  // len=22 (0x0016→0x1600)
                        m_axis_tdata[335:320] <= 16'h0000;  // csum=0

                        // Status payload (16-bit 字段翻转)
                        m_axis_tdata[343:336] <= (stat_s2mm_err | stat_mm2s_err) ? 8'h02 : 8'h00;
                        m_axis_tdata[359:344] <= {stat_s2mm_cmd_cnt[7:0], stat_s2mm_cmd_cnt[15:8]};
                        m_axis_tdata[375:360] <= {stat_mm2s_cmd_cnt[7:0], stat_mm2s_cmd_cnt[15:8]};
                        m_axis_tdata[391:376] <= {stat_rx_wr_count[7:0], 4'd0, stat_rx_wr_count[11:8]};
                        m_axis_tdata[407:392] <= {stat_tx_wr_count[7:0], 4'd0, stat_tx_wr_count[11:8]};
                        m_axis_tdata[415:408] <= {7'd0, stat_s2mm_err | stat_mm2s_err};

                        m_axis_tdata[511:416] <= 96'd0;

                        m_axis_tkeep  <= 64'hFFFF_FFFF_FFFF_FFFF;
                        m_axis_tlast  <= 1'b1;
                        m_axis_tvalid <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
