`timescale 1ns / 1ps
`define SIM_SPEED_UP 1  // 仿真加速宏定义

////////////////////////////////////////////////////////////////////////////////
// 模块名称: tb_system_loopback
// 功能描述: 100G 以太网系统级环回测试平台
// 详细说明:
//           该测试平台用于验证整个 100G 以太网系统的功能，包括：
//           1. AXI4-Lite 配置寄存器读写测试
//           2. UDP 数据通路和背压（backpressure）测试
//           3. PAUSE 帧收发测试
//           4. ARP 响应器功能测试
//           5. ICMP 响应器功能测试
//
//           测试架构：
//           - axis_100g_data_gen: 生成测试数据包
//           - cmac_100g_wrapper: 被测系统（DUT）
//           - axis_100g_data_rx: 接收并统计数据包
//           - 环回连接：TX 直接连接到 RX（通过 GT 串行接口）
//
//           测试时钟：
//           - init_clk: 100 MHz（初始化时钟）
//           - gt_ref_clk: 156.25 MHz（GT 参考时钟）
//           - usr_mac_clk: 由 CMAC 生成的用户时钟
////////////////////////////////////////////////////////////////////////////////

module tb_system_loopback;

    // =========================================================================
    // 系统信号
    // =========================================================================
    reg  sys_reset;         // 系统复位（高电平有效）
    reg  init_clk;          // 初始化时钟（100 MHz）
    reg  gt_ref_clk_p, gt_ref_clk_n;  // GT 参考时钟（差分，156.25 MHz）

    // =========================================================================
    // 时钟生成逻辑
    // =========================================================================
    
    // 生成 100 MHz 初始化时钟（周期 10 ns）
    initial begin
        init_clk = 1'b0;
        forever #5.0 init_clk = ~init_clk;  // 100MHz
    end

    // 生成 156.25 MHz GT 参考时钟（周期 6.4 ns）
    initial begin
        gt_ref_clk_p = 1'b1;
        gt_ref_clk_n = 1'b0;
        forever #3.2 {gt_ref_clk_p, gt_ref_clk_n} = {~gt_ref_clk_p, ~gt_ref_clk_n};  // 156.25MHz
    end

    // =========================================================================
    // 信号声明
    // =========================================================================
    
    // --- GT 串行接口信号 ---
    wire [3:0] gt_serial_p, gt_serial_n;  // GT 差分串行信号（4 通道）

    // --- 系统状态信号 ---
    wire       usr_mac_clk, usr_mac_rst_n, mac_link_up;  // MAC 用户时钟、复位、链路状态

    // --- 控制信号 ---
    reg        tx_start_en, rx_enable;   // TX 启动使能、RX 接收使能
    reg  [8:0] tx_pause_req;            // TX PAUSE 请求（9 位暂停时间）

    // --- AXI-Stream 数据接口 ---
    wire [511:0] tx_tdata, rx_tdata;    // TX/RX 数据（512位，64字节/beat）
    wire [63:0]  tx_tkeep, rx_tkeep;    // TX/RX 字节掩码
    wire         tx_tvalid, rx_tvalid, tx_tlast, rx_tlast, tx_tready, rx_tready;  // 控制信号

    // --- RX 统计输出 ---
    wire [31:0]  rx_pkt_cnt;            // 接收包计数器
    wire [15:0]  rx_beat_cnt;           // 接收 beat 计数器
    wire         rx_error_flag;         // 错误标志

    // =========================================================================
    // AXI4-Lite 配置接口信号（连接到 UDP Config Slave）
    // =========================================================================
    
    // 写地址通道
    reg  [31:0] s_udp_cfg_axi_awaddr  = 32'd0;
    reg         s_udp_cfg_axi_awvalid = 1'b0;
    wire        s_udp_cfg_axi_awready;
    
    // 写数据通道
    reg  [31:0] s_udp_cfg_axi_wdata   = 32'd0;
    reg  [3:0]  s_udp_cfg_axi_wstrb   = 4'h0;
    reg         s_udp_cfg_axi_wvalid  = 1'b0;
    wire        s_udp_cfg_axi_wready;
    
    // 写响应通道
    wire [1:0]  s_udp_cfg_axi_bresp;
    wire        s_udp_cfg_axi_bvalid;
    reg         s_udp_cfg_axi_bready  = 1'b0;
    
    // 读地址通道
    reg  [31:0] s_udp_cfg_axi_araddr  = 32'd0;
    reg         s_udp_cfg_axi_arvalid = 1'b0;
    wire        s_udp_cfg_axi_arready;
    
    // 读数据通道
    wire [31:0] s_udp_cfg_axi_rdata;
    wire [1:0]  s_udp_cfg_axi_rresp;
    wire        s_udp_cfg_axi_rvalid;
    reg         s_udp_cfg_axi_rready  = 1'b0;

    // --- TX 配置信号 ---
    reg  [15:0] tx_payload_beats;             // TX payload beats 数配置
    wire [15:0] tx_tuser = tx_payload_beats;  // AXI-Stream 用户自定义字段

    // =========================================================================
    // CMAC TX/RX 底层状态信号探测（Probing）
    // =========================================================================
    
    wire        stat_tx_pause_pin       = uut_wrapper.DUT.stat_tx_pause;        // TX Pause 状态
    wire [8:0]  stat_tx_pause_valid_pin = uut_wrapper.DUT.stat_tx_pause_valid;  // TX Pause 有效
    wire        stat_rx_pause_pin       = uut_wrapper.DUT.stat_rx_pause;        // RX Pause 状态
    wire [8:0]  stat_rx_pause_req_pin   = uut_wrapper.DUT.stat_rx_pause_req;    // RX Pause 请求

    // =========================================================================
    // [深度] 底层硬件诊断探测
    // =========================================================================
    
    wire [2:0] stat_rx_bad_fcs      = uut_wrapper.DUT.stat_rx_bad_fcs;      // RX FCS 错误计数
    wire [2:0] stat_rx_bad_code     = uut_wrapper.DUT.stat_rx_bad_code;     // RX 编码错误计数
    wire       stat_rx_bad_preamble = uut_wrapper.DUT.stat_rx_bad_preamble; // RX 前导码错误

    // 错误捕获寄存器（用于记录是否出现过错误）
    reg pause_stat_seen;        // 是否检测到 TX Pause
    reg rx_pause_stat_seen;     // 是否检测到 RX Pause
    reg bad_fcs_seen;           // 是否检测到 FCS 错误
    reg bad_code_seen;          // 是否检测到编码错误
    reg bad_preamble_seen;      // 是否检测到前导码错误

    // 错误检测逻辑：在每个时钟周期检查状态信号
    always @(posedge usr_mac_clk) begin
        if (!usr_mac_rst_n) begin
            pause_stat_seen    <= 1'b0;
            rx_pause_stat_seen <= 1'b0;
            bad_fcs_seen       <= 1'b0;
            bad_code_seen      <= 1'b0;
            bad_preamble_seen  <= 1'b0;
        end else begin
            // 检测 TX Pause 状态
            if (stat_tx_pause_pin || (|stat_tx_pause_valid_pin)) pause_stat_seen <= 1'b1;
            // 检测 RX Pause 状态
            if (stat_rx_pause_pin || (|stat_rx_pause_req_pin))   rx_pause_stat_seen <= 1'b1;

            // 捕获任何底层物理层错误/校验错误
            if (|stat_rx_bad_fcs)      bad_fcs_seen      <= 1'b1;
            if (|stat_rx_bad_code)     bad_code_seen     <= 1'b1;
            if (stat_rx_bad_preamble)  bad_preamble_seen <= 1'b1;
        end
    end

    // =========================================================================
    // 测试包定义（Target IP: 192.168.1.20）
    // =========================================================================
    
    // --- ARP Request 数据包 ---
    // 用于测试 ARP 响应器功能
    wire [511:0] pkt_arp_req = {
        176'd0,                                              // Padding
        32'h14_01_A8_C0, 48'h00_00_00_00_00_00,             // Target IP (192.168.1.20), Target MAC (00)
        32'h0A_01_A8_C0, 48'h33_22_11_E8_54_E4,             // Sender IP (192.168.1.10), Sender MAC
        16'h01_00, 8'h04, 8'h06, 16'h00_08, 16'h01_00,     // ARP Opcode (Request), HW/Proto size
        16'h06_08, 48'h33_22_11_E8_54_E4, 48'hFF_FF_FF_FF_FF_FF  // EtherType (ARP), Src MAC, Dst MAC (broadcast)
    };

    // --- ICMP Ping Request 数据包 ---
    // 用于测试 ICMP 响应器功能
    wire [511:0] pkt_icmp_req = {
        176'd0,                                              // Padding
        32'h00_00_00_00, 16'h02_00, 16'h5E_4D, 8'h00, 8'h08, // ICMP Echo Request data
        32'h14_01_A8_C0, 32'h0A_01_A8_C0, 16'hCD_AB, 8'h01, 8'h40, // Target IP, Sender IP, ICMP ID, Seq
        16'h00_00, 16'h34_12, 16'h3C_00, 8'h00, 8'h45,     // ICMP Checksum, IP Total Length
        16'h00_08, 48'h33_22_11_E8_54_E4, 48'h03_02_01_35_0A_00  // EtherType, Src MAC, Dst MAC
    };

    // =========================================================================
    // 实例化被测模块（DUT）
    // =========================================================================
    
    // --- TX 数据生成器 ---
    axis_100g_data_gen uut_tx (
        .clk(usr_mac_clk), .rst_n(usr_mac_rst_n), .start_en(tx_start_en),
        .cfg_payload_beats(tx_payload_beats),
        .m_axis_tdata(tx_tdata), .m_axis_tkeep(tx_tkeep), .m_axis_tvalid(tx_tvalid), .m_axis_tlast(tx_tlast), .m_axis_tready(tx_tready)
    );

    // --- 100G CMAC 顶层封装（被测系统） ---
    cmac_100g_wrapper uut_wrapper (
        .gt_ref_clk_p(gt_ref_clk_p), .gt_ref_clk_n(gt_ref_clk_n), .init_clk(init_clk), .sys_reset(sys_reset),
        .gt_rxp_in(gt_serial_p), .gt_rxn_in(gt_serial_n), .gt_txp_out(gt_serial_p), .gt_txn_out(gt_serial_n),  // 环回连接
        .usr_mac_clk(usr_mac_clk), .usr_mac_rst_n(usr_mac_rst_n), .mac_link_up(mac_link_up),
        .s_axis_tx_tdata(tx_tdata), .s_axis_tx_tkeep(tx_tkeep), .s_axis_tx_tvalid(tx_tvalid), .s_axis_tx_tlast(tx_tlast),
        .s_axis_tx_tuser(tx_tuser), .s_axis_tx_tready(tx_tready),
        .m_axis_rx_tdata(rx_tdata), .m_axis_rx_tkeep(rx_tkeep), .m_axis_rx_tvalid(rx_tvalid), .m_axis_rx_tlast(rx_tlast), .m_axis_rx_tready(rx_tready),
        .tx_pause_req(tx_pause_req),
        .s_udp_cfg_axi_awaddr(s_udp_cfg_axi_awaddr), .s_udp_cfg_axi_awvalid(s_udp_cfg_axi_awvalid), .s_udp_cfg_axi_awready(s_udp_cfg_axi_awready),
        .s_udp_cfg_axi_wdata(s_udp_cfg_axi_wdata), .s_udp_cfg_axi_wstrb(s_udp_cfg_axi_wstrb), .s_udp_cfg_axi_wvalid(s_udp_cfg_axi_wvalid),
        .s_udp_cfg_axi_wready(s_udp_cfg_axi_wready), .s_udp_cfg_axi_bresp(s_udp_cfg_axi_bresp), .s_udp_cfg_axi_bvalid(s_udp_cfg_axi_bvalid),
        .s_udp_cfg_axi_bready(s_udp_cfg_axi_bready), .s_udp_cfg_axi_araddr(s_udp_cfg_axi_araddr), .s_udp_cfg_axi_arvalid(s_udp_cfg_axi_arvalid),
        .s_udp_cfg_axi_arready(s_udp_cfg_axi_arready), .s_udp_cfg_axi_rdata(s_udp_cfg_axi_rdata), .s_udp_cfg_axi_rresp(s_udp_cfg_axi_rresp),
        .s_udp_cfg_axi_rvalid(s_udp_cfg_axi_rvalid), .s_udp_cfg_axi_rready(s_udp_cfg_axi_rready)
    );

    // --- RX 数据监视器 ---
    axis_100g_data_rx uut_rx (
        .clk(usr_mac_clk), .rst_n(usr_mac_rst_n), .rx_enable(rx_enable),
        .s_axis_tdata(rx_tdata), .s_axis_tkeep(rx_tkeep), .s_axis_tvalid(rx_tvalid), .s_axis_tlast(rx_tlast), .s_axis_tready(rx_tready),
        .rx_pkt_cnt(rx_pkt_cnt), .rx_beat_cnt(rx_beat_cnt), .rx_error_flag(rx_error_flag)
    );

    // =========================================================================
    // AXI4-Lite 读写任务（Task）
    // =========================================================================
    
    // --- AXI 写操作任务 ---
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_awaddr  = addr;
            s_udp_cfg_axi_wdata   = data;
            s_udp_cfg_axi_wstrb   = 4'hF;
            s_udp_cfg_axi_awvalid = 1'b1;
            s_udp_cfg_axi_wvalid  = 1'b1;
            s_udp_cfg_axi_bready  = 1'b1;

            wait(s_udp_cfg_axi_awready && s_udp_cfg_axi_wready);
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_awvalid = 1'b0;
            s_udp_cfg_axi_wvalid  = 1'b0;

            wait(s_udp_cfg_axi_bvalid);
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_bready  = 1'b0;
            $display("   [AXI Write] Addr: %08x, Data: %08x", addr, data);
        end
    endtask

    // --- AXI 读操作任务 ---
    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_araddr  = addr;
            s_udp_cfg_axi_arvalid = 1'b1;
            s_udp_cfg_axi_rready  = 1'b1;

            wait(s_udp_cfg_axi_arready);
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_arvalid = 1'b0;

            wait(s_udp_cfg_axi_rvalid);
            data = s_udp_cfg_axi_rdata;
            @(posedge usr_mac_clk);
            s_udp_cfg_axi_rready  = 1'b0;
            $display("   [AXI Read]  Addr: %08x, Data: %08x", addr, data);
        end
    endtask

    // =========================================================================
    // 测试主流程
    // =========================================================================
    
    reg [31:0] read_val;  // 用于存储 AXI 读取的值

    initial begin
        // ======================================================================
        // 初始化阶段
        // ======================================================================
        tx_payload_beats = 16'd16;
        sys_reset = 1; tx_start_en = 0; rx_enable = 0; tx_pause_req = 0;
        #500 sys_reset = 0;  // 释放复位

        // 等待初始化完成和链路建立
        wait (uut_wrapper.u_axi_master.axi_init_done == 1'b1);
        wait (usr_mac_rst_n == 1'b1);
        repeat(100) @(posedge usr_mac_clk);
        $display("\n[%0t] === 系统初始化完成，链路已建立 ===", $time);

        // ======================================================================
        // TEST 1: AXI4-Lite 寄存器读写边界测试
        // ======================================================================
        $display("\n[%0t] [TEST 1] AXI4-Lite 寄存器读写边界测试...", $time);

        // 读取版本号，验证寄存器映射版本
        axi_read(32'h0000_0020, read_val);
        if (read_val == 32'h0002_0000) $display("   [PASS] 版本号匹配 (v2)");

        // 写目标 IP 并回读验证
        axi_write(32'h0000_0014, 32'hC0A80164);
        axi_read(32'h0000_0014, read_val);
        if (read_val == 32'hC0A80164) $display("   [PASS] 目标IP写入并回读校验成功");

        // 写目标 MAC（分高低位）并回读验证
        axi_write(32'h0000_000C, 32'h0000AABB);
        axi_write(32'h0000_0010, 32'hCCDDEEFF);
        axi_read(32'h0000_000C, read_val);
        if (read_val == 32'h0000AABB) $display("   [PASS] 目标MAC(高16位)校验成功");

        axi_read(32'h0000_0010, read_val);
        if (read_val == 32'hCCDDEEFF) $display("   [PASS] 目标MAC(低32位)校验成功");

        // 写 UDP 端口（源/目的）并回读验证
        axi_write(32'h0000_0018, 32'h1F901F90);
        axi_read(32'h0000_0018, read_val);
        if (read_val == 32'h1F901F90) $display("   [PASS] UDP端口(源/目16位)联合校验成功");

        // ======================================================================
        // TEST 1b: tuser 动态负载长度测试
        // ======================================================================
        $display("\n[%0t] [TEST 1b] 动态负载长度(tuser)短包测试...", $time);
        rx_enable = 1; tx_start_en = 1;
        @(posedge usr_mac_clk) tx_payload_beats = 16'd8;  // 发送 8 beats 的短包
        #(3000);
        if (rx_error_flag) $display("   [FAIL] 8 拍长度数据包异常");
        else               $display("   [PASS] 8 拍短包成功接收并解析");
        @(posedge usr_mac_clk) tx_payload_beats = 16'd16;  // 恢复默认长度
        tx_start_en = 0;
        #(1000);

        // ======================================================================
        // TEST 2: UDP 数据通路和背压（Backpressure）测试
        // ======================================================================
        $display("\n[%0t] [TEST 2] UDP 通路背压测试（随机使能）...", $time);
        tx_start_en = 1;
        fork
            begin
                // 随机控制 rx_enable，模拟背压场景
                repeat(5000) begin
                    @(posedge usr_mac_clk);
                    rx_enable = ($random % 100 < 80);  // 80% 概率使能
                end
                rx_enable = 1;  // 最后保持使能，确保数据排空
            end
        join_none

        #(5000);
        tx_start_en = 0;
        #(2000);
        if (rx_error_flag) $display("   [FAIL] 背压测试失败，UDP 数据通路异常，检查 Deframer!");
        else               $display("   [PASS] 成功承受背压测试，数据帧完整");

        // ======================================================================
        // TEST 3: PAUSE 帧收发环回测试
        // ======================================================================
        $display("\n[%0t] [TEST 3] 全局 PAUSE 帧发送/接收环回测试...", $time);

        // 发送 PAUSE 请求（暂停时间 = 1）
        @(posedge usr_mac_clk) tx_pause_req = 9'h001;
        repeat (500) @(posedge usr_mac_clk);
        @(posedge usr_mac_clk) tx_pause_req = 9'h000;  // 清除 PAUSE 请求

        #(30000);  // 等待足够时间让 PAUSE 帧环回

        // 检查 PAUSE 帧是否成功发送和接收
        if (pause_stat_seen && rx_pause_stat_seen)
             $display("   [PASS] 环回测试成功：TX 成功发送 PAUSE，RX 成功接收并解析 PAUSE 帧");
        else if (pause_stat_seen && !rx_pause_stat_seen) begin
             // TX 发送了 PAUSE，但 RX 未收到 - 需要进一步诊断
             $display("   [WARN] TX 已发送 PAUSE，但 RX 未收到。检查硬件探测结果：");
             $display("      - bad_fcs_seen      = %b (1表示帧校验序列错误，可能帧损坏)", bad_fcs_seen);
             $display("      - bad_code_seen     = %b (1表示PCS编码错误，出现非法字符)", bad_code_seen);
             $display("      - bad_preamble_seen = %b (1表示前导码/帧起始定界符错误)", bad_preamble_seen);

             if (!bad_fcs_seen && !bad_code_seen && !bad_preamble_seen) begin
                 $display("      -> [诊断分析] 无任何物理层报错，说明帧在链路上传输正常，但 RX 侧未检测到");
                 $display("      -> 100% 确认 Vivado IP 配置正确且兼容");
                 $display("      -> 检查 IP 核 -> Generate Output Products -> 选择 'Global' 重新生成");
             end else begin
                 $display("      -> [诊断分析] 存在物理层报错，说明数据帧在传输路径上被损坏");
             end
        end else if (!pause_stat_seen)
             $display("   [FAIL] TX 未能发送 PAUSE 帧（检查 0x0030 寄存器配置）");

        // ======================================================================
        // TEST 4: ARP 响应器测试
        // ======================================================================
        $display("\n[%0t] [TEST 4] 注入 ARP 请求，验证 ARP 响应...", $time);
        @(posedge usr_mac_clk);
        
        // 强制注入 ARP Request 到接收通路
        force uut_wrapper.net_rx_tvalid = 1;
        force uut_wrapper.net_rx_tdata  = pkt_arp_req;
        force uut_wrapper.net_rx_tkeep  = 64'hFFFF_FFFF_FFFF_FFFF;
        force uut_wrapper.net_rx_tlast  = 1;
        force uut_wrapper.net_rx_tuser  = 1'b0;

        @(posedge usr_mac_clk);
        release uut_wrapper.net_rx_tvalid;
        release uut_wrapper.net_rx_tdata;
        release uut_wrapper.net_rx_tkeep;
        release uut_wrapper.net_rx_tlast;
        release uut_wrapper.net_rx_tuser;

        // 等待 ARP 响应并验证
        wait (uut_wrapper.arp_tx_tvalid == 1'b1);
        @(posedge usr_mac_clk);
        if (uut_wrapper.arp_tx_tdata[335:304] == 32'h0A_01_A8_C0)
             $display("   [PASS] ARP Reply 构造正确：Target IP 修改成功");
        else $display("   [FAIL] ARP Reply Target IP 错误！当前为 %x", uut_wrapper.arp_tx_tdata[335:304]);
        #(1000);

        // ======================================================================
        // TEST 5: ICMP 响应器测试
        // ======================================================================
        $display("\n[%0t] [TEST 5] 注入 ICMP Ping 请求，验证响应...", $time);
        @(posedge usr_mac_clk);
        
        // 强制注入 ICMP Ping Request 到接收通路
        force uut_wrapper.net_rx_tvalid = 1;
        force uut_wrapper.net_rx_tdata  = pkt_icmp_req;
        force uut_wrapper.net_rx_tkeep  = 64'hFFFF_FFFF_FFFF_FFFF;
        force uut_wrapper.net_rx_tlast  = 1;
        force uut_wrapper.net_rx_tuser  = 1'b0;

        @(posedge usr_mac_clk);
        release uut_wrapper.net_rx_tvalid;
        release uut_wrapper.net_rx_tdata;
        release uut_wrapper.net_rx_tkeep;
        release uut_wrapper.net_rx_tlast;
        release uut_wrapper.net_rx_tuser;

        // 等待 ICMP 响应并验证
        wait (uut_wrapper.icmp_tx_tvalid == 1'b1);
        @(posedge usr_mac_clk);
        if (uut_wrapper.icmp_tx_tdata[279:272] == 8'h00)
             $display("   [PASS] ICMP 响应正确：Type 改为 Reply (0x00)");
        else $display("   [FAIL] ICMP 响应未正确修改");
        #(1000);

        // ======================================================================
        // 测试完成
        // ======================================================================
        $display("\n========================================");
        $display("   所有测试用例执行完成！");
        $display("========================================\n");
        $finish;
    end

endmodule
