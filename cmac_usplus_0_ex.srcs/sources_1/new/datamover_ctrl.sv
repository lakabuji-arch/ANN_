`timescale 1ns / 1ps

module datamover_ctrl (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          rx_fifo_empty,
    input  wire [15:0]   rx_fifo_len,
    output reg           rx_fifo_rd_en,

    output reg  [71:0]   s2mm_cmd_tdata,
    output reg           s2mm_cmd_tvalid,
    input  wire          s2mm_cmd_tready,
    input  wire          s2mm_sts_tvalid,
    input  wire          s2mm_err,

    input  wire          tx_trigger_pulse,
    input  wire [15:0]   tx_request_bytes,
    output wire [15:0]   o_framer_tx_bytes, // 必须是 wire 透传

    output reg  [71:0]   mm2s_cmd_tdata,
    output reg           mm2s_cmd_tvalid,
    input  wire          mm2s_cmd_tready,

    input  wire [31:0]   cfg_rx_base_addr,
    input  wire [31:0]   cfg_tx_base_addr,

    // 外部控制接口 (电平信号, 已 CDC 同步到本时钟域)
    input  wire          ext_rec_active,     // 1=录流使能
    input  wire          ext_play_active,    // 1=回放使能

    output wire [15:0]   o_diag_s2mm_cmd_cnt,
    output wire [15:0]   o_diag_mm2s_cmd_cnt,
    output wire          o_diag_lb_fifo_empty,
    output wire          o_diag_rx_meta_waiting,
    output wire          o_diag_rec_active,
    output wire          o_diag_play_active
);

    reg [31:0] rx_addr_ptr;
    wire        pending_fifo_empty;
    wire [47:0] pending_fifo_dout;
    wire        pending_fifo_rd_en;
    wire        lb_fifo_empty;
    wire [47:0] lb_fifo_dout;
    reg         lb_fifo_rd_en;
    reg [15:0] s2mm_cmd_cnt, mm2s_cmd_cnt;

    // 【新增核心防护】S2MM 带冷却期的状态机
    typedef enum logic [1:0] {S2_IDLE, S2_CMD_WAIT, S2_COOLDOWN} s2_state_t;
    s2_state_t s2_state;
    reg [3:0]  s2_cooldown_cnt;

    typedef enum logic [1:0] {TX_IDLE, TX_WAIT, TX_SEND, TX_COOLDOWN} tx_state_t;
    tx_state_t tx_state;

    assign o_diag_s2mm_cmd_cnt    = s2mm_cmd_cnt;
    assign o_diag_mm2s_cmd_cnt    = mm2s_cmd_cnt;
    assign o_diag_lb_fifo_empty   = lb_fifo_empty;
    assign o_diag_rx_meta_waiting = !rx_fifo_empty;
    assign o_diag_rec_active      = ext_rec_active;
    assign o_diag_play_active     = ext_play_active;
    assign pending_fifo_rd_en = s2mm_sts_tvalid && !pending_fifo_empty;

    xpm_fifo_sync #(.FIFO_MEMORY_TYPE("distributed"), .FIFO_READ_LATENCY(0), .FIFO_WRITE_DEPTH(64), .READ_MODE("fwft"), .WRITE_DATA_WIDTH(48), .READ_DATA_WIDTH(48)) u_pending_fifo (
        .rst(~rst_n), .wr_clk(clk), .wr_en(s2mm_cmd_tvalid && s2mm_cmd_tready), .din({s2mm_cmd_tdata[15:0], s2mm_cmd_tdata[63:32]}), .rd_en(pending_fifo_rd_en), .dout(pending_fifo_dout), .empty(pending_fifo_empty), .sleep(1'b0)
    );

    xpm_fifo_sync #(.FIFO_MEMORY_TYPE("distributed"), .FIFO_READ_LATENCY(0), .FIFO_WRITE_DEPTH(64), .READ_MODE("fwft"), .WRITE_DATA_WIDTH(48), .READ_DATA_WIDTH(48)) u_lb_fifo (
        .rst(~rst_n), .wr_clk(clk), .wr_en(s2mm_sts_tvalid && !s2mm_err && !pending_fifo_empty), .din(pending_fifo_dout), .rd_en(lb_fifo_rd_en), .dout(lb_fifo_dout), .empty(lb_fifo_empty), .sleep(1'b0)
    );

    // RX 逻辑 (S2MM)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s2mm_cmd_tvalid <= 1'b0; rx_fifo_rd_en <= 1'b0; rx_addr_ptr <= 32'd0; s2mm_cmd_cnt <= 16'd0;
            s2_state <= S2_IDLE; s2_cooldown_cnt <= 4'd0;
        end else begin
            rx_fifo_rd_en <= 1'b0;
            case (s2_state)
                S2_IDLE: begin
                    if (!rx_fifo_empty && ext_rec_active) begin
                        s2mm_cmd_tdata  <= {8'h00, rx_addr_ptr, 1'b1, 1'b1, 6'h00, 1'b1, 7'd0, rx_fifo_len};
                        s2mm_cmd_tvalid <= 1'b1; rx_addr_ptr <= rx_addr_ptr + 32'h4000;
                        s2_state <= S2_CMD_WAIT;
                    end
                end
                S2_CMD_WAIT: begin
                    if (s2mm_cmd_tvalid && s2mm_cmd_tready) begin
                        s2mm_cmd_tvalid <= 1'b0; s2mm_cmd_cnt <= s2mm_cmd_cnt + 1'b1; rx_fifo_rd_en <= 1'b1; 
                        s2_cooldown_cnt <= 4'd10; s2_state <= S2_COOLDOWN; // 强制冷却，跨时钟域防抖
                    end
                end
                S2_COOLDOWN: begin
                    if (s2_cooldown_cnt > 0) s2_cooldown_cnt <= s2_cooldown_cnt - 1'b1;
                    else s2_state <= S2_IDLE;
                end
            endcase
            if (rx_addr_ptr >= (32'h4000_0000 - 32'h10000)) rx_addr_ptr <= cfg_rx_base_addr;
        end
    end

    // TX 逻辑 (MM2S)
    assign o_framer_tx_bytes = lb_fifo_dout[47:32];
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mm2s_cmd_tvalid <= 1'b0; lb_fifo_rd_en <= 1'b0; tx_state <= TX_IDLE; mm2s_cmd_cnt <= 16'd0;
        end else begin
            lb_fifo_rd_en <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    if (!lb_fifo_empty && ext_play_active) tx_state <= TX_WAIT;
                end
                TX_WAIT: begin
                    mm2s_cmd_tdata  <= {8'h00, lb_fifo_dout[31:0], 1'b1, 1'b1, 6'h00, 1'b1, 7'd0, lb_fifo_dout[47:32]};
                    mm2s_cmd_tvalid <= 1'b1; tx_state <= TX_SEND;
                end
                TX_SEND: begin
                    if (mm2s_cmd_tvalid && mm2s_cmd_tready) begin
                        mm2s_cmd_tvalid <= 1'b0; mm2s_cmd_cnt <= mm2s_cmd_cnt + 1'b1; lb_fifo_rd_en <= 1'b1; tx_state <= TX_COOLDOWN;
                    end
                end
                TX_COOLDOWN: tx_state <= TX_IDLE;
            endcase
        end
    end
endmodule