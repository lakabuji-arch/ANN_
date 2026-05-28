import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np
import struct

FIXED_SCALE = 65536.0


def float_to_fixed(arr):
    clipped = np.clip(arr * FIXED_SCALE, -2147483648, 2147483647)
    return clipped.astype(np.int64)


def fixed_to_float(val):
    if isinstance(val, int):
        v = val
    else:
        v = int(val)
    if v & 0x80000000:
        v -= 0x100000000
    return float(v) / FIXED_SCALE


def pack_16_ints(arr):
    result = 0
    for i, v in enumerate(arr):
        result |= (int(v) & 0xFFFFFFFF) << (i * 32)
    return result


async def run_distance_test(dut, a, b, dim, metric, expected):
    a_fixed = float_to_fixed(a)
    b_fixed = float_to_fixed(b)
    num_chunks = (dim + 15) // 16

    dut.i_dim.value = dim
    dut.i_metric.value = metric
    dut.i_start.value = 1
    dut.i_vec_a_tdata.value = pack_16_ints(a_fixed[0:16])
    dut.i_vec_a_tvalid.value = 1
    dut.i_vec_b_tdata.value = pack_16_ints(b_fixed[0:16])
    dut.i_vec_b_tvalid.value = 1

    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    for chunk in range(1, num_chunks):
        start = chunk * 16
        end = start + 16
        chunk_a = np.zeros(16, dtype=np.int64)
        chunk_b = np.zeros(16, dtype=np.int64)
        count = min(16, dim - start)
        chunk_a[:count] = a_fixed[start:start + count]
        chunk_b[:count] = b_fixed[start:start + count]
        dut.i_vec_a_tdata.value = pack_16_ints(chunk_a)
        dut.i_vec_b_tdata.value = pack_16_ints(chunk_b)
        await RisingEdge(dut.clk)

    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0

    for _ in range(200):
        await RisingEdge(dut.clk)
        if dut.o_valid.value:
            result = fixed_to_float(dut.o_distance.value)
            return result
    return None


@cocotb.test()
async def test_l2_16dim(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0
    dut.i_start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    a = np.array([1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], dtype=np.float64)
    b = np.array([16.0, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1], dtype=np.float64)
    expected = float(np.sum((a - b) ** 2))

    result = await run_distance_test(dut, a.astype(np.float32), b.astype(np.float32), 16, 0, expected)
    assert result is not None, "Timeout waiting for result"
    cocotb.log.info(f"L2(16d): got={result:.2f}, expected={expected:.2f}")
    assert abs(result - expected) < 5.0, f"Mismatch: {result} vs {expected}"


@cocotb.test()
async def test_l2_256dim(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0
    dut.i_start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    np.random.seed(42)
    a = np.random.randn(256).astype(np.float32)
    b = np.random.randn(256).astype(np.float32)
    expected = float(np.sum((a.astype(np.float64) - b.astype(np.float64)) ** 2))

    result = await run_distance_test(dut, a, b, 256, 0, expected)
    assert result is not None, "Timeout waiting for result"
    cocotb.log.info(f"L2(256d): got={result:.2f}, expected={expected:.2f}")
    assert abs(result - expected) < 200.0, f"Mismatch: {result} vs {expected}"


@cocotb.test()
async def test_ip_16dim(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0
    dut.i_start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    a = np.array([1.0, 2.0, 3.0, 4.0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], dtype=np.float32)
    b = np.array([4.0, 3.0, 2.0, 1.0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], dtype=np.float32)
    expected = float(np.dot(a.astype(np.float64), b.astype(np.float64)))

    result = await run_distance_test(dut, a, b, 16, 2, expected)
    assert result is not None, "Timeout waiting for result"
    cocotb.log.info(f"IP(16d): got={result:.2f}, expected={expected:.2f}")
    assert abs(result - expected) < 5.0, f"Mismatch: {result} vs {expected}"


@cocotb.test()
async def test_l2_dim1(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0
    dut.i_start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    a = np.array([5.0], dtype=np.float32)
    b = np.array([3.0], dtype=np.float32)
    expected = float((5.0 - 3.0) ** 2)

    result = await run_distance_test(dut, a, b, 1, 0, expected)
    assert result is not None, "Timeout waiting for result"
    cocotb.log.info(f"L2(1d): got={result:.2f}, expected={expected:.2f}")
    assert abs(result - expected) < 2.0, f"Mismatch: {result} vs {expected}"


@cocotb.test()
async def test_l2_dim1536(dut):
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())
    dut.rst.value = 1
    dut.i_vec_a_tvalid.value = 0
    dut.i_vec_b_tvalid.value = 0
    dut.i_start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    np.random.seed(99)
    a = np.random.randn(1536).astype(np.float32)
    b = np.random.randn(1536).astype(np.float32)
    expected = float(np.sum((a.astype(np.float64) - b.astype(np.float64)) ** 2))

    result = await run_distance_test(dut, a, b, 1536, 0, expected)
    assert result is not None, "Timeout waiting for result"
    cocotb.log.info(f"L2(1536d): got={result:.2f}, expected={expected:.2f}")
    assert abs(result - expected) < 1000.0, f"Mismatch: {result} vs {expected}"
