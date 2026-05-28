`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// 模块名称: udp_100g_statistics
// 功能描述: UDP 100G 统计计数器模块（带饱和保护版）
// 详细说明: 
//           针对 100G 线速优化，增加了计数器饱和逻辑。
//           在极限 148Mpps 速率下，32位计数器约 29 秒即溢出。
//           本模块在达到 32'hFFFF_FFFF 后将锁死，防止回绕导致统计错误。
////////////////////////////////////////////////////////////////////////////////

module udp_100g_statistics (
    // 时钟和复位信号
    input  wire        clk,         // 时钟信号（usr_mac_clk 域）
    input  wire        rst_n,       // 异步复位，低电平有效

    // 接收侧事件脉冲输入
    input  wire        pulse_rx_arp,         
    input  wire        pulse_rx_icmp,        
    input  wire        pulse_rx_udp,         
    input  wire        pulse_rx_drop,        
    input  wire        pulse_rx_err,         

    // 发送侧事件脉冲输入
    input  wire        pulse_tx_udp,         
    input  wire        pulse_tx_len_mismatch, 
    input  wire        pulse_tx_mac_ovf,     
    input  wire        pulse_tx_mac_unf,     

    // 清零控制
    input  wire        clear_all,            

    // 计数器输出
    output reg  [31:0] cnt_rx_arp,           
    output reg  [31:0] cnt_rx_icmp,          
    output reg  [31:0] cnt_rx_udp,           
    output reg  [31:0] cnt_rx_drop,          
    output reg  [31:0] cnt_rx_err,           
    output reg  [31:0] cnt_tx_udp,           
    output reg  [31:0] cnt_tx_len_mismatch,  
    output reg  [31:0] cnt_tx_mac_ovf,       
    output reg  [31:0] cnt_tx_mac_unf        
);

    // 定义全 F 常量以便比较
    localparam [31:0] CNT_MAX = 32'hFFFF_FFFF;

    // 计数器累加逻辑：带饱和检查
    always_ff @(posedge clk) begin
        if (!rst_n || clear_all) begin
            cnt_rx_arp           <= 32'd0;
            cnt_rx_icmp          <= 32'd0;
            cnt_rx_udp           <= 32'd0;
            cnt_rx_drop          <= 32'd0;
            cnt_rx_err           <= 32'd0;
            cnt_tx_udp           <= 32'd0;
            cnt_tx_len_mismatch  <= 32'd0;
            cnt_tx_mac_ovf       <= 32'd0;
            cnt_tx_mac_unf       <= 32'd0;
        end else begin
            // 接收侧计数 (只有在未达到最大值时才累加)
            if (pulse_rx_arp && (cnt_rx_arp != CNT_MAX)) 
                cnt_rx_arp <= cnt_rx_arp + 32'd1;
                
            if (pulse_rx_icmp && (cnt_rx_icmp != CNT_MAX)) 
                cnt_rx_icmp <= cnt_rx_icmp + 32'd1;
                
            if (pulse_rx_udp && (cnt_rx_udp != CNT_MAX)) 
                cnt_rx_udp <= cnt_rx_udp + 32'd1;
                
            if (pulse_rx_drop && (cnt_rx_drop != CNT_MAX)) 
                cnt_rx_drop <= cnt_rx_drop + 32'd1;
                
            if (pulse_rx_err && (cnt_rx_err != CNT_MAX)) 
                cnt_rx_err <= cnt_rx_err + 32'd1;

            // 发送侧计数
            if (pulse_tx_udp && (cnt_tx_udp != CNT_MAX)) 
                cnt_tx_udp <= cnt_tx_udp + 32'd1;
                
            if (pulse_tx_len_mismatch && (cnt_tx_len_mismatch != CNT_MAX)) 
                cnt_tx_len_mismatch <= cnt_tx_len_mismatch + 32'd1;
                
            if (pulse_tx_mac_ovf && (cnt_tx_mac_ovf != CNT_MAX)) 
                cnt_tx_mac_ovf <= cnt_tx_mac_ovf + 32'd1;
                
            if (pulse_tx_mac_unf && (cnt_tx_mac_unf != CNT_MAX)) 
                cnt_tx_mac_unf <= cnt_tx_mac_unf + 32'd1;
        end
    end

endmodule
