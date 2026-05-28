---
name: fpga-debug
description: Structured FPGA hardware debugging methodology. Data-first, hypothesis-second. Never guess. Use when encountering any bug, test failure, or unexpected behavior.
---

# FPGA Hardware Debugging

> 来源: impakt73/ai-rust-hw-dev (AGENTS.md 调试哲学) + Superpowers systematic-debugging Skill

## The Iron Law

```
NO FIXES WITHOUT OBSERVED DATA FIRST.
```

If you haven't run simulation and looked at actual signal values, you cannot propose a fix.

## When to Use

- Simulation FAIL
- Synthesis ERROR or CRITICAL WARNING
- Timing violation
- On-board behavior different from simulation
- ILA shows unexpected values

## Process (4 Phases)

### Phase 1: Narrow the Scope

**Goal: Find which module is broken.**

```
Step 1: Binary isolation
  Comment out / disconnect HALF the design
  Does the error still happen?
  YES → bug in the remaining half
  NO  → bug in the commented half
  Repeat until you find the single module.

Step 2: Boundary check
  Add $display() at module I/O boundaries:
  
  always @(posedge clk) begin
    if (valid_in)
      $display("[%0t] %m: data_in=0x%h", $time, data_in);
  end
```

### Phase 2: ILA Probe Strategy (for on-board debugging)

Source: impakt73/ai-rust-hw-dev — hardware debugging must be data-driven

**Minimum 5 signals to probe:**
1. Clock (always)
2. Reset (always)
3. Valid/Enable signal
4. Data bus (at least key bits)
5. State machine state

**Trigger conditions (in priority order):**
1. Error flag rising edge
2. State machine entering unexpected state
3. Valid=1 && data has specific value

**Anti-patterns for ILA:**
- ❌ Triggering on clock edge (triggers every cycle)
- ❌ Probing every bit of a 64-bit bus (wastes ILA space)
- ❌ No trigger condition (fills ILA buffer with idle data)

### Phase 3: Build Minimal Repro

**Goal: Simplest test that still fails.**

```
1. Create a standalone testbench for the broken module
2. Feed it the exact inputs that cause the bug
3. Remove all unrelated modules from the test
4. Can you reproduce the bug with just this module?
   YES → Good. Fix is isolated.
   NO  → Bug is in module interaction, look at interface timing.
```

### Phase 4: Fix and Verify

```
1. Change ONLY ONE thing at a time
2. Re-run the EXACT same test
3. Confirm:
   □ Original bug is fixed
   □ No new failures introduced
   □ All previously passing tests still pass
4. If fix didn't work: REVERT and try something else
```

## Specific Debug Patterns

### Pattern: State Machine Stuck

```verilog
// Debug technique: expose state
localparam IDLE=0, WORK=1, DONE=2;
reg [1:0] state;

// Add to ILA probes: state, all transition conditions
// Check: Is a transition condition never becoming true?
```

### Pattern: Data Mismatch

```
Check in order:
1. Is the expected value correct? (print it)
2. Is the received data latched at the right time? (check valid signal)
3. Is there a bit-order problem? (MSB vs LSB)
4. Is there a CDC issue? (data changing during sampling)
```

### Pattern: CDC Bug

```
Symptoms:
- Works 99% of time, fails randomly
- Fails more often at higher temperature
- Different failure rate on different boards

Debug:
- Check: Does EVERY cross-domain signal go through a sync chain?
- $display the input and output of each sync_block
- Check timing report: Are CDC paths properly false_pathed?
```

## Tools Reference

| Tool | Use | Source |
|------|-----|--------|
| `$display()` | Print signal values in simulation | Built-in Verilog |
| Vivado ILA | On-chip logic analyzer | Xilinx |
| vcd-mcp | AI analyzes VCD waveform files | impakt73/ai-rust-hw-dev |
| `report_timing` | Analyze critical path | Vivado Tcl |
| `write_checkpoint` | Save/restore implementation state | Vivado Tcl |
