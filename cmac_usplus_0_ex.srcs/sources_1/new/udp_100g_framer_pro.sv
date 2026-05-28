`timescale 1ns / 1ps

module udp_100g_framer_pro (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [511:0]  s_axis_tdata,
    input  wire [63:0]   s_axis_tkeep,
    input  wire          s_axis_tvalid,
    input  wire          s_axis_tlast,
    output wire          s_axis_tready,

    input  wire [15:0]   i_tx_payload_bytes,
    input  wire          tx_meta_empty,

    input  wire [47:0]   cfg_dest_mac,
    input  wire [47:0]   cfg_local_mac,
    input  wire [31:0]   cfg_local_ip,
    input  wire [31:0]   cfg_dest_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dest_port,

    output reg  [511:0]  m_axis_tdata,
    output reg  [63:0]   m_axis_tkeep,
    output reg           m_axis_tvalid,
    output reg           m_axis_tlast,
    input  wire          m_axis_tready,

    output reg           o_stat_tx_udp,
    output reg           o_meta_rd_en
);

    enum logic [1:0] {ST_IDLE, ST_HEADER, ST_PAYLOAD, ST_FLUSH_TAIL} state;

    reg [31:0] r_local_ip, r_dest_ip;
    reg [15:0] r_src_port, r_dest_port;
    reg [47:0] r_local_mac, r_dest_mac;

    // 【时序优化】：预计算基准校验和，打断 13 级组合逻辑链
    reg [31:0] cksum_base;
    always_ff @(posedge clk) begin
        if (!rst_n) cksum_base <= 32'd0;
        else cksum_base <= 32'h4500 + 32'd28 + 32'h4000 + 32'h4011 +
                           cfg_local_ip[31:16] + cfg_local_ip[15:0] +
                           cfg_dest_ip[31:16]  + cfg_dest_ip[15:0];
    end

    wire [15:0] ip_total_len  = 16'd28 + i_tx_payload_bytes;
    wire [15:0] udp_total_len = 16'd8  + i_tx_payload_bytes;
    wire [31:0] cksum_sum     = cksum_base + i_tx_payload_bytes;
    wire [19:0] cksum_fold    = cksum_sum[15:0] + cksum_sum[31:16];
    wire [15:0] ip_checksum   = ~(cksum_fold[15:0] + cksum_fold[19:16]);

    reg [15:0] reg_ip_len_be, reg_udp_len_be, reg_ip_checksum_le;
    reg [335:0] leftover_data;
    reg [41:0]  leftover_keep;

    // 单拍短包 keep 仍按最小 60B 以太网帧计算，未使用 payload byte 由 mask_payload_22 置 0。
    wire last_is_single = s_axis_tlast && (s_axis_tkeep[63:22] == 42'd0);
    wire [6:0]  single_raw_bytes = 7'd42 + i_tx_payload_bytes[6:0];
    wire [6:0]  single_frame_bytes = (single_raw_bytes < 7'd60) ? 7'd60 : single_raw_bytes;
    wire [63:0] single_keep = (single_frame_bytes == 7'd64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'd1 << single_frame_bytes) - 64'd1);

    function automatic [175:0] mask_payload_22;
        input [175:0] data_in;
        input [21:0]  keep_in;
        integer byte_idx;
        begin
            mask_payload_22 = 176'd0;
            for (byte_idx = 0; byte_idx < 22; byte_idx = byte_idx + 1) begin
                if (keep_in[byte_idx]) begin
                    mask_payload_22[byte_idx*8 +: 8] = data_in[byte_idx*8 +: 8];
                end
            end
        end
    endfunction

    // 吞首拍保护：仅在处理状态拉高 Ready
    assign s_axis_tready = ((state == ST_HEADER) || (state == ST_PAYLOAD)) && m_axis_tready;

    wire [1:0] dbg_fr_state;
    wire        dbg_fr_s_tvalid;
    wire        dbg_fr_s_tlast;
    wire        dbg_fr_m_tvalid;
    wire        dbg_fr_m_tlast;
    wire        dbg_fr_m_tready;
    wire [15:0] dbg_fr_payload_bytes;
    wire        dbg_fr_meta_empty;
    wire        dbg_fr_stat_tx_udp;

    assign dbg_fr_state         = state;
    assign dbg_fr_s_tvalid      = s_axis_tvalid;
    assign dbg_fr_s_tlast       = s_axis_tlast;
    assign dbg_fr_m_tvalid      = m_axis_tvalid;
    assign dbg_fr_m_tlast       = m_axis_tlast;
    assign dbg_fr_m_tready      = m_axis_tready;
    assign dbg_fr_payload_bytes = i_tx_payload_bytes;
    assign dbg_fr_meta_empty    = tx_meta_empty;
    assign dbg_fr_stat_tx_udp   = o_stat_tx_udp;

    // 输出在组合逻辑里保持当前 beat，反压期间时序块只负责锁存 leftover 和推进状态。
    always_comb begin
        m_axis_tdata  = 512'd0;
        m_axis_tkeep  = 64'd0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;

        case (state)
            ST_HEADER: begin
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tdata[47:0]   = {r_dest_mac[7:0], r_dest_mac[15:8], r_dest_mac[23:16], r_dest_mac[31:24], r_dest_mac[39:32], r_dest_mac[47:40]};
                m_axis_tdata[95:48]  = {r_local_mac[7:0], r_local_mac[15:8], r_local_mac[23:16], r_local_mac[31:24], r_local_mac[39:32], r_local_mac[47:40]};
                m_axis_tdata[111:96] = 16'h0008; m_axis_tdata[127:112] = 16'h0045;
                m_axis_tdata[143:128] = reg_ip_len_be; m_axis_tdata[159:144] = 16'h0000;
                m_axis_tdata[175:160] = 16'h0040; m_axis_tdata[191:176] = 16'h1140;
                m_axis_tdata[207:192] = reg_ip_checksum_le;
                m_axis_tdata[239:208] = {r_local_ip[7:0], r_local_ip[15:8], r_local_ip[23:16], r_local_ip[31:24]};
                m_axis_tdata[271:240] = {r_dest_ip[7:0], r_dest_ip[15:8], r_dest_ip[23:16], r_dest_ip[31:24]};
                m_axis_tdata[287:272] = {r_src_port[7:0], r_src_port[15:8]};
                m_axis_tdata[303:288] = {r_dest_port[7:0], r_dest_port[15:8]};
                m_axis_tdata[319:304] = reg_udp_len_be; m_axis_tdata[335:320] = 16'h0000;
                m_axis_tdata[511:336] = last_is_single ? mask_payload_22(s_axis_tdata[175:0], s_axis_tkeep[21:0]) : s_axis_tdata[175:0];
                if (last_is_single) begin
                    m_axis_tkeep = single_keep;
                    m_axis_tlast = 1'b1;
                end else begin
                    m_axis_tkeep = 64'hFFFF_FFFF_FFFF_FFFF;
                end
            end

            ST_PAYLOAD: begin
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tdata  = {s_axis_tdata[175:0], leftover_data};
                m_axis_tkeep  = {s_axis_tkeep[21:0], leftover_keep};
                m_axis_tlast  = s_axis_tlast && (s_axis_tkeep[63:22] == 42'd0);
            end

            ST_FLUSH_TAIL: begin
                m_axis_tvalid = 1'b1;
                m_axis_tlast  = 1'b1;
                m_axis_tdata  = {176'd0, leftover_data};
                m_axis_tkeep  = {22'd0, leftover_keep};
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE; o_stat_tx_udp <= 1'b0; o_meta_rd_en <= 1'b0;
        end else begin
            o_stat_tx_udp <= 1'b0; o_meta_rd_en <= 1'b0;
            case (state)
                ST_IDLE: begin
                    r_local_ip <= cfg_local_ip; r_dest_ip <= cfg_dest_ip;
                    r_src_port <= cfg_src_port; r_dest_port <= cfg_dest_port;
                    r_local_mac <= cfg_local_mac; r_dest_mac <= cfg_dest_mac;
                    reg_ip_len_be <= {ip_total_len[7:0], ip_total_len[15:8]};
                    reg_udp_len_be <= {udp_total_len[7:0], udp_total_len[15:8]};
                    reg_ip_checksum_le <= {ip_checksum[7:0], ip_checksum[15:8]};
                    if (s_axis_tvalid && !tx_meta_empty) begin
                        state <= ST_HEADER; o_meta_rd_en <= 1'b1;
                    end
                end
                ST_HEADER: begin
                    if (s_axis_tvalid && m_axis_tready) begin
                        leftover_data <= s_axis_tdata[511:176]; leftover_keep <= s_axis_tkeep[63:22];
                        if (last_is_single) begin o_stat_tx_udp <= 1'b1; state <= ST_IDLE; end
                        else state <= s_axis_tlast ? ST_FLUSH_TAIL : ST_PAYLOAD;
                    end
                end
                ST_PAYLOAD: begin
                    if (s_axis_tvalid && m_axis_tready) begin
                        leftover_data <= s_axis_tdata[511:176]; 
                        leftover_keep <= s_axis_tkeep[63:22];
                        if (s_axis_tlast) begin
                            if (s_axis_tkeep[63:22] == 42'd0) begin o_stat_tx_udp <= 1'b1; state <= ST_IDLE; end
                            else state <= ST_FLUSH_TAIL;
                        end
                    end
                end
                ST_FLUSH_TAIL: begin
                    if (m_axis_tready) begin o_stat_tx_udp <= 1'b1; state <= ST_IDLE; end
                end
            endcase
        end
    end
endmodule
