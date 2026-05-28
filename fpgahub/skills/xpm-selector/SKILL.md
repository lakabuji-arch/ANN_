---
name: xpm-selector
description: Use when choosing Xilinx XPM primitives for clock domain crossing (CDC) or FIFO scenarios. Helps select the correct xpm_cdc_* or xpm_fifo_* based on signal type, clock relationship, and data width.
---

# XPM Primitives Selector

> 来源: 基于 ADI HDL 和 JESD204B 工程中的实际 XPM 使用模式

## When to Use

Trigger when user mentions ANY of:
- "跨时钟域" / "CDC" / "跨域" / "clock domain crossing"
- "FIFO" (异步场景) / "同步FIFO"
- "异步复位" / "复位同步"
- "xpm_cdc" / "xpm_fifo"

## Decision Tree

Ask the user ONE question at a time:

### Step 1: Signal Type

"What kind of signal are you transferring across clock domains?"

- **A) Single-bit control signal** (enable, reset_done flag)
  → `xpm_cdc_single`
  - DEST_SYNC_FF: 4 (default), 2 for low-latency paths, 5+ for safety-critical

- **B) Multiple independent single-bit signals** (e.g., 8 interrupt flags)
  → `xpm_cdc_array_single`
  - ⚠️ CRITICAL: ONLY for independent signals. NOT for encoded data buses.
  - Different bits may arrive in different clock cycles!

- **C) Multi-bit data bus** (e.g., 16-bit ADC sample)
  → Go to Step 2

- **D) Multi-bit counter/pointer** (e.g., FIFO read/write pointers)
  → `xpm_cdc_gray`
  - Input/output are BINARY (auto-encode/decode internally)
  - Port names: `src_in_bin`, `dest_out_bin` (NOT `src_in`/`dest_out`!)

- **E) Single-cycle pulse**
  → `xpm_cdc_pulse`
  - ⚠️ CRITICAL: Min pulse interval ≥ 2 × T_dest_clk
  - Fast-to-slow: must guarantee pulse spacing

- **F) Asynchronous reset signal**
  → `xpm_cdc_sync_rst`
  - Input: high-active async reset
  - Output: high-active sync-deasserted reset
  - If external reset is low-active: invert before input, invert after output

### Step 2: Data Bus - Latency vs Throughput

(Only reached if Step 1 answer was C)

"How much latency can you tolerate? What throughput do you need?"

- **A) Low latency (<10 cycles), occasional transfers**
  → `xpm_cdc_handshake`
  - Full handshake: src_send → dest_req → dest_ack → src_rcv
  - src_send MUST be a pulse (single-cycle)
  - Cannot send next data until src_rcv returns
  - ~6-8 cycles per transfer

- **B) High throughput, continuous streaming**
  → `xpm_fifo_async`
  - Internally uses xpm_cdc_gray for pointer sync
  - CDC_SYNC_STAGES: 4 (default)
  - Auto-handles back-pressure via full/empty

### Step 3: FIFO Mode Selection

(Only reached if Step 2 answer was B)

"Single clock or dual clock? Native or AXI interface?"

- **Single clock** → `xpm_fifo_sync`
- **Dual async clock** → `xpm_fifo_async`
- **AXI4-Stream interface** → `xpm_fifo_axis`
- **AXI4-Lite interface** → `xpm_fifo_axil`

## CRC (Common Rules and Constraints)

### For ALL XPM primitives:
- [ ] `SIM_ASSERT_CHK = 0` in production code
- [ ] Clock ports connected to correct domain clocks
- [ ] Reset polarity matches: native FIFOs = high-active, AXI FIFOs = low-active (`_aresetn`)
- [ ] Unused output ports left unconnected (not tied to ground)

### For FIFO depth calculation:
```
MinDepth = BurstBacklog + CDC_Inflight
BurstBacklog = BurstLen × (1 - T_wr_word / T_rd_clk)
CDC_Inflight  = ceil(CDC_Delay × T_rd_clk / T_wr_word)
SafeDepth     = ceil_pow2(MinDepth + 25% margin)
```

### For fwft (First Word Fall-Through) mode:
- [ ] `FIFO_READ_LATENCY = 0` (MANDATORY for fwft)
- [ ] `data_valid` output = `!empty`
- [ ] First written word appears on `dout` without `rd_en`

## Anti-Patterns (NEVER DO THIS)

```verilog
// ❌ Using array_single for encoded data
xpm_cdc_array_single #(.WIDTH(8))  // WRONG for data bus!

// ❌ src_send as level signal
always @(*) src_send = valid;      // WRONG - must be pulse!

// ❌ Forgetting hold equation with multicycle
set_multicycle_path -setup 4 ...  // OK
// Missing: set_multicycle_path -hold 3 ...

// ❌ xpm_cdc_gray with wrong port names
.src_in(ptr)        // WRONG - must be .src_in_bin(ptr)
.dest_out(ptr_out)  // WRONG - must be .dest_out_bin(ptr_out)
```
