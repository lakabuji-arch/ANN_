`timescale 1ns / 1ps

module dma_ddr4_sys_wrapper (
    input  wire         clk_50m,
    output wire         clk_100m,
    input  wire         usr_mac_clk,
    input  wire         sys_rst,
    output wire         c0_ddr4_ui_clk,
    input  wire         diff_clock_rtl_0_clk_p,
    input  wire         diff_clock_rtl_0_clk_n,

    output wire         ddr4_rtl_0_act_n,
    output wire [16:0]  ddr4_rtl_0_adr,
    output wire [1:0]   ddr4_rtl_0_ba,
    output wire [0:0]   ddr4_rtl_0_bg,
    output wire [0:0]   ddr4_rtl_0_ck_c,
    output wire [0:0]   ddr4_rtl_0_ck_t,
    output wire [0:0]   ddr4_rtl_0_cke,
    output wire [0:0]   ddr4_rtl_0_cs_n,
    inout  wire [3:0]   ddr4_rtl_0_dm_n,
    inout  wire [31:0]  ddr4_rtl_0_dq,
    inout  wire [3:0]   ddr4_rtl_0_dqs_c,
    inout  wire [3:0]   ddr4_rtl_0_dqs_t,
    output wire [0:0]   ddr4_rtl_0_odt,
    output wire         ddr4_rtl_0_reset_n,

    input  wire [511:0] S_AXIS_RX_tdata,
    input  wire [63:0]  S_AXIS_RX_tkeep,
    input  wire         S_AXIS_RX_tvalid,
    input  wire         S_AXIS_RX_tlast,
    output wire         S_AXIS_RX_tready,

    output wire [511:0] M_AXIS_TX_tdata,
    output wire [63:0]  M_AXIS_TX_tkeep,
    output wire         M_AXIS_TX_tvalid,
    output wire         M_AXIS_TX_tlast,
    input  wire         M_AXIS_TX_tready,

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
    output wire         mm2s_err_0,
    output wire [31:0]  axis_wr_data_count_0,
    output wire [31:0]  axis_wr_data_count_1
);

    wire usr_mac_rst_n = ~sys_rst;
    wire c0_init_calib_complete_i;
    wire dm_rst_n = usr_mac_rst_n & c0_init_calib_complete_i;
    wire [11:0] rx_cdc_wr_count;
    wire [11:0] tx_cdc_wr_count;
    wire rx_fifo_full;

    assign clk_100m              = diff_clock_rtl_0_clk_p;
    assign M_AXIS_S2MM_STS_0_tkeep = 1'b1;
    assign M_AXIS_S2MM_STS_0_tlast = 1'b1;
    assign M_AXIS_MM2S_STS_0_tkeep = 1'b1;
    assign M_AXIS_MM2S_STS_0_tlast = 1'b1;
    assign axis_wr_data_count_0  = {20'd0, rx_cdc_wr_count};
    assign axis_wr_data_count_1  = {20'd0, tx_cdc_wr_count};

    ddr4_subsystem_top dma_ddr4_sys_i (
        .usr_mac_clk             (usr_mac_clk),
        .usr_mac_rst_n           (usr_mac_rst_n),
        .c0_ddr4_ui_clk          (c0_ddr4_ui_clk),
        .sys_rst                 (sys_rst),
        .dm_rst_n                (dm_rst_n),
        .c0_init_calib_complete  (c0_init_calib_complete_i),
        .diff_clock_rtl_0_clk_p  (diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_0_clk_n  (diff_clock_rtl_0_clk_n),
        .ddr4_rtl_0_act_n        (ddr4_rtl_0_act_n),
        .ddr4_rtl_0_adr          (ddr4_rtl_0_adr),
        .ddr4_rtl_0_ba           (ddr4_rtl_0_ba),
        .ddr4_rtl_0_bg           (ddr4_rtl_0_bg),
        .ddr4_rtl_0_ck_c         (ddr4_rtl_0_ck_c),
        .ddr4_rtl_0_ck_t         (ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke          (ddr4_rtl_0_cke),
        .ddr4_rtl_0_cs_n         (ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_dm_n         (ddr4_rtl_0_dm_n),
        .ddr4_rtl_0_dq           (ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c        (ddr4_rtl_0_dqs_c),
        .ddr4_rtl_0_dqs_t        (ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_odt          (ddr4_rtl_0_odt),
        .ddr4_rtl_0_reset_n      (ddr4_rtl_0_reset_n),
        .S_AXIS_RX_tdata         (S_AXIS_RX_tdata),
        .S_AXIS_RX_tkeep         (S_AXIS_RX_tkeep),
        .S_AXIS_RX_tvalid        (S_AXIS_RX_tvalid),
        .S_AXIS_RX_tlast         (S_AXIS_RX_tlast),
        .S_AXIS_RX_tready        (S_AXIS_RX_tready),
        .M_AXIS_TX_tdata         (M_AXIS_TX_tdata),
        .M_AXIS_TX_tkeep         (M_AXIS_TX_tkeep),
        .M_AXIS_TX_tvalid        (M_AXIS_TX_tvalid),
        .M_AXIS_TX_tlast         (M_AXIS_TX_tlast),
        .M_AXIS_TX_tready        (M_AXIS_TX_tready),
        .S_AXIS_S2MM_CMD_0_tdata (S_AXIS_S2MM_CMD_0_tdata),
        .S_AXIS_S2MM_CMD_0_tvalid(S_AXIS_S2MM_CMD_0_tvalid),
        .S_AXIS_S2MM_CMD_0_tready(S_AXIS_S2MM_CMD_0_tready),
        .M_AXIS_S2MM_STS_0_tdata (M_AXIS_S2MM_STS_0_tdata),
        .M_AXIS_S2MM_STS_0_tvalid(M_AXIS_S2MM_STS_0_tvalid),
        .M_AXIS_S2MM_STS_0_tready(M_AXIS_S2MM_STS_0_tready),
        .S_AXIS_MM2S_CMD_0_tdata (S_AXIS_MM2S_CMD_0_tdata),
        .S_AXIS_MM2S_CMD_0_tvalid(S_AXIS_MM2S_CMD_0_tvalid),
        .S_AXIS_MM2S_CMD_0_tready(S_AXIS_MM2S_CMD_0_tready),
        .M_AXIS_MM2S_STS_0_tdata (M_AXIS_MM2S_STS_0_tdata),
        .M_AXIS_MM2S_STS_0_tvalid(M_AXIS_MM2S_STS_0_tvalid),
        .M_AXIS_MM2S_STS_0_tready(M_AXIS_MM2S_STS_0_tready),
        .s2mm_err_0              (s2mm_err_0),
        .mm2s_err_0              (mm2s_err_0),
        .rx_cdc_wr_count         (rx_cdc_wr_count),
        .tx_cdc_wr_count         (tx_cdc_wr_count),
        .rx_fifo_full            (rx_fifo_full)
    );

endmodule