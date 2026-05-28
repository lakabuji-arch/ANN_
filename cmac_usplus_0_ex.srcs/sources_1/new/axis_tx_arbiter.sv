`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: axis_tx_arbiter
// 功能描述: AXI-Stream 发送仲裁器（带输出流水线 Register Slice 优化）
// 详细说明:
//           1. 固定优先级：P0 (ARP) > P1 (ICMP) > P2 (UDP) > P3 (CMD)
//           2. 包级仲裁：一旦开始传输某个包，会完整传完整个包
//           3. 【时序优化】：内置 0-Bubble Skid Buffer，彻底切断 512-bit
//              总线的组合逻辑长链，保证 322MHz 下的完美时序收敛。
////////////////////////////////////////////////////////////////////////////////

module axis_tx_arbiter (
    // 时钟和复位
    input  wire         clk,             
    input  wire         rst_n,           

    // =========================================================================
    // P0: ARP 通道（最高优先级）
    // =========================================================================
    input  wire [511:0] s0_axis_tdata,   
    input  wire [63:0]  s0_axis_tkeep,   
    input  wire         s0_axis_tvalid,  
    input  wire         s0_axis_tlast,   
    output wire         s0_axis_tready,  

    // =========================================================================
    // P1: ICMP 通道（中等优先级）
    // =========================================================================
    input  wire [511:0] s1_axis_tdata,   
    input  wire [63:0]  s1_axis_tkeep,   
    input  wire         s1_axis_tvalid,  
    input  wire         s1_axis_tlast,   
    output wire         s1_axis_tready,  

    // =========================================================================
    // P2: UDP 业务通道
    // =========================================================================
    input  wire [511:0] s2_axis_tdata,
    input  wire [63:0]  s2_axis_tkeep,
    input  wire         s2_axis_tvalid,
    input  wire         s2_axis_tlast,
    output wire         s2_axis_tready,

    // =========================================================================
    // P3: CMD 响应通道（最低优先级，新增）
    // =========================================================================
    input  wire [511:0] s3_axis_tdata,
    input  wire [63:0]  s3_axis_tkeep,
    input  wire         s3_axis_tvalid,
    input  wire         s3_axis_tlast,
    output wire         s3_axis_tready,

    // =========================================================================
    // 输出通道（连接到 CMAC）
    // =========================================================================
    output wire [511:0] m_axis_tdata,    
    output wire [63:0]  m_axis_tkeep,    
    output wire         m_axis_tvalid,   
    output wire         m_axis_tlast,    
    input  wire         m_axis_tready    
);

    // =========================================================================
    // 状态机定义与仲裁逻辑 (保持原有逻辑不变)
    // =========================================================================
    typedef enum logic [2:0] {IDLE=3'd0, PASS_S0=3'd1, PASS_S1=3'd2, PASS_S2=3'd3, PASS_S3=3'd4} state_t;
    state_t state, next_state;

    wire idle_gnt_s0 = (state == IDLE) && s0_axis_tvalid;
    wire idle_gnt_s1 = (state == IDLE) && !s0_axis_tvalid && s1_axis_tvalid;
    wire idle_gnt_s2 = (state == IDLE) && !s0_axis_tvalid && !s1_axis_tvalid && s2_axis_tvalid;
    wire idle_gnt_s3 = (state == IDLE) && !s0_axis_tvalid && !s1_axis_tvalid && !s2_axis_tvalid && s3_axis_tvalid;

    wire sel_s0 = (state == PASS_S0) || idle_gnt_s0;
    wire sel_s1 = (state == PASS_S1) || idle_gnt_s1;
    wire sel_s2 = (state == PASS_S2) || idle_gnt_s2;
    wire sel_s3 = (state == PASS_S3) || idle_gnt_s3;

    always_ff @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    wire mux_tready;

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if      (s0_axis_tvalid) next_state = (mux_tready && s0_axis_tlast) ? IDLE : PASS_S0;
                else if (s1_axis_tvalid) next_state = (mux_tready && s1_axis_tlast) ? IDLE : PASS_S1;
                else if (s2_axis_tvalid) next_state = (mux_tready && s2_axis_tlast) ? IDLE : PASS_S2;
                else if (s3_axis_tvalid) next_state = (mux_tready && s3_axis_tlast) ? IDLE : PASS_S3;
            end
            PASS_S0: if (s0_axis_tvalid && mux_tready && s0_axis_tlast) next_state = IDLE;
            PASS_S1: if (s1_axis_tvalid && mux_tready && s1_axis_tlast) next_state = IDLE;
            PASS_S2: if (s2_axis_tvalid && mux_tready && s2_axis_tlast) next_state = IDLE;
            PASS_S3: if (s3_axis_tvalid && mux_tready && s3_axis_tlast) next_state = IDLE;
        endcase
    end

    // =========================================================================
    // 内部组合逻辑 MUX (这部分信号不再直接输出，而是送入缓冲器)
    // =========================================================================
    wire         mux_tvalid = sel_s0 ? s0_axis_tvalid :
                              sel_s1 ? s1_axis_tvalid :
                              sel_s2 ? s2_axis_tvalid :
                              sel_s3 ? s3_axis_tvalid : 1'b0;

    wire [511:0] mux_tdata  = sel_s0 ? s0_axis_tdata  :
                              sel_s1 ? s1_axis_tdata  :
                              sel_s2 ? s2_axis_tdata  : s3_axis_tdata;

    wire [63:0]  mux_tkeep  = sel_s0 ? s0_axis_tkeep  :
                              sel_s1 ? s1_axis_tkeep  :
                              sel_s2 ? s2_axis_tkeep  : s3_axis_tkeep;

    wire         mux_tlast  = sel_s0 ? s0_axis_tlast  :
                              sel_s1 ? s1_axis_tlast  :
                              sel_s2 ? s2_axis_tlast  : s3_axis_tlast;

    assign s0_axis_tready = sel_s0 ? mux_tready : 1'b0;
    assign s1_axis_tready = sel_s1 ? mux_tready : 1'b0;
    assign s2_axis_tready = sel_s2 ? mux_tready : 1'b0;
    assign s3_axis_tready = sel_s3 ? mux_tready : 1'b0;

    // =========================================================================
    // 【核心时序优化】：0-Bubble Skid Buffer (防滑缓冲寄存器)
    // 彻底隔绝 MUX 组合逻辑与外接模块的时序耦合
    // =========================================================================
    reg [511:0] r_data, skd_data;
    reg [63:0]  r_keep, skd_keep;
    reg         r_last, skd_last;
    reg         r_valid, skd_valid;

    // 输出端直接由纯寄存器驱动（时序完美）
    assign m_axis_tdata  = r_data;
    assign m_axis_tkeep  = r_keep;
    assign m_axis_tlast  = r_last;
    assign m_axis_tvalid = r_valid;

    // 只要备用缓冲 (Skid) 是空的，MUX 就可以继续吞入数据
    assign mux_tready = !skd_valid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_valid   <= 1'b0;
            skd_valid <= 1'b0;
        end else begin
            // -----------------------------------------------------
            // 1. 主输出寄存器更新
            // -----------------------------------------------------
            if (m_axis_tready || !r_valid) begin
                if (skd_valid) begin
                    // 如果备用缓冲有数据，优先推给主输出
                    r_valid <= 1'b1;
                    r_data  <= skd_data;
                    r_keep  <= skd_keep;
                    r_last  <= skd_last;
                    skd_valid <= 1'b0; // 清空备用缓冲
                end else if (mux_tvalid && mux_tready) begin
                    // 直接从 MUX 流水线打一拍出去
                    r_valid <= 1'b1;
                    r_data  <= mux_tdata;
                    r_keep  <= mux_tkeep;
                    r_last  <= mux_tlast;
                end else begin
                    r_valid <= 1'b0;
                end
            end
            
            // -----------------------------------------------------
            // 2. 备用缓冲更新 (Skid 动作)
            // 当下游反压 (!m_axis_tready)，但当前寄存器满了且 MUX 还有新数据时，
            // 将新数据缓存到 Skid 寄存器，防止数据丢失
            // -----------------------------------------------------
            if (!m_axis_tready && r_valid && mux_tvalid && mux_tready) begin
                skd_valid <= 1'b1;
                skd_data  <= mux_tdata;
                skd_keep  <= mux_tkeep;
                skd_last  <= mux_tlast;
            end
        end
    end

endmodule
