# Vivado Non-Project Mode 全流程脚本
# 用法: vivado -mode batch -source run_build.tcl -tclargs <top> <part> <out_dir> <rpt_dir>
# 来源: analogdevicesinc/hdl + AMD UG835

set_param general.maxThreads 8

set TOP    [lindex $argv 0]
set PART   [lindex $argv 1]
set OUTDIR [lindex $argv 2]
set RPTDIR [lindex $argv 3]

# 读取
read_verilog [glob ../src/*.v]
read_xdc ../jesd204_phy_0_example_design.xdc

# 综合
puts "=== Synthesis ==="
synth_design -top $TOP -part $PART
write_checkpoint -force $RPTDIR/post_synth.dcp

# 实现
puts "=== Implementation ==="
opt_design
place_design
route_design
write_checkpoint -force $RPTDIR/post_route.dcp

# 报告
report_utilization  -file $RPTDIR/utilization_impl.rpt
report_timing_summary -file $RPTDIR/timing_impl.rpt

# Bitstream
puts "=== Bitstream ==="
write_bitstream -force $OUTDIR/$TOP.bit

puts "=== Build Complete ==="
puts "Bitstream: $OUTDIR/$TOP.bit"
