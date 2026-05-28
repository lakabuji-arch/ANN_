---
name: vivado-tcl-scripting
description: Use when generating Vivado Tcl scripts for project creation, synthesis, implementation, or bitstream generation. Always includes maxThreads acceleration.
---

# Vivado Tcl Automation

> 来源: analogdevicesinc/hdl (Makefile+Tcl自动化) + AMD UG835 (官方Tcl参考)

## When to Use

Trigger when user mentions ANY of:
- "建 Vivado 工程" / "create project"
- "跑综合" / "跑实现" / "synthesis" / "implementation"
- "生成 bitstream"
- "tcl" / "Vivado 脚本"

## Critical: Always Add Multi-Threading

**EVERY Tcl script that runs synthesis or implementation MUST include:**

```tcl
# Vivado 多线程加速 (AMD UG835 推荐)
set_param general.maxThreads 8
```

Place this BEFORE any `synth_design` or `place_design` or `route_design` command.

## Script Templates

### Non-Project Mode (Recommended for CI/automation)

```tcl
# run_build.tcl — Complete build flow
set_param general.maxThreads 8

# Read sources
read_verilog [glob ./src/*.v]
read_verilog [glob ./src/**/*.v]
read_xdc ./constraints/timing.xdc

# Synthesis
synth_design -top <top_module> -part <part_number>
write_checkpoint -force post_synth.dcp
report_utilization  -file reports/utilization_synth.rpt
report_timing_summary -file reports/timing_synth.rpt

# Implementation
opt_design
place_design
route_design
write_checkpoint -force post_route.dcp
report_utilization  -file reports/utilization_impl.rpt
report_timing_summary -file reports/timing_impl.rpt

# Bitstream
write_bitstream -force ./output/<top_module>.bit
```

### Project Mode (for GUI debugging)

```tcl
# create_project.tcl — One-time project setup
set_param general.maxThreads 8

create_project <name> ./<name>_proj -part <part_number>
add_files -norecurse [glob ./src/*.v]
add_files -fileset constrs_1 [glob ./constraints/*.xdc]
set_property top <top_module> [current_fileset]
update_compile_order -fileset sources_1

# Run synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

### Quick Commands

```tcl
# Report timing
report_timing -max_paths 10 -file timing.rpt
report_timing_summary -file timing_summary.rpt

# Report utilization
report_utilization -file utilization.rpt

# Report clock interaction (CDC check)
report_clock_interaction -file clock_interaction.rpt

# Check for CRITICAL WARNINGs
report_critical_warning -file critical_warnings.txt
```

## Checklist

- [ ] `set_param general.maxThreads 8` at top of script
- [ ] Part number matches target device
- [ ] All .v/.sv files added
- [ ] All .xdc files added
- [ ] Top module name correct
- [ ] `synth_design` before `opt_design` before `place_design` before `route_design`
- [ ] All reports saved to files (not just printed to console)
- [ ] Build output goes to `./output/` or specified directory
