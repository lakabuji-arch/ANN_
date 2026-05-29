import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np

FIXED = 65536.0

def f2q(v):
    x = int(round(v * 65536))
    return x & 0xFFFFFFFF

def q2f(v):
    x = int(v)
    if x & 0x80000000: x -= 0x100000000
    return x / 65536.0

async def insert_and_wait(dut, distances, ids, k):
    dut.i_k.value = k
    for d, vid in zip(distances, ids):
        dut.i_push.value = 1
        dut.i_distance.value = f2q(d)
        dut.i_vector_id.value = vid
        await RisingEdge(dut.clk)
    dut.i_push.value = 0
    await ClockCycles(dut.clk, 30)

async def read_all(dut):
    results = []
    dut.i_read_en.value = 1
    for _ in range(300):
        await RisingEdge(dut.clk)
        if dut.o_read_valid.value:
            results.append((q2f(dut.o_distance.value), int(dut.o_vector_id.value)))
        else:
            break
    dut.i_read_en.value = 0
    return results

@cocotb.test()
async def test_topk_basic(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1; dut.i_push.value = 0; dut.i_read_en.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    np.random.seed(42)
    dists = np.random.uniform(0, 100, 100).astype(np.float64)
    expected = np.sort(dists)[:10]

    await insert_and_wait(dut, dists, range(100), 10)
    results = await read_all(dut)
    results.sort(key=lambda x: x[0])
    assert len(results) == 10
    for (rd,_), ed in zip(results, expected):
        assert abs(rd - ed) < 0.1, f"Mismatch: {rd:.4f} vs {ed:.4f}"

@cocotb.test()
async def test_topk_k1(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1; dut.i_push.value = 0; dut.i_read_en.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    await insert_and_wait(dut, [50.0, 30.0, 70.0, 10.0, 40.0], [0,1,2,3,4], 1)
    results = await read_all(dut)
    assert len(results) == 1
    assert abs(results[0][0] - 10.0) < 0.1
    assert results[0][1] == 3
