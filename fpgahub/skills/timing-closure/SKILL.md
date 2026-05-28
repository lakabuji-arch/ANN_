---
name: timing-closure
description: Use when analyzing Vivado timing reports and fixing setup/hold violations. Structured diagnosis first, then fix recommendations.
---

# Timing Closure

> 来源: OpenHW CVA6 (工业级时序要求) + impakt73/ai-rust-hw-dev (Fmax优先设计)

## When to Use

Trigger when user mentions ANY of:
- "时序" / "timing" / "时序违例"
- "WNS" / "WHS" / "TNS"
- "setup violation" / "hold violation"
- "静态时序" / "clock skew"

## Diagnosis Flow

### Phase 1: Understand the Scope

1. **How many failing endpoints?**
   - <10: Read each path individually
   - 10-100: Look for patterns (same clock? same module?)
   - >100: Check clock constraints first — likely a missing `set_clock_groups`

2. **What's the WNS (Worst Negative Slack) value?**
   - WNS > -0.100 ns: Minor. Try `opt_design` first.
   - WNS -0.100 ~ -0.500 ns: Moderate. Needs pipeline or floorplanning.
   - WNS < -0.500 ns: Serious. Architecture change needed.
   - WNS < -2.000 ns: Critical. Design likely has wrong clock constraint.

3. **Logic vs Routing percentage?**
   ```
   report_timing -path_type summary
   ```
   - Logic Delay > 60%: Add pipeline registers
   - Routing Delay > 60%: Floorplanning issue, check placement
   - Clock Skew > 500ps: Check clock tree constraints

### Phase 2: Read One Critical Path

```tcl
report_timing -from [get_clocks <launch>] -to [get_clocks <capture>] \
              -max_paths 5 -file critical_paths.rpt
```

For each path, identify:
- **Launch clock** and **Capture clock**
- Number of logic levels (LUT depth)
- Any large fanout nets (>100 loads)
- Any unexpected CDC paths (should have been set_false_path)

### Phase 3: Classify and Fix

| Problem Type | Fix Strategy |
|-------------|-------------|
| Too many logic levels (>15) | Add pipeline stage |
| Large fanout | Replicate register / use MAX_FANOUT constraint |
| Clock skew | Check BUFG placement / clock root |
| CDC path not declared | Add `set_false_path` or `set_clock_groups -asynchronous` |
| Tight IO timing | Adjust `set_input_delay` / `set_output_delay` values |
| Hold violation | Add delay (BUFG_PS) or fix min delay path |

### Phase 4: Fix Strategies (ordered by effectiveness)

1. **Add pipeline registers** ⭐ Most effective
   ```verilog
   // Before: long combinational path
   assign result = a * b + c * d + e * f;
   
   // After: pipelined
   reg [31:0] stage1, stage2;
   always @(posedge clk) begin
       stage1 <= a * b + c * d;
       stage2 <= stage1 + e * f;
   end
   assign result = stage2;
   ```

2. **set_multicycle_path** (ONLY if clocks are from same PLL/MMCM!)
   ```tcl
   set_multicycle_path -setup N -from <src> -to <dst>
   set_multicycle_path -hold  N-1 -from <src> -to <dst>
   ```

3. **Reduce fanout**
   ```tcl
   set_property MAX_FANOUT 50 [get_nets <high_fanout_net>]
   ```

4. **Floorplanning**
   ```tcl
   set_property PBLOCK <pblock_name> [get_cells <critical_module>]
   ```

5. **Physical optimization**
   ```tcl
   opt_design -retarget
   place_design -directive ExtraTimingOpt
   phys_opt_design -directive AggressiveExplore
   ```

## Anti-Patterns

```tcl
# ❌ NEVER use set_false_path to hide real violations
set_false_path -from [get_cells critical_reg] -to [get_cells dest_reg]

# ❌ NEVER use set_multicycle_path on asynchronous clocks
set_multicycle_path -setup 4 -from [get_clocks clk_a] -to [get_clocks clk_b]

# ❌ NEVER skip hold fixing — hold violations cause silicon failure
# WHS must be ≥ 0 before generating bitstream
```
