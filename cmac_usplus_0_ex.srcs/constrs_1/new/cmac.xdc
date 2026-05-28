# =========================================================================
# 1. 主时钟频率约束
# =========================================================================
create_clock -period 20.000 -name clk_50m_in -waveform {0.000 10.000} [get_ports clk_50m_in]
create_clock -period 6.400 -name gt_ref_clk_p -waveform {0.000 3.200} [get_ports gt_ref_clk_p]
# diff_clock_rtl_0_clk_p 时钟由 DDR4 IP 自动生成约束，此处不再重复定义

# =========================================================================
# 2. 系统基础引脚 (时钟、复位)
# =========================================================================
set_property PACKAGE_PIN E18 [get_ports clk_50m_in]
set_property IOSTANDARD LVCMOS18 [get_ports clk_50m_in]

set_property PACKAGE_PIN P19 [get_ports sys_rst_pad_in]
set_property IOSTANDARD LVCMOS12 [get_ports sys_rst_pad_in]

# DDR4 参考时钟引脚
set_property PACKAGE_PIN T24 [get_ports diff_clock_rtl_0_clk_p]
set_property PACKAGE_PIN T25 [get_ports diff_clock_rtl_0_clk_n]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports diff_clock_rtl_0_clk_p]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports diff_clock_rtl_0_clk_n]

# =========================================================================
# 3. 100G CMAC / GT 物理约束
# =========================================================================
set_property PACKAGE_PIN T7 [get_ports gt_ref_clk_p]

# GT TX 位置约束
set_property PACKAGE_PIN R4 [get_ports {gt_txp_out[0]}]
set_property PACKAGE_PIN N4 [get_ports {gt_txp_out[1]}]
set_property PACKAGE_PIN L4 [get_ports {gt_txp_out[2]}]
set_property PACKAGE_PIN J4 [get_ports {gt_txp_out[3]}]

# GT RX 位置约束 (结合了你的 LOC 修改)
set_property LOC GTYE4_CHANNEL_X0Y4 [get_cells {u_cmac_wrapper/DUT/inst/cmac_usplus_0_gt_i/inst/gen_gtwizard_gtye4_top.cmac_usplus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[3].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST}]
set_property PACKAGE_PIN Y2 [get_ports {gt_rxp_in[0]}]
set_property LOC GTYE4_CHANNEL_X0Y5 [get_cells {u_cmac_wrapper/DUT/inst/cmac_usplus_0_gt_i/inst/gen_gtwizard_gtye4_top.cmac_usplus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[3].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[1].GTYE4_CHANNEL_PRIM_INST}]
set_property PACKAGE_PIN V2 [get_ports {gt_rxp_in[1]}]
set_property LOC GTYE4_CHANNEL_X0Y6 [get_cells {u_cmac_wrapper/DUT/inst/cmac_usplus_0_gt_i/inst/gen_gtwizard_gtye4_top.cmac_usplus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[3].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[2].GTYE4_CHANNEL_PRIM_INST}]
set_property PACKAGE_PIN T2 [get_ports {gt_rxp_in[2]}]
set_property LOC GTYE4_CHANNEL_X0Y7 [get_cells {u_cmac_wrapper/DUT/inst/cmac_usplus_0_gt_i/inst/gen_gtwizard_gtye4_top.cmac_usplus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[3].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST}]
set_property PACKAGE_PIN P2 [get_ports {gt_rxp_in[3]}]

# =========================================================================
# 4. DDR4 物理引脚分配 (32-bit 数据总线)
# =========================================================================
# --- 控制信号 ---
set_property PACKAGE_PIN V19 [get_ports ddr4_rtl_0_act_n]
set_property IOSTANDARD SSTL12_DCI [get_ports ddr4_rtl_0_act_n]

set_property PACKAGE_PIN P23 [get_ports ddr4_rtl_0_reset_n]
set_property IOSTANDARD LVCMOS12 [get_ports ddr4_rtl_0_reset_n]

# --- 地址与 Bank 信号 ---
set_property PACKAGE_PIN P26 [get_ports {ddr4_rtl_0_adr[0]}]
set_property PACKAGE_PIN P25 [get_ports {ddr4_rtl_0_adr[1]}]
set_property PACKAGE_PIN R22 [get_ports {ddr4_rtl_0_adr[2]}]
set_property PACKAGE_PIN AA24 [get_ports {ddr4_rtl_0_adr[3]}]
set_property PACKAGE_PIN T23 [get_ports {ddr4_rtl_0_adr[4]}]
set_property PACKAGE_PIN W20 [get_ports {ddr4_rtl_0_adr[5]}]
set_property PACKAGE_PIN T22 [get_ports {ddr4_rtl_0_adr[6]}]
set_property PACKAGE_PIN W19 [get_ports {ddr4_rtl_0_adr[7]}]
set_property PACKAGE_PIN U21 [get_ports {ddr4_rtl_0_adr[8]}]
set_property PACKAGE_PIN P21 [get_ports {ddr4_rtl_0_adr[9]}]
set_property PACKAGE_PIN V22 [get_ports {ddr4_rtl_0_adr[10]}]
set_property PACKAGE_PIN U19 [get_ports {ddr4_rtl_0_adr[11]}]
set_property PACKAGE_PIN Y25 [get_ports {ddr4_rtl_0_adr[12]}]
set_property PACKAGE_PIN P20 [get_ports {ddr4_rtl_0_adr[13]}]
set_property PACKAGE_PIN Y23 [get_ports {ddr4_rtl_0_adr[14]}]
set_property PACKAGE_PIN U26 [get_ports {ddr4_rtl_0_adr[15]}]
set_property PACKAGE_PIN V26 [get_ports {ddr4_rtl_0_adr[16]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_adr[*]}]

set_property PACKAGE_PIN U22 [get_ports {ddr4_rtl_0_ba[0]}]
set_property PACKAGE_PIN R26 [get_ports {ddr4_rtl_0_ba[1]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_ba[*]}]

set_property PACKAGE_PIN V21 [get_ports {ddr4_rtl_0_bg[0]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_bg[*]}]

# --- 🚨 致命冲突区：时钟、选通与片选 🚨 ---
set_property PACKAGE_PIN W25 [get_ports {ddr4_rtl_0_ck_t[0]}]


set_property PACKAGE_PIN Y22 [get_ports {ddr4_rtl_0_cke[0]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_cke[*]}]

# TODO: 请查原理图！cs_n 如果真的是 Y26，那么上面的时钟负端就必须改掉。
set_property PACKAGE_PIN Y26 [get_ports {ddr4_rtl_0_cs_n[0]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_cs_n[*]}]

set_property PACKAGE_PIN AA25 [get_ports {ddr4_rtl_0_odt[0]}]
set_property IOSTANDARD SSTL12_DCI [get_ports {ddr4_rtl_0_odt[*]}]

# --- 数据掩码 (DM) ---
set_property PACKAGE_PIN AE25 [get_ports {ddr4_rtl_0_dm_n[0]}]
set_property PACKAGE_PIN AE22 [get_ports {ddr4_rtl_0_dm_n[1]}]
set_property PACKAGE_PIN AD20 [get_ports {ddr4_rtl_0_dm_n[2]}]
set_property PACKAGE_PIN Y20 [get_ports {ddr4_rtl_0_dm_n[3]}]
set_property IOSTANDARD POD12_DCI [get_ports {ddr4_rtl_0_dm_n[*]}]

# --- 数据总线 (DQ) [整合了末尾的大量修改] ---
set_property PACKAGE_PIN AD24 [get_ports {ddr4_rtl_0_dq[0]}]
set_property PACKAGE_PIN AF24 [get_ports {ddr4_rtl_0_dq[1]}]
set_property PACKAGE_PIN AB26 [get_ports {ddr4_rtl_0_dq[2]}]
set_property PACKAGE_PIN AB24 [get_ports {ddr4_rtl_0_dq[3]}]
set_property PACKAGE_PIN AC24 [get_ports {ddr4_rtl_0_dq[4]}]
set_property PACKAGE_PIN AB25 [get_ports {ddr4_rtl_0_dq[5]}]
set_property PACKAGE_PIN AF25 [get_ports {ddr4_rtl_0_dq[6]}]
set_property PACKAGE_PIN AD25 [get_ports {ddr4_rtl_0_dq[7]}]
set_property PACKAGE_PIN AD23 [get_ports {ddr4_rtl_0_dq[8]}]
set_property PACKAGE_PIN AE23 [get_ports {ddr4_rtl_0_dq[9]}]
set_property PACKAGE_PIN AD21 [get_ports {ddr4_rtl_0_dq[10]}]
set_property PACKAGE_PIN AC23 [get_ports {ddr4_rtl_0_dq[11]}]
set_property PACKAGE_PIN AC22 [get_ports {ddr4_rtl_0_dq[12]}]
set_property PACKAGE_PIN AE21 [get_ports {ddr4_rtl_0_dq[13]}]
set_property PACKAGE_PIN AB21 [get_ports {ddr4_rtl_0_dq[14]}]
set_property PACKAGE_PIN AC21 [get_ports {ddr4_rtl_0_dq[15]}]
set_property PACKAGE_PIN AF17 [get_ports {ddr4_rtl_0_dq[16]}]
set_property PACKAGE_PIN AE17 [get_ports {ddr4_rtl_0_dq[17]}]
set_property PACKAGE_PIN AC19 [get_ports {ddr4_rtl_0_dq[18]}]
set_property PACKAGE_PIN AF18 [get_ports {ddr4_rtl_0_dq[19]}]
set_property PACKAGE_PIN AF19 [get_ports {ddr4_rtl_0_dq[20]}]
set_property PACKAGE_PIN AD19 [get_ports {ddr4_rtl_0_dq[21]}]
set_property PACKAGE_PIN AE16 [get_ports {ddr4_rtl_0_dq[22]}]
set_property PACKAGE_PIN AD16 [get_ports {ddr4_rtl_0_dq[23]}]
set_property PACKAGE_PIN AB20 [get_ports {ddr4_rtl_0_dq[24]}]
set_property PACKAGE_PIN AB19 [get_ports {ddr4_rtl_0_dq[25]}]
set_property PACKAGE_PIN AA19 [get_ports {ddr4_rtl_0_dq[26]}]
set_property PACKAGE_PIN AA20 [get_ports {ddr4_rtl_0_dq[27]}]
set_property PACKAGE_PIN Y17 [get_ports {ddr4_rtl_0_dq[28]}]
set_property PACKAGE_PIN AA17 [get_ports {ddr4_rtl_0_dq[29]}]
set_property PACKAGE_PIN Y18 [get_ports {ddr4_rtl_0_dq[30]}]
set_property PACKAGE_PIN AA18 [get_ports {ddr4_rtl_0_dq[31]}]
set_property IOSTANDARD POD12_DCI [get_ports {ddr4_rtl_0_dq[*]}]

# --- 数据选通 (DQS) ---
set_property PACKAGE_PIN AC26 [get_ports {ddr4_rtl_0_dqs_t[0]}]
set_property PACKAGE_PIN AD26 [get_ports {ddr4_rtl_0_dqs_c[0]}]
set_property PACKAGE_PIN AA22 [get_ports {ddr4_rtl_0_dqs_t[1]}]
set_property PACKAGE_PIN AB22 [get_ports {ddr4_rtl_0_dqs_c[1]}]
set_property PACKAGE_PIN AC18 [get_ports {ddr4_rtl_0_dqs_t[2]}]
set_property PACKAGE_PIN AD18 [get_ports {ddr4_rtl_0_dqs_c[2]}]
set_property PACKAGE_PIN AB17 [get_ports {ddr4_rtl_0_dqs_t[3]}]
set_property PACKAGE_PIN AC16 [get_ports {ddr4_rtl_0_dqs_c[3]}]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports {ddr4_rtl_0_dqs_t[*]}]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports {ddr4_rtl_0_dqs_c[*]}]



##------------------------------------------------------------------------------
##  LED 状态指示灯约束
##------------------------------------------------------------------------------
# 警告：以下 PACKAGE_PIN 为示例，请务必替换为你板子上真实的 LED 引脚！
set_property PACKAGE_PIN E16 [get_ports {led_out[0]}]
set_property PACKAGE_PIN E17 [get_ports {led_out[1]}]
set_property PACKAGE_PIN F15 [get_ports {led_out[2]}]
set_property PACKAGE_PIN D15 [get_ports {led_out[3]}]

# 替换为你板子上 LED 所在 Bank 的实际电平
set_property IOSTANDARD LVCMOS18 [get_ports {led_out[*]}]

# 异步时钟组 — 基于根时钟端口划分，自动涵盖所有派生时钟
# clk_50m_in → clk_100m (clk_wiz)
# gt_ref_clk_p → usr_mac_clk (CMAC)
# diff_clock_rtl_0_clk_p → c0_ddr4_ui_clk (DDR4)
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks -of_objects [get_ports clk_50m_in]] -group [get_clocks -include_generated_clocks -of_objects [get_ports gt_ref_clk_p]] -group [get_clocks -include_generated_clocks -of_objects [get_ports diff_clock_rtl_0_clk_p]]

# =========================================================================
# 5. 配置与位流约束
# =========================================================================
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 31.9 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# =========================================================================
# ILA — 已禁用。需要时通过 Vivado "Set Up Debug" GUI 重新添加
# =========================================================================
