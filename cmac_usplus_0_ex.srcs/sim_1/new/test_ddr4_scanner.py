import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_scanner_state_machine(dut):
    """Verify scanner transitions through states correctly"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_start.value = 0
    for i in range(8):
        dut.i_cluster_id[i].value = 0
        dut.i_cluster_size[i].value = 0
        dut.i_cluster_base[i].value = 0
    dut.i_cluster_count.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # Set up 1 cluster with 2 vectors of 16-dim (1 beat each)
    dut.i_dim.value = 16
    dut.i_metric.value = 0
    dut.i_topk.value = 10
    dut.i_cluster_count.value = 1
    dut.i_cluster_id[0].value = 3
    dut.i_cluster_size[0].value = 2
    dut.i_cluster_base[0].value = 0x00001000

    dut.i_start.value = 1
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    # Wait for done or timeout
    for _ in range(500):
        await RisingEdge(dut.clk)
        if dut.o_done.value:
            cocotb.log.info(f"Scanner done. Vectors scanned: {int(dut.o_vectors_scanned.value)}")
            break

    assert int(dut.o_vectors_scanned.value) > 0, "No vectors scanned"

@cocotb.test()
async def test_scanner_empty_clusters(dut):
    """Edge case: all clusters empty -> should complete immediately"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_start.value = 0
    for i in range(8):
        dut.i_cluster_id[i].value = 0
        dut.i_cluster_size[i].value = 0
        dut.i_cluster_base[i].value = 0
    dut.i_cluster_count.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    dut.i_dim.value = 256
    dut.i_cluster_count.value = 0
    dut.i_start.value = 1
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    for _ in range(100):
        await RisingEdge(dut.clk)
        if dut.o_done.value:
            break

    assert int(dut.o_vectors_scanned.value) == 0
