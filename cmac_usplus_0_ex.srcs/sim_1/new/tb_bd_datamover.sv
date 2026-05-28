`timescale 1ps / 1ps

module tb_bd_datamover();

    localparam integer TB_TIMEOUT_CYCLES = 4000;

    // =========================================================================
    // 1. Clock & Reset
    // =========================================================================
    reg clk_50m = 0;
    wire clk_100m;
    reg usr_mac_clk = 0;
    reg diff_clock_rtl_0_clk_p = 0;
    wire diff_clock_rtl_0_clk_n = ~diff_clock_rtl_0_clk_p;
    reg sys_rst = 1;

    always #10000 clk_50m = ~clk_50m;                // 50MHz
    always #1553  usr_mac_clk = ~usr_mac_clk;        // 322MHz
    always #5000  diff_clock_rtl_0_clk_p = ~diff_clock_rtl_0_clk_p; // 100MHz DDR4 ref

    wire c0_ddr4_ui_clk;

    // =========================================================================
    // 2. AXI-Stream Interfaces
    // =========================================================================
    // S2MM command
    reg  [71:0]  s2mm_cmd_tdata = 0;
    reg          s2mm_cmd_tvalid = 0;
    wire         s2mm_cmd_tready;

    // S2MM data input (512-bit, usr_mac_clk domain)
    reg  [511:0] axis_rx_tdata = 0;
    reg  [63:0]  axis_rx_tkeep = 0;
    reg          axis_rx_tvalid = 0;
    reg          axis_rx_tlast = 0;
    wire         axis_rx_tready;

    // S2MM status output
    wire [7:0]   s2mm_sts_tdata;
    wire [0:0]   s2mm_sts_tkeep;
    wire         s2mm_sts_tlast;
    wire         s2mm_sts_tvalid;

    // MM2S command
    reg  [71:0]  mm2s_cmd_tdata = 0;
    reg          mm2s_cmd_tvalid = 0;
    wire         mm2s_cmd_tready;

    // MM2S data output (512-bit, usr_mac_clk domain)
    wire [511:0] axis_tx_tdata;
    wire [63:0]  axis_tx_tkeep;
    wire         axis_tx_tvalid;
    wire         axis_tx_tlast;
    reg          axis_tx_tready = 0;

    // MM2S status output
    wire [7:0]   mm2s_sts_tdata;
    wire [0:0]   mm2s_sts_tkeep;
    wire         mm2s_sts_tlast;
    wire         mm2s_sts_tvalid;

    // Error flags
    wire s2mm_err, mm2s_err;

    // Diagnostic FIFO occupancy
    wire [31:0]  axis_wr_data_count_0;  // RX path FIFO
    wire [31:0]  axis_wr_data_count_1;  // TX path FIFO

    // DDR4 physical interface
    wire         ddr4_act_n;
    wire [16:0]  ddr4_adr;
    wire [1:0]   ddr4_ba;
    wire [0:0]   ddr4_bg;
    wire [0:0]   ddr4_ck_c, ddr4_ck_t, ddr4_cke, ddr4_cs_n, ddr4_odt;
    wire         ddr4_reset_n;
    wire [3:0]   ddr4_dm_n;
    wire [31:0]  ddr4_dq;
    wire [3:0]   ddr4_dqs_c, ddr4_dqs_t;

    // =========================================================================
    // 3. Hierarchical probes + AXI RAM replacement for DDR4
    // =========================================================================
    wire calib_complete = uut.dma_ddr4_sys_i.c0_init_calib_complete;
    wire ddr4_aresetn   = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.ddr4_0.inst.c0_ddr4_aresetn;
    wire ddr4_ui_clk    = uut.dma_ddr4_sys_i.c0_ddr4_ui_clk;
    wire [511:0] raw_mm2s_tdata  = uut.dma_ddr4_sys_i.bd_mm2s_tdata;
    wire [63:0]  raw_mm2s_tkeep  = uut.dma_ddr4_sys_i.bd_mm2s_tkeep;
    wire         raw_mm2s_tvalid = uut.dma_ddr4_sys_i.bd_mm2s_tvalid;
    wire         raw_mm2s_tready = uut.dma_ddr4_sys_i.bd_mm2s_tready;
    wire         raw_mm2s_tlast  = uut.dma_ddr4_sys_i.bd_mm2s_tlast;
    wire [7:0]   raw_mm2s_sts_tdata  = uut.dma_ddr4_sys_i.bd_mm2s_sts_tdata;
    wire         raw_mm2s_sts_tvalid = uut.dma_ddr4_sys_i.bd_mm2s_sts_tvalid;
    wire [31:0]  m00_axi_araddr  = {1'b0, uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARADDR};
    wire [7:0]   m00_axi_arlen   = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARLEN;
    wire [2:0]   m00_axi_arsize  = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARSIZE;
    wire [1:0]   m00_axi_arburst = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARBURST;
    wire         m00_axi_arvalid = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_ARVALID;
    wire         m00_axi_rready  = uut.dma_ddr4_sys_i.u_bd.ddr4_dma_subsystem_i.smartconnect_0_M00_AXI_RREADY;
    wire         sc_awready, sc_wready, sc_bvalid, sc_arready, sc_rvalid, sc_rlast;
    wire [1:0]   sc_bresp, sc_rresp;
    wire [255:0] sc_rdata;

    integer pass_cnt, fail_cnt;
    integer expected_mm2s_beats;
    integer expected_m_axi_beats;
    integer mem_r_handshake_count;
    integer raw_mm2s_handshake_count;
    integer axis_tx_handshake_count;
    integer raw_mm2s_status_count;
    integer top_mm2s_status_count;

    reg raw_mm2s_status_seen = 0;
    reg top_mm2s_status_seen = 0;
    reg [7:0] raw_mm2s_status_last = 0;
    reg [7:0] top_mm2s_status_last = 0;

    reg calib_seen = 0;
    always @(posedge ddr4_ui_clk) begin
        if (calib_complete && !calib_seen) begin
            calib_seen <= 1;
            $display("  [DDR4] Calibration COMPLETE at %0t ns", $time/1000);
        end
    end

    always @(posedge ddr4_ui_clk) begin
        if (raw_mm2s_tvalid && raw_mm2s_tready) begin
            raw_mm2s_handshake_count = raw_mm2s_handshake_count + 1;
            $display("  [RAW %0t ns] Beat%0d DATA=0x%h TKEEP=0x%h TLAST=%b",
                     $time/1000,
                     raw_mm2s_handshake_count,
                     raw_mm2s_tdata,
                     raw_mm2s_tkeep,
                     raw_mm2s_tlast);
        end

        if (raw_mm2s_sts_tvalid) begin
            raw_mm2s_status_count = raw_mm2s_status_count + 1;
            raw_mm2s_status_seen = 1'b1;
            raw_mm2s_status_last = raw_mm2s_sts_tdata;
            $display("  [RAW-MM2S-STS %0t ns] Count=%0d DATA=0x%h",
                     $time/1000,
                     raw_mm2s_status_count,
                     raw_mm2s_sts_tdata);
        end

        if (mm2s_sts_tvalid) begin
            top_mm2s_status_count = top_mm2s_status_count + 1;
            top_mm2s_status_seen = 1'b1;
            top_mm2s_status_last = mm2s_sts_tdata;
            $display("  [TOP-MM2S-STS %0t ns] Count=%0d DATA=0x%h",
                     $time/1000,
                     top_mm2s_status_count,
                     mm2s_sts_tdata);
        end
    end

    always @(posedge usr_mac_clk) begin
        if (axis_tx_tvalid && axis_tx_tready) begin
            axis_tx_handshake_count = axis_tx_handshake_count + 1;
            $display("  [TX  %0t ns] Beat%0d DATA=0x%h TKEEP=0x%h TLAST=%b",
                     $time/1000,
                     axis_tx_handshake_count,
                     axis_tx_tdata,
                     axis_tx_tkeep,
                     axis_tx_tlast);
        end
    end

    always @(posedge ddr4_ui_clk) begin
        if (m00_axi_arvalid && sc_arready) begin
            mem_r_handshake_count = 0;
            $display("  [MEM-AR %0t ns] ADDR=0x%h ARLEN=%0d ARSIZE=%0d ARBURST=0x%0h EXPECTED_MEM_BEATS=%0d",
                     $time/1000,
                     m00_axi_araddr,
                     m00_axi_arlen,
                     m00_axi_arsize,
                     m00_axi_arburst,
                     expected_m_axi_beats);
        end

        if (sc_rvalid && m00_axi_rready) begin
            mem_r_handshake_count = mem_r_handshake_count + 1;
            if (expected_m_axi_beats <= 8) begin
                $display("  [MEM-R  %0t ns] Beat%0d DATA=0x%h RLAST=%b",
                         $time/1000,
                         mem_r_handshake_count,
                         sc_rdata,
                         sc_rlast);
            end
        end
    end

    // === AXI4 RAM slave replaces DDR4 behavioral model ===
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

    // Force smartconnect M00_AXI response wires driven by AXI RAM (replaces DDR4)
    initial begin
        #100; // let reset settle
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

    // =========================================================================
    // 4. Global simulation timeout (2ms)
    // =========================================================================
    initial begin
        #2000000000;
        $error("\n[FATAL] SIMULATION TIMEOUT: 2ms reached. Design may be deadlocked.");
        $display("  Final state:");
        $display("    calib_complete=%b  ddr4_aresetn=%b", calib_complete, ddr4_aresetn);
        $display("    s2mm_cmd_tready=%b  mm2s_cmd_tready=%b", s2mm_cmd_tready, mm2s_cmd_tready);
        $display("    axis_rx_tready=%b   axis_tx_tvalid=%b", axis_rx_tready, axis_tx_tvalid);
        $display("    s2mm_sts_tvalid=%b  mm2s_sts_tvalid=%b", s2mm_sts_tvalid, mm2s_sts_tvalid);
        $display("    s2mm_err=%b         mm2s_err=%b", s2mm_err, mm2s_err);
        $display("    fifo_rx_cnt=%0d     fifo_tx_cnt=%0d", axis_wr_data_count_0, axis_wr_data_count_1);
        $finish;
    end

    // =========================================================================
    // 4. DUT - Block Design Wrapper
    // =========================================================================
    dma_ddr4_sys_wrapper uut (
        .clk_50m                 (clk_50m),
        .clk_100m                (clk_100m),
        .usr_mac_clk             (usr_mac_clk),
        .sys_rst                 (sys_rst),
        .c0_ddr4_ui_clk          (c0_ddr4_ui_clk),
        .diff_clock_rtl_0_clk_p  (diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_0_clk_n  (diff_clock_rtl_0_clk_n),

        .ddr4_rtl_0_act_n   (ddr4_act_n),
        .ddr4_rtl_0_adr     (ddr4_adr),
        .ddr4_rtl_0_ba      (ddr4_ba),
        .ddr4_rtl_0_bg      (ddr4_bg),
        .ddr4_rtl_0_ck_c    (ddr4_ck_c),
        .ddr4_rtl_0_ck_t    (ddr4_ck_t),
        .ddr4_rtl_0_cke     (ddr4_cke),
        .ddr4_rtl_0_cs_n    (ddr4_cs_n),
        .ddr4_rtl_0_dm_n    (ddr4_dm_n),
        .ddr4_rtl_0_dq      (ddr4_dq),
        .ddr4_rtl_0_dqs_c   (ddr4_dqs_c),
        .ddr4_rtl_0_dqs_t   (ddr4_dqs_t),
        .ddr4_rtl_0_odt     (ddr4_odt),
        .ddr4_rtl_0_reset_n (ddr4_reset_n),

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

        .S_AXIS_MM2S_CMD_0_tdata (mm2s_cmd_tdata),
        .S_AXIS_MM2S_CMD_0_tvalid(mm2s_cmd_tvalid),
        .S_AXIS_MM2S_CMD_0_tready(mm2s_cmd_tready),

        .M_AXIS_S2MM_STS_0_tdata (s2mm_sts_tdata),
        .M_AXIS_S2MM_STS_0_tkeep (s2mm_sts_tkeep),
        .M_AXIS_S2MM_STS_0_tlast (s2mm_sts_tlast),
        .M_AXIS_S2MM_STS_0_tvalid(s2mm_sts_tvalid),
        .M_AXIS_S2MM_STS_0_tready(1'b1),

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

    // =========================================================================
    // 5. Helper Tasks
    // =========================================================================

    // --- Send S2MM (write) command with non-blocking handshake ---
    task send_s2mm_cmd(input [31:0] addr, input [22:0] bytes);
        begin
            @(posedge c0_ddr4_ui_clk);
            s2mm_cmd_tdata[71:68] <= 4'h0;
            s2mm_cmd_tdata[67:64] <= 4'hA;           // TAG
            s2mm_cmd_tdata[63:32] <= addr;
            s2mm_cmd_tdata[31]    <= 1'b0;           // DRR=0
            s2mm_cmd_tdata[30]    <= 1'b1;           // EOF=1
            s2mm_cmd_tdata[29:24] <= 6'h00;          // DSA
            s2mm_cmd_tdata[23]    <= 1'b1;           // INCR
            s2mm_cmd_tdata[22:0]  <= bytes;          // BTT
            s2mm_cmd_tvalid       <= 1'b1;

            forever begin
                @(posedge c0_ddr4_ui_clk);
                if (s2mm_cmd_tvalid && s2mm_cmd_tready) begin
                    s2mm_cmd_tvalid <= 1'b0;
                    break;
                end
            end
            $display("  [%0t ns] S2MM CMD -> ADDR=0x%h BTT=%0d", $time/1000, addr, bytes);
        end
    endtask

    // --- Send MM2S (read) command with non-blocking handshake ---
    task send_mm2s_cmd(input [31:0] addr, input [22:0] bytes);
        begin
            expected_mm2s_beats      = (bytes + 23'd63) >> 6;
            expected_m_axi_beats     = expected_mm2s_beats << 1;
            mem_r_handshake_count    = 0;
            raw_mm2s_handshake_count = 0;
            axis_tx_handshake_count  = 0;
            raw_mm2s_status_count    = 0;
            top_mm2s_status_count    = 0;
            raw_mm2s_status_seen     = 1'b0;
            top_mm2s_status_seen     = 1'b0;
            raw_mm2s_status_last     = 8'd0;
            top_mm2s_status_last     = 8'd0;

            @(posedge c0_ddr4_ui_clk);
            mm2s_cmd_tdata[71:68] <= 4'h0;
            mm2s_cmd_tdata[67:64] <= 4'hB;           // TAG
            mm2s_cmd_tdata[63:32] <= addr;
            mm2s_cmd_tdata[31]    <= 1'b0;           // DRR=0
            mm2s_cmd_tdata[30]    <= 1'b1;           // EOF=1
            mm2s_cmd_tdata[29:24] <= 6'h00;          // DSA
            mm2s_cmd_tdata[23]    <= 1'b1;           // INCR
            mm2s_cmd_tdata[22:0]  <= bytes;          // BTT
            mm2s_cmd_tvalid       <= 1'b1;

            forever begin
                @(posedge c0_ddr4_ui_clk);
                if (mm2s_cmd_tvalid && mm2s_cmd_tready) begin
                    mm2s_cmd_tvalid <= 1'b0;
                    break;
                end
            end
            $display("  [%0t ns] MM2S CMD -> ADDR=0x%h BTT=%0d", $time/1000, addr, bytes);
        end
    endtask

    // --- Inject one 512-bit data beat on S_AXIS_RX ---
    task inject_beat(input [511:0] data, input [63:0] keep, input last);
        begin
            @(posedge usr_mac_clk);
            axis_rx_tdata  <= data;
            axis_rx_tkeep  <= keep;
            axis_rx_tlast  <= last;
            axis_rx_tvalid <= 1'b1;

            forever begin
                @(posedge usr_mac_clk);
                if (axis_rx_tvalid && axis_rx_tready) begin
                    axis_rx_tvalid <= 1'b0;
                    axis_rx_tlast  <= 1'b0;
                    break;
                end
            end
        end
    endtask

    // --- Wait for S2MM status with timeout ---
    task wait_s2mm_sts;
        begin
            fork : wss
                begin
                    wait(s2mm_sts_tvalid);
                    $display("  [%0t ns] S2MM STS -> 0x%h", $time/1000, s2mm_sts_tdata);
                    @(posedge c0_ddr4_ui_clk);
                end
                begin
                    repeat (TB_TIMEOUT_CYCLES) @(posedge c0_ddr4_ui_clk);
                    $error("  [FAIL] S2MM STS timeout (%0d cycles)", TB_TIMEOUT_CYCLES);
                    disable wss;
                end
            join_any
            disable wss;
        end
    endtask

    // --- Wait for MM2S status with timeout ---
    task wait_mm2s_sts;
        integer wait_cycles;
        integer mm2s_status_seen;
        begin
            mm2s_status_seen = 0;
            if (top_mm2s_status_seen) begin
                mm2s_status_seen = 1;
                $display("  [%0t ns] MM2S STS -> 0x%h (latched)", $time/1000, top_mm2s_status_last);
            end else begin
                for (wait_cycles = 0; wait_cycles < TB_TIMEOUT_CYCLES; wait_cycles = wait_cycles + 1) begin
                    @(posedge c0_ddr4_ui_clk);
                    if (top_mm2s_status_seen) begin
                        mm2s_status_seen = 1;
                        $display("  [%0t ns] MM2S STS -> 0x%h", $time/1000, top_mm2s_status_last);
                        break;
                    end
                end

                if (!mm2s_status_seen) begin
                    $error("  [FAIL] MM2S STS timeout (%0d cycles)", TB_TIMEOUT_CYCLES);
                end
            end

            repeat (16) @(posedge usr_mac_clk);
            $display("  [OBS] MEM_AXI_R_BEATS=%0d RAW_MM2S_BEATS=%0d TX_AXIS_BEATS=%0d EXPECTED=%0d EXPECTED_MEM=%0d MM2S_STS_SEEN=%0d",
                     mem_r_handshake_count,
                     raw_mm2s_handshake_count,
                     axis_tx_handshake_count,
                     expected_mm2s_beats,
                     expected_m_axi_beats,
                     mm2s_status_seen);
            $display("  [OBS] RAW_MM2S_STS_SEEN=%0d RAW_MM2S_STS_COUNT=%0d RAW_MM2S_STS_LAST=0x%h TOP_MM2S_STS_SEEN=%0d TOP_MM2S_STS_COUNT=%0d TOP_MM2S_STS_LAST=0x%h",
                     raw_mm2s_status_seen,
                     raw_mm2s_status_count,
                     raw_mm2s_status_last,
                     top_mm2s_status_seen,
                     top_mm2s_status_count,
                     top_mm2s_status_last);

            if (mem_r_handshake_count != expected_m_axi_beats) begin
                $error("  [FAIL] Memory-side AXI R beat count mismatch! Expected=%0d Got=%0d",
                       expected_m_axi_beats,
                       mem_r_handshake_count);
                fail_cnt = fail_cnt + 1;
            end

            if (raw_mm2s_handshake_count != expected_mm2s_beats) begin
                $error("  [FAIL] RAW MM2S beat count mismatch! Expected=%0d Got=%0d",
                       expected_mm2s_beats,
                       raw_mm2s_handshake_count);
                fail_cnt = fail_cnt + 1;
            end

            if (axis_tx_handshake_count != raw_mm2s_handshake_count) begin
                $error("  [FAIL] TX output beat count diverges from RAW MM2S! RAW=%0d TX=%0d",
                       raw_mm2s_handshake_count,
                       axis_tx_handshake_count);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // --- Capture and verify one beat from M_AXIS_TX ---
    task verify_read_beat(input [511:0] expected_data, input [63:0] expected_keep, input expected_last);
        integer wait_cycles;
        begin
            for (wait_cycles = 0; wait_cycles < TB_TIMEOUT_CYCLES; wait_cycles = wait_cycles + 1) begin
                @(posedge usr_mac_clk);
                if (axis_tx_tvalid && axis_tx_tready) begin
                    $display("  [%0t ns] Read Beat: DATA=0x%h TKEEP=0x%h TLAST=%b",
                             $time/1000, axis_tx_tdata, axis_tx_tkeep, axis_tx_tlast);

                    if (axis_tx_tdata !== expected_data) begin
                        $error("  [FAIL] Data mismatch!");
                        fail_cnt = fail_cnt + 1;
                        $display("    Expected: 0x%h", expected_data);
                        $display("    Got:      0x%h", axis_tx_tdata);
                    end else if (axis_tx_tkeep !== expected_keep) begin
                        $error("  [FAIL] TKEEP mismatch!");
                        fail_cnt = fail_cnt + 1;
                        $display("    Expected: 0x%h", expected_keep);
                        $display("    Got:      0x%h", axis_tx_tkeep);
                    end else if (axis_tx_tlast !== expected_last) begin
                        $error("  [FAIL] TLAST mismatch! Expected=%b Got=%b", expected_last, axis_tx_tlast);
                        fail_cnt = fail_cnt + 1;
                    end else begin
                        $display("  [PASS] Beat OK");
                    end

                    return;
                end
            end

            $error("  [FAIL] Read data timeout (%0d cycles)", TB_TIMEOUT_CYCLES);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    // --- Log current diagnostics ---
    task log_diag;
        begin
            $display("  [DIAG] FIFO_RX_CNT=%0d FIFO_TX_CNT=%0d s2mm_err=%b mm2s_err=%b",
                     axis_wr_data_count_0, axis_wr_data_count_1, s2mm_err, mm2s_err);
        end
    endtask

    // =========================================================================
    // 6. Main Test Sequence
    // =========================================================================
    reg [511:0] pat;
    reg [511:0] pat0;
    reg [511:0] pat1;
    reg [511:0] pat2;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        expected_mm2s_beats = 0;
        expected_m_axi_beats = 0;
        mem_r_handshake_count = 0;
        raw_mm2s_handshake_count = 0;
        axis_tx_handshake_count = 0;

        $display("=================================================");
        $display("  DataMover + DDR4 BD Verification Testbench     ");
        $display("=================================================");

        // --- Reset Phase ---
        sys_rst = 1;
        #200000;  // 200ns
        sys_rst = 0;
        $display("\n[%0t ns] Reset released. Waiting for DDR4 calibration...", $time/1000);

        // Wait for DDR4 calibration to complete
        // With SIM_SPEED_UP, calibration takes ~15-30us at the DDR4 PHY level
        // We poll c0_ddr4_ui_clk activity as a proxy for calibration done
        #30000000;  // 30us — conservative for SIM_SPEED_UP
        $display("[%0t ns] DDR4 calibration wait done.", $time/1000);
        $display("  calib_complete=%b  ddr4_aresetn=%b", calib_complete, ddr4_aresetn);
        if (!calib_complete)
            $display("  [WARN] DDR4 calibration NOT complete! AXI writes will fail.");
        if (!ddr4_aresetn)
            $display("  [WARN] DDR4 AXI interface held in RESET!");
        log_diag;

        axis_tx_tready <= 1'b1;  // Always ready for read data

        // =====================================================================
        // TEST 1: Single 64-byte write + readback
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 1: Basic 64-byte Write + Readback");
        $display("===================================================================");

        send_s2mm_cmd(32'h0000_0000, 23'd64);

        pat = {16{32'hDEAD_BEEF}};
        inject_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        $display("  [%0t ns] Data injected (1 beat, 64 bytes)", $time/1000);

        wait_s2mm_sts;
        if (s2mm_err) begin
            $error("  [FAIL] S2MM error after write!");
            fail_cnt = fail_cnt + 1;
        end

        log_diag;

        #2000000;  // 2us settling time

        send_mm2s_cmd(32'h0000_0000, 23'd64);
        verify_read_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);

        wait_mm2s_sts;
        if (mm2s_err) begin
            $error("  [FAIL] MM2S error after read!");
            fail_cnt = fail_cnt + 1;
        end

        log_diag;

        // =====================================================================
        // TEST 2: 128-byte write + readback (spans multiple DMA beats)
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 2: 128-byte Write + Readback (multi-beat)");
        $display("===================================================================");

        pat0 = {8{64'hCAFE_F00D_DEAD_BEEF}};
        pat1 = {8{64'h0123_4567_89AB_CDEF}};

        send_s2mm_cmd(32'h0001_0000, 23'd128);

        inject_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);  // beat 0
        inject_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);  // beat 1
        $display("  [%0t ns] Data injected (2 beats, 128 bytes)", $time/1000);

        wait_s2mm_sts;
        if (s2mm_err) begin $error("  [FAIL] S2MM error!"); fail_cnt = fail_cnt + 1; end

        #2000000;

        send_mm2s_cmd(32'h0001_0000, 23'd128);

        // Expect 2 beats back
        verify_read_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        verify_read_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);

        wait_mm2s_sts;
        if (mm2s_err) begin $error("  [FAIL] MM2S error!"); fail_cnt = fail_cnt + 1; end

        log_diag;

        // =====================================================================
        // TEST 2A: 127-byte write + readback (boundary just below 128B)
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 2A: 127-byte Write + Readback (2 beats, partial tail)");
        $display("===================================================================");

        pat0 = {8{64'h0123_4567_89AB_CDEF}};
        pat1 = 512'd0;
        pat1[503:0] = {63{8'hA5}};

        send_s2mm_cmd(32'h0001_0080, 23'd127);
        inject_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_beat(pat1, 64'h7FFF_FFFF_FFFF_FFFF, 1'b1);
        $display("  [%0t ns] Data injected (2 beats, 127 bytes)", $time/1000);

        wait_s2mm_sts;
        if (s2mm_err) begin $error("  [FAIL] S2MM error in 127-byte test!"); fail_cnt = fail_cnt + 1; end

        #2000000;

        send_mm2s_cmd(32'h0001_0080, 23'd127);
        verify_read_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        verify_read_beat(pat1, 64'h7FFF_FFFF_FFFF_FFFF, 1'b1);

        wait_mm2s_sts;
        if (mm2s_err) begin $error("  [FAIL] MM2S error in 127-byte test!"); fail_cnt = fail_cnt + 1; end

        log_diag;

        // =====================================================================
        // TEST 2B: 129-byte write + readback (boundary just above 128B)
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 2B: 129-byte Write + Readback (3 beats, 1-byte tail)");
        $display("===================================================================");

        pat0 = {8{64'h89AB_CDEF_0123_4567}};
        pat1 = {8{64'h1357_9BDF_2468_ACE0}};
        pat2 = {504'd0, 8'h3C};

        send_s2mm_cmd(32'h0001_0100, 23'd129);
        inject_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        inject_beat(pat2, 64'h0000_0000_0000_0001, 1'b1);
        $display("  [%0t ns] Data injected (3 beats, 129 bytes)", $time/1000);

        wait_s2mm_sts;
        if (s2mm_err) begin $error("  [FAIL] S2MM error in 129-byte test!"); fail_cnt = fail_cnt + 1; end

        #2000000;

        send_mm2s_cmd(32'h0001_0100, 23'd129);
        verify_read_beat(pat0, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        verify_read_beat(pat1, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
        verify_read_beat(pat2, 64'h0000_0000_0000_0001, 1'b1);

        wait_mm2s_sts;
        if (mm2s_err) begin $error("  [FAIL] MM2S error in 129-byte test!"); fail_cnt = fail_cnt + 1; end

        log_diag;

        // =====================================================================
        // TEST 3: Address isolation — write different patterns to different
        //          addresses, verify no cross-contamination
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 3: Address Isolation (3 regions)");
        $display("===================================================================");

        // Write AAA... to 0x0002_0000
        send_s2mm_cmd(32'h0002_0000, 23'd64);
        inject_beat({16{32'hAAAA_AAAA}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_sts;
        #500000;

        // Write BBB... to 0x0003_0000
        send_s2mm_cmd(32'h0003_0000, 23'd64);
        inject_beat({16{32'hBBBB_BBBB}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_sts;
        #500000;

        // Write CCC... to 0x0004_0000
        send_s2mm_cmd(32'h0004_0000, 23'd64);
        inject_beat({16{32'hCCCC_CCCC}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_sts;
        #2000000;

        log_diag;

        // Read back 0x0002_0000 → expect AAA
        $display("  --- Readback 0x0002_0000 (expect AAA...) ---");
        send_mm2s_cmd(32'h0002_0000, 23'd64);
        verify_read_beat({16{32'hAAAA_AAAA}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_mm2s_sts;

        // Read back 0x0003_0000 → expect BBB
        $display("  --- Readback 0x0003_0000 (expect BBB...) ---");
        send_mm2s_cmd(32'h0003_0000, 23'd64);
        verify_read_beat({16{32'hBBBB_BBBB}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_mm2s_sts;

        // Read back 0x0004_0000 → expect CCC
        $display("  --- Readback 0x0004_0000 (expect CCC...) ---");
        send_mm2s_cmd(32'h0004_0000, 23'd64);
        verify_read_beat({16{32'hCCCC_CCCC}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_mm2s_sts;

        // Read back 0x0000_0000 again → should still be DEAD_BEEF
        $display("  --- Readback 0x0000_0000 (expect original DEAD_BEEF) ---");
        send_mm2s_cmd(32'h0000_0000, 23'd64);
        verify_read_beat({16{32'hDEAD_BEEF}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_mm2s_sts;

        if (s2mm_err || mm2s_err) begin
            $error("  [FAIL] Error flags set during TEST 3!");
            fail_cnt = fail_cnt + 1;
        end

        log_diag;

        // =====================================================================
        // TEST 4: Back-to-back writes and reads (no delay between)
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 4: Back-to-back Write + Immediate Read");
        $display("===================================================================");

        send_s2mm_cmd(32'h0005_0000, 23'd64);
        inject_beat({16{32'hB00B_B00B}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_s2mm_sts;

        // Read back immediately, no extra settling time
        send_mm2s_cmd(32'h0005_0000, 23'd64);
        verify_read_beat({16{32'hB00B_B00B}}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        wait_mm2s_sts;

        if (s2mm_err || mm2s_err) begin
            $error("  [FAIL] Error flags during back-to-back test!");
            fail_cnt = fail_cnt + 1;
        end

        log_diag;

        // =====================================================================
        // TEST 5: Small payload (8 bytes) — tests tkeep edge cases
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 5: Small payload (8 bytes, partial beat)");
        $display("===================================================================");

        send_s2mm_cmd(32'h0006_0000, 23'd8);

        pat = {448'd0, 64'h1122_3344_5566_7788};
        inject_beat(pat, 64'h0000_0000_0000_00FF, 1'b1);  // only lower 8 bytes valid
        $display("  [%0t ns] Data injected (1 beat, 8 bytes valid)", $time/1000);

        wait_s2mm_sts;
        #2000000;

        send_mm2s_cmd(32'h0006_0000, 23'd8);
        verify_read_beat(pat, 64'h0000_0000_0000_00FF, 1'b1);
        wait_mm2s_sts;

        log_diag;

        // =====================================================================
        // TEST 6: Max BTT (23'h4000 = 16KB, but limited by DataMover BTT=23)
        //         Use 4096 bytes (one page) for practical test
        // =====================================================================
        $display("\n===================================================================");
        $display("  TEST 6: 4096-byte block write + read (page-sized)");
        $display("===================================================================");

        send_s2mm_cmd(32'h0010_0000, 23'd4096);

        // 4096 bytes = 64 beats of 512-bit at full width
        pat = 512'h01234567_89ABCDEF_FEDCBA98_76543210_01234567_89ABCDEF_FEDCBA98_76543210_01234567_89ABCDEF_FEDCBA98_76543210_01234567_89ABCDEF_FEDCBA98_76543210;
        begin
            integer i;
            for (i = 0; i < 63; i = i + 1)
                inject_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
            inject_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);  // last beat
        end
        $display("  [%0t ns] Data injected (64 beats, 4096 bytes)", $time/1000);

        wait_s2mm_sts;
        if (s2mm_err) begin $error("  [FAIL] S2MM error in 4KB test!"); fail_cnt = fail_cnt + 1; end

        #5000000;

        send_mm2s_cmd(32'h0010_0000, 23'd4096);

        begin
            integer i;
            for (i = 0; i < 63; i = i + 1)
                verify_read_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0);
            verify_read_beat(pat, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1);
        end
        $display("  [%0t ns] All 64 beats received", $time/1000);

        wait_mm2s_sts;
        if (mm2s_err) begin $error("  [FAIL] MM2S error in 4KB test!"); fail_cnt = fail_cnt + 1; end

        log_diag;

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n=================================================");
        $display("  Simulation Complete");
        $display("=================================================");
        $display("  S2MM err: %b", s2mm_err);
        $display("  MM2S err: %b", mm2s_err);
        $display("  Final FIFO_RX_CNT: %0d", axis_wr_data_count_0);
        $display("  Final FIFO_TX_CNT: %0d", axis_wr_data_count_1);
        if (fail_cnt > 0)
            $display("  [RESULT] %0d failure(s) detected!", fail_cnt);
        else
            $display("  [RESULT] All tests passed!");
        $display("=================================================\n");

        #100000;
        $finish;
    end

endmodule
