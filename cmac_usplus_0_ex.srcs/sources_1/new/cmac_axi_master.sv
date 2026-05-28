`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: cmac_axi_master
// 功能描述: CMAC AXI 主控制器（初始化配置序列，含 RS-FEC）
// 详细说明:
//           该模块实现了一个 AXI4-Lite 主控制器，用于在系统上电时
//           按顺序配置 CMAC IP 核的关键寄存器。
//
//           初始化序列（精简防死锁版）：
//           1. 延迟等待（delay_cnt 计满 ~167ms 等待 GT 复位释放）
//           2. 使能 RS-FEC（地址 0x00D0，值 0x07）
//           3. 使能 RX 数据通路（地址 0x0014，值 0x01）
//           4. 使能 TX 数据通路（地址 0x000C，值 0x01）- 强势开启，不再死等RX对齐
//           5. 配置 TX Pause 使能（地址 0x0030，值 0x01FF）
//           6. 配置 TX Pause Quanta（地址 0x0048，值 0x0FFF）
//           7. 配置 RX Pause 使能（地址 0x0084，值 0x01）
//           8. 完成初始化，置位 axi_init_done
//
// 时钟域: init_clk（初始化时钟）
// 复位: s_axi_sreset（系统复位，高电平有效）
////////////////////////////////////////////////////////////////////////////////

module cmac_axi_master (
    // 时钟和复位
    input  wire        s_axi_aclk,        // AXI 时钟信号（init_clk）
    input  wire        s_axi_sreset,      // 系统复位，高电平有效

    // AXI4-Lite 写地址通道
    output reg  [31:0] s_axi_awaddr,      
    output reg         s_axi_awvalid,     
    input  wire        s_axi_awready,     

    // AXI4-Lite 写数据通道
    output reg  [31:0] s_axi_wdata,       
    output wire [3:0]  s_axi_wstrb,       
    output reg         s_axi_wvalid,      
    input  wire        s_axi_wready,      

    // AXI4-Lite 写响应通道
    input  wire [1:0]  s_axi_bresp,       
    input  wire        s_axi_bvalid,      
    output reg         s_axi_bready,      

    // AXI4-Lite 读地址通道 (不再使用，固定为 0)
    output wire [31:0] s_axi_araddr,
    output wire        s_axi_arvalid,
    input  wire        s_axi_arready,

    // AXI4-Lite 读数据通道 (不再使用)
    input  wire [31:0] s_axi_rdata,
    input  wire [1:0]  s_axi_rresp,
    input  wire        s_axi_rvalid,
    output wire        s_axi_rready,

    // 状态输出
    output reg         axi_init_done      // 初始化完成标志
);

    assign s_axi_wstrb   = 4'hF;
    
    // 读通道闲置绑定
    assign s_axi_araddr  = 32'd0;
    assign s_axi_arvalid = 1'b0;
    assign s_axi_rready  = 1'b0;

    // =========================================================================
    // 状态机定义
    // =========================================================================
    typedef enum logic [3:0] {
        ST_IDLE               = 4'd0,
        ST_DELAY              = 4'd1,
        // 阶段1: 使能 RS-FEC
        ST_WR_RSFEC_EN        = 4'd2,
        ST_WAIT_RSFEC_ACK     = 4'd3,
        // 阶段2: 使能 RX
        ST_WR_RX_EN           = 4'd4,
        ST_WAIT_RX_ACK        = 4'd5,
        // 阶段3: 使能 TX (直接进入)
        ST_WR_TX_EN           = 4'd6,
        ST_WAIT_TX_ACK        = 4'd7,
        // 阶段4: 配置 Pause 流控
        ST_WR_TX_PAUSE_EN     = 4'd8,
        ST_WAIT_TX_PAUSE_ACK  = 4'd9,
        ST_WR_TX_QUANTA       = 4'd10,
        ST_WAIT_TX_QUANTA_ACK = 4'd11,
        ST_WR_RX_PAUSE_EN     = 4'd12,
        ST_WAIT_RX_PAUSE_ACK  = 4'd13,
        // 完成
        ST_DONE               = 4'd14
    } state_t;

    state_t state;
    reg [23:0] delay_cnt;

    always_ff @(posedge s_axi_aclk) begin
        if (s_axi_sreset) begin
            state          <= ST_IDLE;
            s_axi_awaddr   <= 32'd0;
            s_axi_awvalid  <= 1'b0;
            s_axi_wdata    <= 32'd0;
            s_axi_wvalid   <= 1'b0;
            s_axi_bready   <= 1'b0;
            axi_init_done  <= 1'b0;
            delay_cnt      <= 24'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    axi_init_done <= 1'b0;
                    state         <= ST_DELAY;
                end

                // 延迟 ~167ms 等待 GT 复位释放
                ST_DELAY: begin
                    if (delay_cnt == 24'hFFFFFF)
                        state <= ST_WR_RSFEC_EN;
                    else
                        delay_cnt <= delay_cnt + 1'b1;
                end

                // ==============================================================
                // 阶段 1: 写 0x00D0 = 0x07 (RS-FEC 使能)
                // ==============================================================
                ST_WR_RSFEC_EN: begin
                    s_axi_awaddr  <= 32'h0000_00D0;
                    s_axi_wdata   <= 32'h0000_0007;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_RSFEC_ACK;
                end
                ST_WAIT_RSFEC_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        state        <= ST_WR_RX_EN;
                    end
                end

                // ==============================================================
                // 阶段 2: 写 0x0014 = 0x01 (ctl_rx_enable = 1)
                // ==============================================================
                ST_WR_RX_EN: begin
                    s_axi_awaddr  <= 32'h0000_0014;
                    s_axi_wdata   <= 32'h0000_0001;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_RX_ACK;
                end
                ST_WAIT_RX_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready   <= 1'b0;
                        // 强势开启 TX！
                        state          <= ST_WR_TX_EN; 
                    end
                end

                // ==============================================================
                // 阶段 3: 写 0x000C = 0x01 (ctl_tx_enable=1)
                // ==============================================================
                ST_WR_TX_EN: begin
                    s_axi_awaddr  <= 32'h0000_000C;
                    s_axi_wdata   <= 32'h0000_0001;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_TX_ACK;
                end
                ST_WAIT_TX_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        state        <= ST_WR_TX_PAUSE_EN;
                    end
                end

                // ==============================================================
                // 阶段 4: 配置 Pause 流控
                // ==============================================================
                ST_WR_TX_PAUSE_EN: begin
                    s_axi_awaddr  <= 32'h0000_0030;
                    s_axi_wdata   <= 32'h0000_01FF;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_TX_PAUSE_ACK;
                end
                ST_WAIT_TX_PAUSE_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        state        <= ST_WR_TX_QUANTA;
                    end
                end

                ST_WR_TX_QUANTA: begin
                    s_axi_awaddr  <= 32'h0000_0048;
                    s_axi_wdata   <= 32'h0000_0FFF;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_TX_QUANTA_ACK;
                end
                ST_WAIT_TX_QUANTA_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        state        <= ST_WR_RX_PAUSE_EN;
                    end
                end

                ST_WR_RX_PAUSE_EN: begin
                    s_axi_awaddr  <= 32'h0000_0084;
                    s_axi_wdata   <= 32'h0000_0000;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    s_axi_bready  <= 1'b1;
                    state         <= ST_WAIT_RX_PAUSE_ACK;
                end
                ST_WAIT_RX_PAUSE_ACK: begin
                    if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 1'b0;
                    if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 1'b0;
                    if (s_axi_bvalid  && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        state        <= ST_DONE;
                    end
                end

                // ==============================================================
                ST_DONE: begin
                    axi_init_done <= 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule