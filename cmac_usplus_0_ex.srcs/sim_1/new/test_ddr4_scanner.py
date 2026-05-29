import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np

@cocotb.test()
async def test_scanner_state_machine(dut):
    """Verify scanner scans vectors with AXI handshake"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_start.value = 0
    dut.m_axi_arready.value = 1
    dut.m_axi_rvalid.value = 0
    dut.m_axi_rdata.value = 0
    for i in range(8):
        dut.i_cluster_id[i].value = 0
        dut.i_cluster_size[i].value = 0
        dut.i_cluster_base[i].value = 0
    dut.i_cluster_count.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # 1 cluster with 1 vector of 16-dim (1 beat = 64B)
    dut.i_dim.value = 16
    dut.i_metric.value = 0
    dut.i_topk.value = 10
    dut.i_cluster_count.value = 1
    dut.i_cluster_id[0].value = 3
    dut.i_cluster_size[0].value = 1    # just 1 vector
    dut.i_cluster_base[0].value = 0x00001000

    dut.i_start.value = 1
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    # Simulate AXI responses — drive rvalid+rdata when scanner requests
    for _ in range(200):
        await RisingEdge(dut.clk)
        # When scanner asserts arvalid, simulate a read response
        if dut.m_axi_arvalid.value:
            # Acknowledge the read
            await RisingEdge(dut.clk)
            # Return vector data (any data, just to advance the state machine)
            dut.m_axi_rvalid.value = 1
            dut.m_axi_rdata.value = 0x12345678_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000001
            await RisingEdge(dut.clk)
            dut.m_axi_rvalid.value = 0
        if dut.o_done.value:
            break

    cocotb.log.info(f"Vectors scanned: {int(dut.o_vectors_scanned.value)}")
    assert int(dut.o_vectors_scanned.value) > 0, "No vectors scanned"

@cocotb.test()
async def test_scanner_empty_clusters(dut):
    """Edge case: all clusters empty"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_start.value = 0
    dut.m_axi_arready.value = 1
    dut.m_axi_rvalid.value = 0
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
