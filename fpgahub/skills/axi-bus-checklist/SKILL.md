---
name: axi-bus-checklist
description: AXI4/AXI4-Lite/AXI4-Stream protocol compliance checklist. Use when designing or debugging AXI interfaces.
---

# AXI Bus Compliance Checklist

> 来源: OpenHW CVA6 (CI验证要求) + JESD204B 工程 AXI 接口实践

## When to Use

Trigger when user mentions ANY of:
- "AXI" / "AXI4" / "AXI-Lite" / "AXI-Stream"
- "s_axi" / "m_axi" / "s_axis" / "m_axis"
- "总线" / "bus interface"

## AXI Protocol Rule

### The VALID/READY Handshake (Applies to ALL channels)

```
VALID must NOT wait for READY:
  Source sets VALID=1 → holds until READY=1 → data transferred

READY may wait for VALID:
  Destination may set READY=1 before or after VALID=1
```

## AXI4-Lite Write Channel Checklist

### AW (Write Address) Channel
- [ ] AWVALID raised when address is valid
- [ ] AWVALID held until AWREADY=1 (never de-assert before handshake)
- [ ] AWADDR is stable while AWVALID=1 and AWREADY=0
- [ ] AWADDR falls within slave's address space

### W (Write Data) Channel
- [ ] WVALID raised when data is valid
- [ ] WVALID held until WREADY=1
- [ ] WDATA is stable while WVALID=1 and WREADY=0
- [ ] WSTRB correctly reflects valid byte lanes (4'b1111 for full word)

### B (Write Response) Channel
- [ ] BVALID raised after write is complete (both AW and W handshook)
- [ ] BVALID held until BREADY=1
- [ ] BRESP = 2'b00 (OKAY) or 2'b10 (SLVERR) for unmapped addresses
- [ ] Master's BREADY is asserted (or properly back-pressured)

## AXI4-Lite Read Channel Checklist

### AR (Read Address) Channel
- [ ] ARVALID raised when address is valid
- [ ] ARVALID held until ARREADY=1
- [ ] ARADDR is stable during handshake

### R (Read Data) Channel
- [ ] RVALID raised AFTER data is ready (not before)
- [ ] RVALID held until RREADY=1
- [ ] RDATA is stable during handshake
- [ ] RRESP = 2'b00 (OKAY) or 2'b10 (SLVERR)

## AXI4-Stream Checklist

- [ ] TVALID raised when data is valid
- [ ] TVALID held until TREADY=1
- [ ] TREADY can be de-asserted for back-pressure
- [ ] TLAST asserted ONLY on the last beat of a packet
- [ ] TLAST pulse lasts exactly one beat
- [ ] TKEEP correctly indicates valid bytes on TLAST beat (may not be all-1s)
- [ ] TDATA, TKEEP, TLAST all stable while TVALID=1 and TREADY=0

## Common Bugs (from CVA6 and JESD204B experience)

### Bug 1: Driving input port with assign
```verilog
// ❌ WRONG
input s_axi_awready;
assign s_axi_awready = some_condition;

// ✅ CORRECT
output s_axi_awready;
assign s_axi_awready = some_condition;
```

### Bug 2: VALID de-asserts before READY
```verilog
// ❌ WRONG
always @(posedge clk) begin
  if (start)       awvalid <= 1;
  else             awvalid <= 0;  // De-asserts before handshake!
end

// ✅ CORRECT
always @(posedge clk) begin
  if (start)                  awvalid <= 1;
  else if (awvalid && awready) awvalid <= 0;  // Only de-assert after handshake
end
```

### Bug 3: RVALID race condition
```verilog
// ❌ WRONG: RVALID raised before data is ready
always @(posedge clk) begin
  rvalid <= arvalid && arready;  // Too early! Data not ready yet
end

// ✅ CORRECT: RVALID raised after data is ready
always @(posedge clk) begin
  if (arvalid && arready)   rdata <= read_data_from_memory;
  rvalid <= arvalid && arready;  // rdata registered same cycle
end
```

### Bug 4: Not checking BRESP/RRESP
```verilog
// ❌ WRONG: Ignoring error response
always @(posedge clk) begin
  if (bvalid && bready) begin
    write_done <= 1;  // No check of BRESP!
  end
end

// ✅ CORRECT
always @(posedge clk) begin
  if (bvalid && bready) begin
    if (bresp == 2'b00)   write_done <= 1;
    else                   write_error <= 1;
  end
end
```

### Bug 5: Reset polarity mismatch
```verilog
// ❌ WRONG: XPM native FIFO uses high-active rst
xpm_fifo_async inst (.rst(~aresetn));  // inverted low-active!

// ❌ WRONG: XPM AXI FIFO uses low-active aresetn
xpm_fifo_axis inst (.s_aresetn(rst));  // high-active connected to low-active!

// ✅ CORRECT: Know each primitive's reset polarity
// Native FIFOs: high-active rst
// AXI FIFOs: low-active _aresetn
```
