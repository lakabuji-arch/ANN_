`timescale 1ns / 1ps

module tb_tx_reset_alignment_force;

    reg clk_50m_in = 1'b0;
    reg sys_rst_pad_in = 1'b1;
    reg gt_ref_clk_p = 1'b0;
    reg gt_ref_clk_n = 1'b1;
    reg [3:0] gt_rxp_in = 4'd0;
    reg [3:0] gt_rxn_in = 4'd0;
    reg diff_clock_rtl_0_clk_p = 1'b0;
    reg diff_clock_rtl_0_clk_n = 1'b1;

    wire [3:0] gt_txp_out;
    wire [3:0] gt_txn_out;
    wire       ddr4_rtl_0_act_n;
    wire [16:0] ddr4_rtl_0_adr;
    wire [1:0] ddr4_rtl_0_ba;
    wire [0:0] ddr4_rtl_0_bg;
    wire [0:0] ddr4_rtl_0_ck_c;
    wire [0:0] ddr4_rtl_0_ck_t;
    wire [0:0] ddr4_rtl_0_cke;
    wire [0:0] ddr4_rtl_0_cs_n;
    wire [3:0] ddr4_rtl_0_dm_n;
    wire [31:0] ddr4_rtl_0_dq;
    wire [3:0] ddr4_rtl_0_dqs_c;
    wire [3:0] ddr4_rtl_0_dqs_t;
    wire [0:0] ddr4_rtl_0_odt;
    wire       ddr4_rtl_0_reset_n;
    wire [3:0] led_out;

    fpga_top_100g dut (
        .clk_50m_in            (clk_50m_in),
        .sys_rst_pad_in        (sys_rst_pad_in),
        .gt_ref_clk_p          (gt_ref_clk_p),
        .gt_ref_clk_n          (gt_ref_clk_n),
        .gt_rxp_in             (gt_rxp_in),
        .gt_rxn_in             (gt_rxn_in),
        .gt_txp_out            (gt_txp_out),
        .gt_txn_out            (gt_txn_out),
        .ddr4_rtl_0_act_n      (ddr4_rtl_0_act_n),
        .ddr4_rtl_0_adr        (ddr4_rtl_0_adr),
        .ddr4_rtl_0_ba         (ddr4_rtl_0_ba),
        .ddr4_rtl_0_bg         (ddr4_rtl_0_bg),
        .ddr4_rtl_0_ck_c       (ddr4_rtl_0_ck_c),
        .ddr4_rtl_0_ck_t       (ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke        (ddr4_rtl_0_cke),
        .ddr4_rtl_0_cs_n       (ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_dm_n       (ddr4_rtl_0_dm_n),
        .ddr4_rtl_0_dq         (ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c      (ddr4_rtl_0_dqs_c),
        .ddr4_rtl_0_dqs_t      (ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_odt        (ddr4_rtl_0_odt),
        .ddr4_rtl_0_reset_n    (ddr4_rtl_0_reset_n),
        .diff_clock_rtl_0_clk_p(diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_0_clk_n(diff_clock_rtl_0_clk_n),
        .led_out               (led_out)
    );

    always #10.0 clk_50m_in = ~clk_50m_in;
    always #3.2 begin
        gt_ref_clk_p = ~gt_ref_clk_p;
        gt_ref_clk_n = ~gt_ref_clk_n;
    end
    always #5.0 begin
        diff_clock_rtl_0_clk_p = ~diff_clock_rtl_0_clk_p;
        diff_clock_rtl_0_clk_n = ~diff_clock_rtl_0_clk_n;
    end

    task automatic wait_tx_queued(input [127:0] stage_name);
        integer cycles;
        begin
            cycles = 0;
            while ((dut.tx_meta_empty || (dut.tx_cdc_wr_count == 0)) && (cycles < 300)) begin
                @(posedge dut.c0_ddr4_ui_clk);
                cycles = cycles + 1;
            end
            if (dut.tx_meta_empty || (dut.tx_cdc_wr_count == 0)) begin
                $error("[%0t] %0s queue timeout: tx_meta_empty=%0b tx_fifo_cnt=%0d", $time, stage_name, dut.tx_meta_empty, dut.tx_cdc_wr_count);
                $fatal;
            end
            $display("[%0t] %0s queued: tx_meta_empty=%0b tx_fifo_cnt=%0d", $time, stage_name, dut.tx_meta_empty, dut.tx_cdc_wr_count);
        end
    endtask

    task automatic wait_tx_flushed(input [127:0] stage_name);
        integer cycles;
        begin
            cycles = 0;
            while (((!dut.tx_meta_empty) || (dut.tx_cdc_wr_count != 0)) && (cycles < 300)) begin
                @(posedge dut.c0_ddr4_ui_clk);
                cycles = cycles + 1;
            end
            if ((!dut.tx_meta_empty) || (dut.tx_cdc_wr_count != 0)) begin
                $error("[%0t] %0s flush timeout: tx_meta_empty=%0b tx_fifo_cnt=%0d", $time, stage_name, dut.tx_meta_empty, dut.tx_cdc_wr_count);
                $fatal;
            end
            $display("[%0t] %0s flushed: tx_meta_empty=%0b tx_fifo_cnt=%0d", $time, stage_name, dut.tx_meta_empty, dut.tx_cdc_wr_count);
        end
    endtask

    task automatic inject_tx_packet;
        begin
            force dut.mm2s_cmd_tdata = {4'h0, 4'h1, 32'h4000_0000, 1'b0, 1'b1, 6'd0, 1'b1, 23'd64};
            force dut.mm2s_cmd_tvalid = 1'b1;
            force dut.u_bd_wrapper.bd_mm2s_tdata = {8{64'h8877665544332211}};
            force dut.u_bd_wrapper.bd_mm2s_tkeep = 64'hFFFF_FFFF_FFFF_FFFF;
            force dut.u_bd_wrapper.bd_mm2s_tlast = 1'b1;
            force dut.u_bd_wrapper.bd_mm2s_tvalid = 1'b1;
            repeat (2) @(posedge dut.c0_ddr4_ui_clk);
            release dut.mm2s_cmd_tdata;
            release dut.mm2s_cmd_tvalid;
            release dut.u_bd_wrapper.bd_mm2s_tdata;
            release dut.u_bd_wrapper.bd_mm2s_tkeep;
            release dut.u_bd_wrapper.bd_mm2s_tlast;
            release dut.u_bd_wrapper.bd_mm2s_tvalid;
        end
    endtask

    initial begin
        #200000;
        $error("[FATAL] tb_tx_reset_alignment_force timeout");
        $fatal;
    end

    initial begin
        repeat (8) @(posedge clk_50m_in);
        sys_rst_pad_in = 1'b0;

        wait (dut.c0_ddr4_ui_clk === 1'b0 || dut.c0_ddr4_ui_clk === 1'b1);
        repeat (8) @(posedge dut.c0_ddr4_ui_clk);
        force dut.dm_rst_n_reg = 1'b1;

        wait (dut.datamover_rst_n == 1'b1);
        wait (dut.usr_mac_rst_n == 1'b1);
        repeat (32) @(posedge dut.c0_ddr4_ui_clk);

        inject_tx_packet();
        wait_tx_queued("before usr_mac reset");

        force dut.usr_mac_rst_n = 1'b0;
        repeat (8) @(posedge dut.usr_mac_clk);
        wait_tx_flushed("during usr_mac reset pulse");
        release dut.usr_mac_rst_n;

        wait (dut.usr_mac_rst_n == 1'b1);
        repeat (32) @(posedge dut.c0_ddr4_ui_clk);

        inject_tx_packet();
        wait_tx_queued("after usr_mac reset recovery");

        $display("[%0t] tb_tx_reset_alignment_force PASS", $time);
        $finish;
    end

endmodule

module clk_wiz_0 (
    output reg clk_out1,
    output wire clk_out2,
    input  wire reset,
    output reg locked,
    input  wire clk_in1
);

    assign clk_out2 = 1'b0;

    initial begin
        clk_out1 = 1'b0;
        locked   = 1'b0;
    end

    always #5.0 clk_out1 = ~clk_out1;

    always @(posedge clk_out1 or posedge reset) begin
        if (reset)
            locked <= 1'b0;
        else
            locked <= 1'b1;
    end

endmodule

module cmac_100g_wrapper (
    input  wire         gt_ref_clk_p,
    input  wire         gt_ref_clk_n,
    input  wire [3:0]   gt_rxp_in,
    input  wire [3:0]   gt_rxn_in,
    output wire [3:0]   gt_txp_out,
    output wire [3:0]   gt_txn_out,
    input  wire         init_clk,
    input  wire         sys_reset,
    output reg          usr_mac_clk,
    output reg          usr_mac_rst_n,
    output reg          mac_link_up,
    output wire [511:0] m_axis_rx_tdata,
    output wire [63:0]  m_axis_rx_tkeep,
    output wire         m_axis_rx_tvalid,
    output wire         m_axis_rx_tlast,
    input  wire         m_axis_rx_tready,
    output wire         o_payload_cmd_valid,
    output wire [15:0]  o_payload_bytes,
    input  wire [511:0] s_axis_tx_tdata,
    input  wire [63:0]  s_axis_tx_tkeep,
    input  wire         s_axis_tx_tvalid,
    input  wire         s_axis_tx_tlast,
    output wire         s_axis_tx_tready,
    input  wire [15:0]  i_tx_payload_bytes,
    input  wire         tx_meta_empty,
    output wire         o_tx_meta_rd_en,
    input  wire [8:0]   tx_pause_req
);

    assign gt_txp_out          = 4'd0;
    assign gt_txn_out          = 4'd0;
    assign m_axis_rx_tdata     = 512'd0;
    assign m_axis_rx_tkeep     = 64'd0;
    assign m_axis_rx_tvalid    = 1'b0;
    assign m_axis_rx_tlast     = 1'b0;
    assign o_payload_cmd_valid = 1'b0;
    assign o_payload_bytes     = 16'd0;
    assign s_axis_tx_tready    = 1'b0;
    assign o_tx_meta_rd_en     = 1'b0;

    initial begin
        usr_mac_clk   = 1'b0;
        usr_mac_rst_n = 1'b0;
        mac_link_up   = 1'b0;
    end

    always #1.553 usr_mac_clk = ~usr_mac_clk;

    always @(posedge usr_mac_clk or posedge sys_reset) begin
        if (sys_reset) begin
            usr_mac_rst_n <= 1'b0;
            mac_link_up   <= 1'b0;
        end else begin
            usr_mac_rst_n <= 1'b1;
            mac_link_up   <= 1'b1;
        end
    end

endmodule

module datamover_ctrl (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rx_fifo_empty,
    input  wire [15:0]  rx_fifo_len,
    output wire         rx_fifo_rd_en,
    output wire [71:0]  s2mm_cmd_tdata,
    output wire         s2mm_cmd_tvalid,
    input  wire         s2mm_cmd_tready,
    input  wire         s2mm_sts_tvalid,
    input  wire         s2mm_err,
    input  wire         tx_trigger_pulse,
    input  wire [15:0]  tx_request_bytes,
    output wire [15:0]  o_framer_tx_bytes,
    output wire [71:0]  mm2s_cmd_tdata,
    output wire         mm2s_cmd_tvalid,
    input  wire         mm2s_cmd_tready,
    input  wire [31:0]  cfg_rx_base_addr,
    input  wire [31:0]  cfg_tx_base_addr,
    output wire [15:0]  o_diag_s2mm_cmd_cnt,
    output wire [15:0]  o_diag_mm2s_cmd_cnt,
    output wire         o_diag_lb_fifo_empty,
    output wire         o_diag_rx_meta_waiting
);

    assign rx_fifo_rd_en          = 1'b0;
    assign s2mm_cmd_tdata         = 72'd0;
    assign s2mm_cmd_tvalid        = 1'b0;
    assign o_framer_tx_bytes      = 16'd64;
    assign mm2s_cmd_tdata         = 72'd0;
    assign mm2s_cmd_tvalid        = 1'b0;
    assign o_diag_s2mm_cmd_cnt    = 16'd0;
    assign o_diag_mm2s_cmd_cnt    = 16'd0;
    assign o_diag_lb_fifo_empty   = 1'b1;
    assign o_diag_rx_meta_waiting = 1'b0;

endmodule

module ddr4_dma_subsystem_wrapper (
    output wire         C0_DDR4_0_act_n,
    output wire [16:0]  C0_DDR4_0_adr,
    output wire [1:0]   C0_DDR4_0_ba,
    output wire [0:0]   C0_DDR4_0_bg,
    output wire [0:0]   C0_DDR4_0_ck_c,
    output wire [0:0]   C0_DDR4_0_ck_t,
    output wire [0:0]   C0_DDR4_0_cke,
    output wire [0:0]   C0_DDR4_0_cs_n,
    inout  wire [3:0]   C0_DDR4_0_dm_n,
    inout  wire [31:0]  C0_DDR4_0_dq,
    inout  wire [3:0]   C0_DDR4_0_dqs_c,
    inout  wire [3:0]   C0_DDR4_0_dqs_t,
    output wire [0:0]   C0_DDR4_0_odt,
    output wire         C0_DDR4_0_reset_n,
    input  wire         C0_SYS_CLK_0_clk_p,
    input  wire         C0_SYS_CLK_0_clk_n,
    output reg          c0_ddr4_ui_clk,
    output reg          c0_init_calib_complete_0,
    input  wire         sys_rst,
    input  wire [511:0] S_AXIS_S2MM_0_tdata,
    input  wire [63:0]  S_AXIS_S2MM_0_tkeep,
    input  wire         S_AXIS_S2MM_0_tlast,
    input  wire         S_AXIS_S2MM_0_tvalid,
    output wire         S_AXIS_S2MM_0_tready,
    output wire [511:0] M_AXIS_MM2S_0_tdata,
    output wire [63:0]  M_AXIS_MM2S_0_tkeep,
    output wire         M_AXIS_MM2S_0_tlast,
    output wire         M_AXIS_MM2S_0_tvalid,
    input  wire         M_AXIS_MM2S_0_tready,
    input  wire [71:0]  S_AXIS_S2MM_CMD_0_tdata,
    input  wire         S_AXIS_S2MM_CMD_0_tvalid,
    output wire         S_AXIS_S2MM_CMD_0_tready,
    output wire [7:0]   M_AXIS_S2MM_STS_0_tdata,
    output wire [0:0]   M_AXIS_S2MM_STS_0_tkeep,
    output wire         M_AXIS_S2MM_STS_0_tlast,
    output wire         M_AXIS_S2MM_STS_0_tvalid,
    input  wire         M_AXIS_S2MM_STS_0_tready,
    input  wire [71:0]  S_AXIS_MM2S_CMD_0_tdata,
    input  wire         S_AXIS_MM2S_CMD_0_tvalid,
    output wire         S_AXIS_MM2S_CMD_0_tready,
    output wire [7:0]   M_AXIS_MM2S_STS_0_tdata,
    output wire [0:0]   M_AXIS_MM2S_STS_0_tkeep,
    output wire         M_AXIS_MM2S_STS_0_tlast,
    output wire         M_AXIS_MM2S_STS_0_tvalid,
    input  wire         M_AXIS_MM2S_STS_0_tready,
    output wire         s2mm_err_0,
    output wire         mm2s_err_0
);

    assign C0_DDR4_0_act_n         = 1'b1;
    assign C0_DDR4_0_adr           = 17'd0;
    assign C0_DDR4_0_ba            = 2'd0;
    assign C0_DDR4_0_bg            = 1'd0;
    assign C0_DDR4_0_ck_c          = 1'd0;
    assign C0_DDR4_0_ck_t          = 1'd0;
    assign C0_DDR4_0_cke           = 1'd0;
    assign C0_DDR4_0_cs_n          = 1'd1;
    assign C0_DDR4_0_odt           = 1'd0;
    assign C0_DDR4_0_reset_n       = 1'b1;
    assign C0_DDR4_0_dm_n          = 4'bzzzz;
    assign C0_DDR4_0_dq            = 32'hzzzzzzzz;
    assign C0_DDR4_0_dqs_c         = 4'bzzzz;
    assign C0_DDR4_0_dqs_t         = 4'bzzzz;
    assign S_AXIS_S2MM_0_tready    = 1'b1;
    assign M_AXIS_MM2S_0_tdata     = 512'd0;
    assign M_AXIS_MM2S_0_tkeep     = 64'd0;
    assign M_AXIS_MM2S_0_tlast     = 1'b0;
    assign M_AXIS_MM2S_0_tvalid    = 1'b0;
    assign S_AXIS_S2MM_CMD_0_tready = 1'b1;
    assign M_AXIS_S2MM_STS_0_tdata = 8'd0;
    assign M_AXIS_S2MM_STS_0_tkeep = 1'b1;
    assign M_AXIS_S2MM_STS_0_tlast = 1'b1;
    assign M_AXIS_S2MM_STS_0_tvalid = 1'b0;
    assign S_AXIS_MM2S_CMD_0_tready = 1'b1;
    assign M_AXIS_MM2S_STS_0_tdata = 8'd0;
    assign M_AXIS_MM2S_STS_0_tkeep = 1'b1;
    assign M_AXIS_MM2S_STS_0_tlast = 1'b1;
    assign M_AXIS_MM2S_STS_0_tvalid = 1'b0;
    assign s2mm_err_0              = 1'b0;
    assign mm2s_err_0              = 1'b0;

    initial begin
        c0_ddr4_ui_clk           = 1'b0;
        c0_init_calib_complete_0 = 1'b0;
    end

    always #1.500 c0_ddr4_ui_clk = ~c0_ddr4_ui_clk;

    always @(posedge c0_ddr4_ui_clk or posedge sys_rst) begin
        if (sys_rst)
            c0_init_calib_complete_0 <= 1'b0;
        else
            c0_init_calib_complete_0 <= 1'b1;
    end

endmodule