# Vivado Non-Project Mode 综合脚本
# 用法: vivado -mode batch -source run_synth.tcl -tclargs <top> <part> <rpt_dir>
# 来源: analogdevicesinc/hdl + AMD UG835

set_param general.maxThreads 8

# 参数
set TOP    [lindex $argv 0]
set PART   [lindex $argv 1]
set RPTDIR [lindex $argv 2]

# 读取源文件
read_verilog [glob ../src/*.v]
read_xdc ../jesd204_phy_0_example_design.xdc

# 综合
puts "=== Synthesis: $TOP ($PART) ==="
synth_design -top $TOP -part $PART

# 报告
write_checkpoint -force $RPTDIR/post_synth.dcp
report_utilization  -file $RPTDIR/utilization_synth.rpt
report_timing_summary -file $RPTDIR/timing_synth.rpt

puts "=== Synthesis Complete ==="
