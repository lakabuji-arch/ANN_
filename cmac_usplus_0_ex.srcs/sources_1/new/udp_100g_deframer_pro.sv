`timescale 1ns / 1ps

module udp_100g_deframer_pro (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [511:0]  s_axis_tdata,
    input  wire [63:0]   s_axis_tkeep,
    input  wire          s_axis_tvalid,
    input  wire          s_axis_tlast,
    output logic         s_axis_tready,

    output reg  [511:0]  m_axis_tdata,
    output reg  [63:0]   m_axis_tkeep,
    output reg           m_axis_tvalid,
    output reg           m_axis_tlast,
    input  wire          m_axis_tready,

    output reg           o_payload_cmd_valid, 
    output reg  [15:0]   o_payload_bytes,     
    output reg           o_stat_rx_udp        
);

    enum logic [2:0] {ST_IDLE, ST_PAYLOAD, ST_FLUSH_TAIL, ST_DROP} state;
    
    reg [175:0] leftover_data; 
    reg [15:0]  remaining_bytes; 
    reg         drop_needed;     

    wire [6:0]  out_bytes = (remaining_bytes >= 16'd64) ? 7'd64 : remaining_bytes[6:0];
    wire [63:0] keep_mask = (out_bytes == 7'd64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'h1 << out_bytes) - 1'b1);

    // 根据输入 tkeep 掩码低 42 字节，防止尾拍垃圾数据污染输出
    function automatic [335:0] mask_lower_42;
        input [335:0] data_in;
        input [41:0]  keep_in;
        integer i;
        begin
            mask_lower_42 = 336'd0;
            for (i = 0; i < 42; i = i + 1)
                if (keep_in[i]) mask_lower_42[i*8 +: 8] = data_in[i*8 +: 8];
        end
    endfunction

    always_comb begin
        if (state == ST_DROP) s_axis_tready = 1'b1;
        else if (state == ST_FLUSH_TAIL) s_axis_tready = 1'b0;
        else s_axis_tready = m_axis_tready;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            m_axis_tvalid       <= 1'b0;
            m_axis_tlast        <= 1'b0;
            o_payload_cmd_valid <= 1'b0;
            o_payload_bytes     <= 16'd0;
            o_stat_rx_udp       <= 1'b0;
            drop_needed         <= 1'b0;
            remaining_bytes     <= 16'd0;
        end else begin
            // 【核心修复】：全局默认拉低脉冲信号，彻底防止 CMAC 空隙造成的"复制拍"死锁！
            o_payload_cmd_valid <= 1'b0; 
            o_stat_rx_udp       <= 1'b0;
            m_axis_tvalid       <= 1'b0; 

            case (state)
                ST_IDLE: begin
                    m_axis_tlast <= 1'b0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (s_axis_tdata[111:96] == 16'h0008) begin
                            automatic logic [15:0] udp_len_raw = {s_axis_tdata[311:304], s_axis_tdata[319:312]};
                            if (udp_len_raw > 16'd8 && udp_len_raw < 16'd9000) begin 
                                automatic logic [15:0] pay_len = udp_len_raw - 16'd8;
                                
                                o_payload_bytes     <= pay_len;
                                o_payload_cmd_valid <= 1'b1; 
                                remaining_bytes     <= pay_len; 
                                leftover_data       <= s_axis_tdata[511:336];
                                
                                if (s_axis_tlast) begin
                                    state <= ST_FLUSH_TAIL;
                                    drop_needed <= 1'b0;
                                end else begin
                                    if (pay_len <= 16'd22) begin
                                        state <= ST_FLUSH_TAIL;
                                        drop_needed <= 1'b1; 
                                    end else begin
                                        state <= ST_PAYLOAD;
                                    end
                                end
                            end else begin
                                if (!s_axis_tlast) state <= ST_DROP;
                            end
                        end else begin
                            if (!s_axis_tlast) state <= ST_DROP;
                        end
                    end
                end

                ST_PAYLOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        m_axis_tvalid <= 1'b1; // 此处覆盖默认值
                        m_axis_tdata  <= { mask_lower_42(s_axis_tdata[335:0], s_axis_tkeep[41:0]), leftover_data };
                        m_axis_tkeep  <= keep_mask; 
                        
                        leftover_data <= s_axis_tdata[511:336];

                        if (remaining_bytes <= 16'd64) begin
                            m_axis_tlast  <= 1'b1;
                            o_stat_rx_udp <= 1'b1;
                            remaining_bytes <= 16'd0;
                            
                            if (s_axis_tlast) state <= ST_IDLE;
                            else state <= ST_DROP; 
                        end else begin
                            m_axis_tlast <= 1'b0;
                            remaining_bytes <= remaining_bytes - 16'd64;
                            if (s_axis_tlast) state <= ST_FLUSH_TAIL; 
                        end
                    end
                end

                ST_FLUSH_TAIL: begin
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b1; // 此处覆盖默认值
                        m_axis_tlast  <= 1'b1;
                        m_axis_tdata  <= { 336'd0, leftover_data };

                        if (remaining_bytes <= 16'd64) begin
                            m_axis_tkeep  <= keep_mask; 
                            o_stat_rx_udp <= 1'b1;
                            remaining_bytes <= 16'd0;
                            
                            if (drop_needed) state <= ST_DROP; 
                            else state <= ST_IDLE;
                        end else begin
                            m_axis_tlast  <= 1'b0;
                            m_axis_tkeep  <= 64'hFFFF_FFFF_FFFF_FFFF;
                            remaining_bytes <= remaining_bytes - 16'd64;
                            leftover_data <= 176'd0; 
                        end
                    end
                end
                
                ST_DROP: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state <= ST_IDLE;
                    end
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule