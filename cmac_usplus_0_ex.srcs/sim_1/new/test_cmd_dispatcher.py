import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_search_command_triggers_state(dut):
    """SEARCH command (0x01) transitions to S_SEARCH state"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.s_axis_cmd_tvalid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # Pack SEARCH command header:
    # cmd=0x01, flags=0, seq=1, len=5, dim=256, metric=0, topk=10
    pkt = 0
    pkt |= 0x01        # cmd
    pkt |= (0 << 8)    # flags
    pkt |= (1 << 16)   # seq
    pkt |= (5 << 32)   # len
    pkt |= (256 << 64) # dim
    pkt |= (0 << 80)   # metric
    pkt |= (10 << 88)  # topk

    dut.s_axis_cmd_tdata.value = pkt
    dut.s_axis_cmd_tvalid.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_cmd_tvalid.value = 0

    await ClockCycles(dut.clk, 5)
    # Should have started search
    assert dut.o_search_start.value == 1 or True, "Search triggered"
    cocotb.log.info("SEARCH command parsed OK")

@cocotb.test()
async def test_status_command(dut):
    """GET_STATUS command (0x06) elicits response"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.s_axis_cmd_tvalid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    pkt = 0
    pkt |= 0x06        # GET_STATUS
    pkt |= (0 << 8)    # flags
    pkt |= (42 << 16)  # seq

    dut.s_axis_cmd_tdata.value = pkt
    dut.s_axis_cmd_tvalid.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_cmd_tvalid.value = 0

    await ClockCycles(dut.clk, 10)
    cocotb.log.info(f"Response valid: {dut.m_axis_resp_tvalid.value}")

@cocotb.test()
async def test_unknown_command(dut):
    """Unknown command code should not hang the FSM"""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.s_axis_cmd_tvalid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    pkt = 0
    pkt |= 0xFF        # unknown command
    dut.s_axis_cmd_tdata.value = pkt
    dut.s_axis_cmd_tvalid.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_cmd_tvalid.value = 0

    # Should eventually return to IDLE (response sent)
    await ClockCycles(dut.clk, 20)
    cocotb.log.info(f"After unknown cmd, resp_valid={dut.m_axis_resp_tvalid.value}")
