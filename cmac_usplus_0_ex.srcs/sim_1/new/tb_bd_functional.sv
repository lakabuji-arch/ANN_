`timescale 1ps / 1ps

module tb_bd_functional();

    localparam integer UI_TIMEOUT_CYCLES  = 4000;
    localparam integer MAC_TIMEOUT_CYCLES = 4000;
    localparam [7:0]  EXPECT_S2MM_STS     = 8'h8A;
    localparam [7:0]  EXPECT_MM2S_STS     = 8'h8B;

    reg clk_50m = 1'b0;
    wire clk_100m;
    reg usr_mac_clk = 1'b0;
    reg diff_clock_rtl_0_clk_p = 1'b0;
    wire diff_clock_rtl_0_clk_n = ~diff_clock_rtl_0_clk_p;
    reg sys_rst = 1'b1;

    always #10000 clk_50m = ~clk_50m;
    always #1553  usr_mac_clk = ~usr_mac_clk;
    always #5000  diff_clock_rtl_0_clk_p = ~diff_clock_rtl_0_clk_p;

    wire c0_ddr4_ui_clk;

    reg  [71:0]  s2mm_cmd_tdata = 72'd0;
    reg          s2mm_cmd_tvalid = 1'b0;
    wire         s2mm_cmd_tready;

    reg  [511:0] axis_rx_tdata = 512'd0;
    reg  [63:0]  axis_rx_tkeep = 64'd0;
    reg          axis_rx_tvalid = 1'b0;
    reg          axis_rx_tlast = 1'b0;
    wire         axis_rx_tready;

    wire [7:0]   s2mm_sts_tdata;
    wire [0:0]   s2mm_sts_tkeep;
    wire         s2mm_sts_tlast;
    wire         s2mm_sts_tvalid;

    reg  [71:0]  mm2s_cmd_tdata = 72'd0;
    reg          mm2s_cmd_tvalid = 1'b0;
    wire         mm2s_cmd_tready;

    wire [511:0] axis_tx_tdata;
    wire [63:0]  axis_tx_tkeep;
    wire         axis_tx_tvalid;
    wire         axis_tx_tlast;
    reg          axis_tx_tready = 1'b0;

    wire [7:0]   mm2s_sts_tdata;
    wire [0:0]   mm2s_sts_tkeep;
    wire         mm2s_sts_tlast;
    wire         mm2s_sts_tvalid;

    wire s2mm_err;
    wire mm2s_err;
    wire [31:0] axis_wr_data_count_0;
    wire [31:0] axis_wr_data_count_1;

    wire        ddr4_act_n;
    wire [16:0] ddr4_adr;
    wire [1:0]  ddr4_ba;
    wire [0:0]  ddr4_bg;
    wire [0:0]  ddr4_ck_c, ddr4_ck_t, ddr4_cke, ddr4_cs_n, ddr4_odt;
    wire        ddr4_reset_n;
    wire [3:0]  ddr4_dm_n;
    wire [31:0] ddr4_dq;
    wire [3:0]  ddr4_dqs_c, ddr4_dqs_t;

    wire calib_complete = uut.dma_ddr4_sys_i.c0_init_calib_complete;
    wire ddr4_aresetn   = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.ddr4_0.inst.c0_ddr4_aresetn;
    wire ddr4_ui_clk    = uut.dma_ddr4_sys_i.c0_ddr4_ui_clk;

    wire [31:0]  m00_axi_araddr  = {1'b0, uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARADDR};
    wire [7:0]   m00_axi_arlen   = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARLEN;
    wire [2:0]   m00_axi_arsize  = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARSIZE;
    wire [1:0]   m00_axi_arburst = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARBURST;
    wire         m00_axi_arvalid = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARVALID;
    wire         m00_axi_rready  = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RREADY;

    wire         sc_awready, sc_wready, sc_bvalid, sc_arready, sc_rvalid, sc_rlast;
    wire [1:0]   sc_bresp, sc_rresp;
    wire [255:0] sc_rdata;

    reg          s2mm_status_seen = 1'b0;
    reg [7:0]    s2mm_status_data = 8'd0;
    integer      s2mm_status_count = 0;
    reg          mm2s_status_seen = 1'b0;
    reg [7:0]    mm2s_status_data = 8'd0;
    integer      mm2s_status_count = 0;

    reg [511:0] tx_data_queue[$];
    reg [63:0]  tx_keep_queue[$];
    reg         tx_last_queue[$];
    integer     tx_handshake_count = 0;

    integer     m_axi_read_cmd_count = 0;
    integer     m_axi_read_beats_expected = 0;
    integer     m_axi_read_beats_seen = 0;

    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer fail_snapshot;
    integer byte_idx;

    reg [511:0] beat_got_data;
    reg [63:0]  beat_got_keep;
    reg         beat_got_last;
    reg [7:0]   got_byte;
    reg [7:0]   exp_byte;

    function automatic [71:0] build_cmd(input [3:0] tag, input [31:0] addr, input [22:0] bytes);
        begin
            build_cmd = 72'd0;
            build_cmd[67:64] = tag;
            build_cmd[63:32] = addr;
            build_cmd[31]    = 1'b0;
            build_cmd[30]    = 1'b1;
            build_cmd[29:24] = 6'd0;
            build_cmd[23]    = 1'b1;
            build_cmd[22:0]  = bytes;
        end
    endfunction

    task automatic clear_write_obs;
        begin
            s2mm_status_seen  = 1'b0;
            s2mm_status_data  = 8'd0;
            s2mm_status_count = 0;
        end
    endtask

    task automatic clear_read_obs;
        begin
            mm2s_status_seen      = 1'b0;
            mm2s_status_data      = 8'd0;
            mm2s_status_count     = 0;
            tx_data_queue.delete();
            tx_keep_queue.delete();
            tx_last_queue.delete();
            tx_handshake_count     = 0;
            m_axi_read_cmd_count   = 0;
            m_axi_read_beats_expected = 0;
            m_axi_read_beats_seen  = 0;
        end
    endtask

    task automatic send_s2mm_cmd(input [31:0] addr, input [22:0] bytes);
        begin
            clear_write_obs;
            @(posedge c0_ddr4_ui_clk);
            s2mm_cmd_tdata  = build_cmd(4'hA, addr, bytes);
            s2mm_cmd_tvalid = 1'b1;
            while (!s2mm_cmd_tready) begin
                @(posedge c0_ddr4_ui_clk);
            end
            @(posedge c0_ddr4_ui_clk);
            s2mm_cmd_tvalid = 1'b0;
            s2mm_cmd_tdata  = 72'd0;
            $display("  [%0t ns] S2MM CMD -> ADDR=0x%h BTT=%0d", $time/1000, addr, bytes);
        end
    endtask

    task automatic send_mm2s_cmd(input [31:0] addr, input [22:0] bytes);
        begin
            clear_read_obs;
            @(posedge c0_ddr4_ui_clk);
            mm2s_cmd_tdata  = build_cmd(4'hB, addr, bytes);
            mm2s_cmd_tvalid = 1'b1;
            while (!mm2s_cmd_tready) begin
                @(posedge c0_ddr4_ui_clk);
            end
            @(posedge c0_ddr4_ui_clk);
            mm2s_cmd_tvalid = 1'b0;
            mm2s_cmd_tdata  = 72'd0;
            $display("  [%0t ns] MM2S CMD -> ADDR=0x%h BTT=%0d", $time/1000, addr, bytes);
        end
    endtask

    task automatic inject_rx_beat(input [511:0] data, input [63:0] keep, input last);
        begin
            @(posedge usr_mac_clk);
            axis_rx_tdata  = data;
            axis_rx_tkeep  = keep;
            axis_rx_tlast  = last;
            axis_rx_tvalid = 1'b1;
            while (!axis_rx_tready) begin
                @(posedge usr_mac_clk);
            end
            @(posedge usr_mac_clk);
            axis_rx_tdata  = 512'd0;
            axis_rx_tkeep  = 64'd0;
            axis_rx_tlast  = 1'b0;
            axis_rx_tvalid = 1'b0;
        end
    endtask

    task automatic wait_s2mm_status;
        integer wait_cycles;
        begin
            for (wait_cycles = 0; wait_cycles < UI_TIMEOUT_CYCLES; wait_cycles = wait_cycles + 1) begin
                if (s2mm_status_seen) begin
                    if (s2mm_status_data !== EXPECT_S2MM_STS) begin
                        $error("  [FAIL] Unexpected S2MM status: 0x%h", s2mm_status_data);
                        fail_cnt = fail_cnt + 1;
                    end else begin
                        $display("  [%0t ns] S2MM STS -> 0x%h", $time/1000, s2mm_status_data);
                    end
                    return;
                end
                @(posedge c0_ddr4_ui_clk);
            end

            $error("  [FAIL] S2MM STS timeout (%0d cycles)", UI_TIMEOUT_CYCLES);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    task automatic wait_mm2s_status;
        integer wait_cycles;
        begin
            for (wait_cycles = 0; wait_cycles < UI_TIMEOUT_CYCLES; wait_cycles = wait_cycles + 1) begin
                if (mm2s_status_seen) begin
                    if (mm2s_status_data !== EXPECT_MM2S_STS) begin
                        $error("  [FAIL] Unexpected MM2S status: 0x%h", mm2s_status_data);
                        fail_cnt = fail_cnt + 1;
                    end else begin
                        $display("  [%0t ns] MM2S STS -> 0x%h", $time/1000, mm2s_status_data);
                    end
                    return;
                end
                @(posedge c0_ddr4_ui_clk);
            end

            $error("  [FAIL] MM2S STS timeout (%0d cycles)", UI_TIMEOUT_CYCLES);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    task automatic expect_tx_beat(input [511:0] expected_data, input [63:0] expected_keep, input expected_last);
        integer wait_cycles;
        begin
            for (wait_cycles = 0; wait_cycles < MAC_TIMEOUT_CYCLES; wait_cycles = wait_cycles + 1) begin
                if (tx_data_queue.size() > 0) begin
                    beat_got_data = tx_data_queue.pop_front();
                    beat_got_keep = tx_keep_queue.pop_front();
                    beat_got_last = tx_last_queue.pop_front();

                    $display("  [%0t ns] Read Beat: DATA=0x%h TKEEP=0x%h TLAST=%b",
                             $time/1000,
                             beat_got_data,
                             beat_got_keep,
                             beat_got_last);

                    if (beat_got_keep !== expected_keep) begin
                        $error("  [FAIL] TKEEP mismatch! Expected=0x%h Got=0x%h", expected_keep, beat_got_keep);
                        fail_cnt = fail_cnt + 1;
                    end

                    if (beat_got_last !== expected_last) begin
                        $error("  [FAIL] TLAST mismatch! Expected=%b Got=%b", expected_last, beat_got_last);
                        fail_cnt = fail_cnt + 1;
                    end

                    for (byte_idx = 0; byte_idx < 64; byte_idx = byte_idx + 1) begin
                        if (expected_keep[byte_idx]) begin
                            got_byte = beat_got_data[(byte_idx*8) +: 8];
                            exp_byte = expected_data[(byte_idx*8) +: 8];
                            if (got_byte !== exp_byte) begin
                                $error("  [FAIL] DATA byte mismatch at byte %0d! Expected=0x%02h Got=0x%02h",
                                       byte_idx,
                                       exp_byte,
                                       got_byte);
                                fail_cnt = fail_cnt + 1;
                                disable expect_tx_beat;
                            end
                        end
                    end

                    $display("  [PASS] Beat OK");
                    return;
                end
                @(posedge usr_mac_clk);
            end

            $error("  [FAIL] Read data timeout (%0d cycles)", MAC_TIMEOUT_CYCLES);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    task automatic expect_no_extra_tx_beats;
        integer wait_cycles;
        begin
            for (wait_cycles = 0; wait_cycles < 32; wait_cycles = wait_cycles + 1) begin
                @(posedge usr_mac_clk);
            end

            if (tx_data_queue.size() != 0) begin
                $error("  [FAIL] Unexpected extra TX beats remaining: %0d", tx_data_queue.size());
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task automatic log_case_obs;
        begin
            $display("  [OBS] MM2S_STS_SEEN=%0d MM2S_STS_COUNT=%0d M_AXI_AR_CMDS=%0d M_AXI_AR_BEATS=%0d M_AXI_R_BEATS=%0d TX_BEATS=%0d",
                     mm2s_status_seen,
                     mm2s_status_count,
                     m_axi_read_cmd_count,
                     m_axi_read_beats_expected,
                     m_axi_read_beats_seen,
                     tx_handshake_count);
        end
    endtask

    always @(posedge ddr4_ui_clk or negedge ddr4_aresetn) begin
        if (!ddr4_aresetn) begin
            s2mm_status_seen  <= 1'b0;
            s2mm_status_data  <= 8'd0;
            s2mm_status_count <= 0;
            mm2s_status_seen  <= 1'b0;
            mm2s_status_data  <= 8'd0;
            mm2s_status_count <= 0;
            m_axi_read_cmd_count <= 0;
            m_axi_read_beats_expected <= 0;
            m_axi_read_beats_seen <= 0;
        end else begin
            if (s2mm_sts_tvalid) begin
                s2mm_status_seen  <= 1'b1;
                s2mm_status_data  <= s2mm_sts_tdata;
                s2mm_status_count <= s2mm_status_count + 1;
            end

            if (mm2s_sts_tvalid) begin
                mm2s_status_seen  <= 1'b1;
                mm2s_status_data  <= mm2s_sts_tdata;
                mm2s_status_count <= mm2s_status_count + 1;
            end

            if (m00_axi_arvalid && sc_arready) begin
                m_axi_read_cmd_count <= m_axi_read_cmd_count + 1;
                m_axi_read_beats_expected <= m00_axi_arlen + 1;
                m_axi_read_beats_seen <= 0;
                $display("  [MEM-AR %0t ns] ADDR=0x%h ARLEN=%0d ARSIZE=%0d ARBURST=0x%0h",
                         $time/1000,
                         m00_axi_araddr,
                         m00_axi_arlen,
                         m00_axi_arsize,
                         m00_axi_arburst);
            end

            if (sc_rvalid && m00_axi_rready) begin
                m_axi_read_beats_seen <= m_axi_read_beats_seen + 1;
            end
        end
    end

    always @(posedge usr_mac_clk) begin
        if (axis_tx_tvalid && axis_tx_tready) begin
            tx_data_queue.push_back(axis_tx_tdata);
            tx_keep_queue.push_back(axis_tx_tkeep);
            tx_last_queue.push_back(axis_tx_tlast);
            tx_handshake_count <= tx_handshake_count + 1;
            $display("  [TX  %0t ns] DATA=0x%h TKEEP=0x%h TLAST=%b",
                     $time/1000,
                     axis_tx_tdata,
                     axis_tx_tkeep,
                     axis_tx_tlast);
        end
    end

    axi_ram_slave u_axi_ram (
        .aclk    (ddr4_ui_clk),
        .aresetn (ddr4_aresetn),
        .awaddr  ({1'b0, uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWADDR}),
        .awlen   (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWLEN),
        .awsize  (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWSIZE),
        .awburst (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWBURST),
        .awvalid (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWVALID),
        .awready (sc_awready),
        .wdata   (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_WDATA),
        .wstrb   (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_WSTRB),
        .wlast   (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_WLAST),
        .wvalid  (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_WVALID),
        .wready  (sc_wready),
        .bresp   (sc_bresp),
        .bvalid  (sc_bvalid),
        .bready  (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_BREADY),
        .araddr  ({1'b0, uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARADDR}),
        .arlen   (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARLEN),
        .arsize  (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARSIZE),
        .arburst (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARBURST),
        .arvalid (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARVALID),
        .arready (sc_arready),
        .rdata   (sc_rdata),
        .rresp   (sc_rresp),
        .rlast   (sc_rlast),
        .rvalid  (sc_rvalid),
        .rready  (uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RREADY)
    );

    initial begin
        #100;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_AWREADY = sc_awready;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_WREADY  = sc_wready;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_BRESP   = sc_bresp;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_BVALID  = sc_bvalid;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARREADY = sc_arready;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RDATA   = sc_rdata;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RRESP   = sc_rresp;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RLAST   = sc_rlast;
        force uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RVALID  = sc_rvalid;
    end

    initial begin
        #2000000000;
        $error("[FATAL] Functional TB timeout after 2ms");
        $finish;
    end

    dma_ddr4_sys_wrapper uut (
        .clk_50m                 (clk_50m),
        .clk_100m                (clk_100m),
        .usr_mac_clk             (usr_mac_clk),
        .sys_rst                 (sys_rst),
        .c0_ddr4_ui_clk          (c0_ddr4_ui_clk),
        .diff_clock_rtl_0_clk_p  (diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_0_clk_n  (diff_clock_rtl_0_clk_n),
        .ddr4_rtl_0_act_n        (ddr4_act_n),
        .ddr4_rtl_0_adr          (ddr4_adr),
        .ddr4_rtl_0_ba           (ddr4_ba),
        .ddr4_rtl_0_bg           (ddr4_bg),
        .ddr4_rtl_0_ck_c         (ddr4_ck_c),
        .ddr4_rtl_0_ck_t         (ddr4_ck_t),
        .ddr4_rtl_0_cke          (ddr4_cke),
        .ddr4_rtl_0_cs_n         (ddr4_cs_n),
        .ddr4_rtl_0_dm_n         (ddr4_dm_n),
        .ddr4_rtl_0_dq           (ddr4_dq),
        .ddr4_rtl_0_dqs_c        (ddr4_dqs_c),
        .ddr4_rtl_0_dqs_t        (ddr4_dqs_t),
        .ddr4_rtl_0_odt          (ddr4_odt),
        .ddr4_rtl_0_reset_n      (ddr4_reset_n),
        .S_AXIS_RX_tdata         (axis_rx_tdata),
        .S_AXIS_RX_tkeep         (axis_rx_tkeep),
        .S_AXIS_RX_tvalid        (axis_rx_tvalid),
        .S_AXIS_RX_tlast         (axis_rx_tlast),
        .S_AXIS_RX_tready        (axis_rx_tready),
        .M_AXIS_TX_tdata         (axis_tx_tdata),
        .M_AXIS_TX_tkeep         (axis_tx_tkeep),
        .M_AXIS_TX_tvalid        (axis_tx_tvalid),
        .M_AXIS_TX_tlast         (axis_tx_tlast),
        .M_AXIS_TX_tready        (axis_tx_tready),
        .S_AXIS_S2MM_CMD_0_tdata (s2mm_cmd_tdata),
        .S_AXIS_S2MM_CMD_0_tvalid(s2mm_cmd_tvalid),
        .S_AXIS_S2MM_CMD_0_tready(s2mm_cmd_tready),
        .M_AXIS_S2MM_STS_0_tdata (s2mm_sts_tdata),
        .M_AXIS_S2MM_STS_0_tkeep (s2mm_sts_tkeep),
        .M_AXIS_S2MM_STS_0_tlast (s2mm_sts_tlast),
        .M_AXIS_S2MM_STS_0_tvalid(s2mm_sts_tvalid),
        .M_AXIS_S2MM_STS_0_tready(1'b1),
        .S_AXIS_MM2S_CMD_0_tdata (mm2s_cmd_tdata),
        .S_AXIS_MM2S_CMD_0_tvalid(mm2s_cmd_tvalid),
        .S_AXIS_MM2S_CMD_0_tready(mm2s_cmd_tready),
        .M_AXIS_MM2S_STS_0_tdata (mm2s_sts_tdata),
        .M_AXIS_MM2S_STS_0_tkeep (mm2s_sts_tkeep),
        .M_AXIS_MM2S_STS_0_tlast (mm2s_sts_tlast),
        .M_AXIS_MM2S_STS_0_tvalid(mm2s_sts_tvalid),
        .M_AXIS_MM2S_STS_0_tready(1'b1),
        .s2mm_err_0              (s2mm_err),
        .mm2s_err_0              (mm2s_err),
        .axis_wr_data_count_0    (axis_wr_data_count_0),
        .axis_wr_data_count_1    (axis_wr_data_count_1)
    );

    initial begin
        reg [511:0] pat0;
        reg [511:0] pat1;
        reg [511:0] pat2;
        reg [511:0] tail1;

        axis_tx_tready = 1'b1;

        $display("=================================================");
        $display("  Focused BD Functional Verification Testbench   ");
        $display("=================================================");

        sys_rst = 1'b1;
        #200000;
        sys_rst = 1'b0;

        $display("[%0t ns] Reset released. Waiting for DDR4 calibration...", $time/1000);
        #30000000;
        $display("[%0t ns] DDR4 calibration wait done. calib_complete=%b ddr4_aresetn=%b",
                 $time/1000,
                 calib_complete,
                 ddr4_aresetn);

        if (!calib_complete || !ddr4_aresetn) begin
            $error("[FATAL] DDR4 interface not ready for functional TB");
            $finish;
        end

        pat0 = {16{32'hDEAD_BEEF}};
        pat1 = {16{32'h0123_4567}};
        pat2 = {16{32'hA5A5_5A5A}};
        tail1 = 512'd0;
        tail1[7:0] = 8'h3C;

        $display("\n--- CASE 1: 64B single-beat write/read ---");
        fail_snapshot = fail_cnt;
        send_s2mm_cmd(32'h0000_0000, 23'd64);
        inject_rx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_status;
        send_mm2s_cmd(32'h0000_0000, 23'd64);
        expect_tx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        expect_no_extra_tx_beats;
        wait_mm2s_status;
        log_case_obs;
        if (fail_cnt == fail_snapshot) pass_cnt = pass_cnt + 1;

        $display("\n--- CASE 2: 128B two-beat readback ---");
        fail_snapshot = fail_cnt;
        send_s2mm_cmd(32'h0001_0000, 23'd128);
        inject_rx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_rx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_status;
        send_mm2s_cmd(32'h0001_0000, 23'd128);
        expect_tx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        expect_tx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        expect_no_extra_tx_beats;
        wait_mm2s_status;
        log_case_obs;
        if (fail_cnt == fail_snapshot) pass_cnt = pass_cnt + 1;

        $display("\n--- CASE 3: 127B tail keep handling ---");
        fail_snapshot = fail_cnt;
        send_s2mm_cmd(32'h0001_0080, 23'd127);
        inject_rx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_rx_beat(pat2, 64'h7FFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_status;
        send_mm2s_cmd(32'h0001_0080, 23'd127);
        expect_tx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        expect_tx_beat(pat2, 64'h7FFF_FFFF_FFFF_FFFF, 1'b1);
        expect_no_extra_tx_beats;
        wait_mm2s_status;
        log_case_obs;
        if (fail_cnt == fail_snapshot) pass_cnt = pass_cnt + 1;

        $display("\n--- CASE 4: 129B three-beat readback ---");
        fail_snapshot = fail_cnt;
        send_s2mm_cmd(32'h0001_0100, 23'd129);
        inject_rx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_rx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_rx_beat(tail1, 64'h0000_0000_0000_0001, 1'b1);
        wait_s2mm_status;
        send_mm2s_cmd(32'h0001_0100, 23'd129);
        expect_tx_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        expect_tx_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        expect_tx_beat(tail1, 64'h0000_0000_0000_0001, 1'b1);
        expect_no_extra_tx_beats;
        wait_mm2s_status;
        log_case_obs;
        if (fail_cnt == fail_snapshot) pass_cnt = pass_cnt + 1;

        $display("\n--- CASE 5: 8B partial single beat ---");
        fail_snapshot = fail_cnt;
        send_s2mm_cmd(32'h0006_0000, 23'd8);
        inject_rx_beat(512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001122334455667788,
                       64'h0000_0000_0000_00FF,
                       1'b1);
        wait_s2mm_status;
        send_mm2s_cmd(32'h0006_0000, 23'd8);
        expect_tx_beat(512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001122334455667788,
                       64'h0000_0000_0000_00FF,
                       1'b1);
        expect_no_extra_tx_beats;
        wait_mm2s_status;
        log_case_obs;
        if (fail_cnt == fail_snapshot) pass_cnt = pass_cnt + 1;

        $display("\n=================================================");
        $display("  Focused BD Functional Verification Summary      ");
        $display("=================================================");
        $display("  PASS CASES = %0d", pass_cnt);
        $display("  FAIL COUNT = %0d", fail_cnt);

        if (fail_cnt == 0) begin
            $display("  [PASS] Functional BD verification passed.");
        end else begin
            $display("  [FAIL] Functional BD verification found issues.");
        end

        $finish;
    end

endmodule