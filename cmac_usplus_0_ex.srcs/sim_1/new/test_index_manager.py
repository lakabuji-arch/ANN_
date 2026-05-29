import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_zone_switch(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_reindex_switch.value = 0
    dut.i_insert_req.value = 0
    dut.i_cluster_wr_en.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # Initial: zone A, base = 0x0000_0000
    assert dut.o_active_zone.value == 0
    assert dut.o_active_base.value == 0x0000_0000

    # Switch to B
    dut.i_reindex_switch.value = 1
    await RisingEdge(dut.clk)
    dut.i_reindex_switch.value = 0
    await ClockCycles(dut.clk, 3)

    assert dut.o_active_zone.value == 1
    assert dut.o_active_base.value == 0x40000000

    # Switch back to A
    dut.i_reindex_switch.value = 1
    await RisingEdge(dut.clk)
    dut.i_reindex_switch.value = 0
    await ClockCycles(dut.clk, 3)

    assert dut.o_active_zone.value == 0
    assert dut.o_active_base.value == 0x0000_0000

@cocotb.test()
async def test_insert_increments_pending(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_reindex_switch.value = 0
    dut.i_insert_req.value = 0
    dut.i_cluster_wr_en.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # Insert 5 vectors
    for _ in range(5):
        dut.i_insert_req.value = 1
        await RisingEdge(dut.clk)
    dut.i_insert_req.value = 0
    await ClockCycles(dut.clk, 5)

    # pending_count should be 5 (each write is 64 bytes, so tail incremented by 64*5)
    cocotb.log.info(f"pending_count: {int(dut.o_pending_count.value)}")
    assert int(dut.o_pending_count.value) == 5

    # After zone switch, pending should reset
    dut.i_reindex_switch.value = 1
    await RisingEdge(dut.clk)
    dut.i_reindex_switch.value = 0
    await ClockCycles(dut.clk, 3)

    assert int(dut.o_pending_count.value) == 0

@cocotb.test()
async def test_cluster_table_rw(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_reindex_switch.value = 0
    dut.i_insert_req.value = 0
    dut.i_cluster_wr_en.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # Zone A active, write cluster 5 to standby zone (B)
    dut.i_cluster_wr_en.value = 1
    dut.i_cluster_wr_idx.value = 5
    dut.i_cluster_wr_base.value = 0x1000
    dut.i_cluster_wr_size.value = 200
    await RisingEdge(dut.clk)
    dut.i_cluster_wr_en.value = 0
    await ClockCycles(dut.clk, 3)

    # Read cluster 5 from active zone (A) — still defaults
    dut.i_cluster_rd_idx.value = 5
    await RisingEdge(dut.clk)
    # Should read from A (default 0 since we wrote to B)
    # Now switch
    dut.i_reindex_switch.value = 1
    await RisingEdge(dut.clk)
    dut.i_reindex_switch.value = 0
    await ClockCycles(dut.clk, 3)

    # Now B is active, cluster 5 should have our data
    dut.i_cluster_rd_idx.value = 5
    await RisingEdge(dut.clk)
    # Should now be 0x1000/200
    cocotb.log.info(f"After switch: base={dut.o_cluster_rd_base.value}, size={dut.o_cluster_rd_size.value}")
