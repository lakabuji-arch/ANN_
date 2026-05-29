import cocotb
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
import numpy as np

FIXED = 65536.0


def f2q(arr):
    """Convert float array to Q16.16 fixed-point integers."""
    c = np.clip(arr * 65536, -2147483648, 2147483647)
    return c.astype(np.int64)


def q2f(v):
    """Convert Q16.16 fixed-point value back to float."""
    x = int(v)
    if x & 0x80000000:
        x -= 0x100000000
    return x / 65536.0


def pack16(arr):
    """Pack 16 x 32-bit values into a 512-bit integer (little-endian)."""
    r = 0
    for i, v in enumerate(arr):
        r |= (int(v) & 0xFFFFFFFF) << (i * 32)
    return r


def unpack16(packed):
    """Unpack a 512-bit integer into 16 x 32-bit values."""
    vals = []
    for i in range(16):
        v = (packed >> (i * 32)) & 0xFFFFFFFF
        if v & 0x80000000:
            v -= 0x100000000
        vals.append(v)
    return np.array(vals, dtype=np.int64)


async def drive_reset(dut, cycles=5):
    """Drive reset for a given number of clock cycles."""
    dut.rst.value = 1
    await ClockCycles(dut.clk, cycles)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def feed_query_chunks(dut, query_chunks, num_chunks):
    """Feed query vector chunks into the module."""
    for ci in range(num_chunks):
        dut.i_query_vec_a.value = query_chunks[ci]
        dut.i_query_valid.value = 1
        await RisingEdge(dut.clk)
        while dut.o_query_ready.value == 0:
            await RisingEdge(dut.clk)
    dut.i_query_valid.value = 0
    await RisingEdge(dut.clk)


async def simulate_dcu_response(dut, num_centroids, chunk_latency, dcu_latency):
    """
    Simulate DCU behavior:
    - Each centroid takes chunk_latency cycles of data streaming
    - After the last chunk, dcu_latency cycles later the result appears on i_dcu_distance
    """
    # We run this in parallel with the main test flow
    # For each centroid, after chunks are streamed, generate a result
    pass


async def inject_dcu_results(dut, centroid_distances, num_chunks, dcu_pipeline_depth=4):
    """
    Inject centroid data through the DCU interface and capture results.
    For each centroid:
      1. Provide centroid chunk data on i_dcu_vec_b (driven from URAM)
      2. Consume query data from o_dcu_vec_a
      3. After all chunks, generate i_dcu_valid with the computed distance
    """
    n_centroids = len(centroid_distances)

    for ci in range(n_centroids):
        # Stream chunks for this centroid
        for ch in range(num_chunks):
            # Wait for module to assert vec_a_valid and vec_b valid
            await RisingEdge(dut.clk)

            # Provide a dummy centroid chunk on port B (simulating URAM read)
            centroid_chunk = np.random.randint(
                -2147483648, 2147483647, size=16, dtype=np.int64
            )
            dut.i_centroid_rdata.value = pack16(centroid_chunk)
            dut.i_dcu_vec_a_ready.value = 1

        # After all chunks streamed, inject DCU result
        # The DCU pipeline has some latency; inject after pipeline empties
        await ClockCycles(dut.clk, dcu_pipeline_depth)
        dut.i_dcu_distance.value = centroid_distances[ci]
        dut.i_dcu_valid.value = 1
        await RisingEdge(dut.clk)
        dut.i_dcu_valid.value = 0


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@cocotb.test()
async def test_coarse_search_reset(dut):
    """Verify the module resets to IDLE state and outputs are inert."""
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    # After reset, module should be IDLE
    assert dut.o_done.value == 0, "o_done should be 0 after reset"
    assert dut.o_query_ready.value == 0, "o_query_ready should be 0 after reset"
    assert dut.o_centroid_re.value == 0, "o_centroid_re should be 0 after reset"
    assert dut.o_dcu_start.value == 0, "o_dcu_start should be 0 after reset"
    assert dut.o_cluster_count.value == 0, "o_cluster_count should be 0 after reset"
    cocotb.log.info("Reset test PASS")


@cocotb.test()
async def test_coarse_search_start_transition(dut):
    """
    Verify that asserting i_start causes transition from IDLE to LOAD.
    Full test of state machine requires DCU integration (Task 11).
    """
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    DIM = 256
    P = 3

    dut.i_dim.value = DIM
    dut.i_metric.value = 0  # L2
    dut.i_probes.value = P
    dut.i_query_valid.value = 0

    # Assert start for one cycle
    dut.i_start.value = 1
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    # Module should now be in LOAD state and accept query data
    assert dut.o_query_ready.value == 1, (
        f"o_query_ready should be 1 in LOAD state, got {dut.o_query_ready.value}"
    )

    # Feed one query chunk to advance the state
    dummy_chunk = 0
    dut.i_query_vec_a.value = dummy_chunk
    dut.i_query_valid.value = 1
    await RisingEdge(dut.clk)
    dut.i_query_valid.value = 0

    cocotb.log.info("State transition test PASS: IDLE -> LOAD works")


@cocotb.test()
async def test_coarse_search_16_centroids(dut):
    """
    Test with N=16 centroids, P=3, DIM=256.
    Inject known distance values and verify top-3 selection.

    This tests the top-P sorting logic in isolation.
    The DCU is bypassed by directly providing distances on i_dcu_distance.
    """
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    N = 16
    DIM = 256
    P = 3
    num_chunks = (DIM + 15) // 16  # 16

    # Inject distances directly (simulating DCU results)
    # Centroids 0..15 with distances:
    distances = [500, 200, 100, 50, 300, 400, 150, 250,
                 600, 350, 80, 90, 120, 110, 130, 140]

    # Expected top-3 (smallest): idx 3 (50), idx 10 (80), idx 11 (90)
    expected_top3 = [3, 10, 11]
    expected_dists = [50, 80, 90]

    dut.i_dim.value = DIM
    dut.i_metric.value = 0
    dut.i_probes.value = P
    dut.i_start.value = 1
    dut.i_query_valid.value = 1
    dut.i_query_vec_a.value = 0
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    # Feed remaining query chunks
    NUM_CHUNKS = 16
    for ci in range(1, NUM_CHUNKS):
        await RisingEdge(dut.clk)
    dut.i_query_valid.value = 0

    # Module should now be in SCAN state.
    # Cycle through centroids injecting results.
    # We need to also handle the URAM read / DCU streaming handshake.
    # For a focused top-P test, drive the minimal interface:

    # Wait for scan state (will cycle through centroids even without URAM data)
    for ci in range(N):
        # Provide centroid read data (dummy) and DCU handshake
        for ch in range(num_chunks):
            await RisingEdge(dut.clk)
            dut.i_centroid_rdata.value = 0
            dut.i_dcu_vec_a_ready.value = 1

        # Inject the distance result for this centroid
        # Pipeline: result arrives some cycles after last chunk
        await ClockCycles(dut.clk, 2)
        dut.i_dcu_distance.value = distances[ci]
        dut.i_dcu_valid.value = 1
        await RisingEdge(dut.clk)
        dut.i_dcu_valid.value = 0
        dut.i_dcu_vec_a_ready.value = 0

    # Wait for done
    timeout = 200
    while timeout > 0:
        await RisingEdge(dut.clk)
        timeout -= 1
        if dut.o_done.value == 1:
            break

    assert timeout > 0, "Timeout waiting for o_done"

    # Check results
    count = dut.o_cluster_count.value
    assert count == P, f"Expected cluster_count={P}, got {count}"

    for rank in range(P):
        cid = dut.o_cluster_id[rank].value
        assert cid == expected_top3[rank], (
            f"Rank {rank}: expected cluster_id={expected_top3[rank]}, got {cid}"
        )
        cocotb.log.info(f"Rank {rank}: cluster_id={cid}, distance={expected_dists[rank]}")

    cocotb.log.info("Top-3 selection test PASS")


@cocotb.test()
async def test_coarse_search_all_same_distance(dut):
    """
    Edge case: all centroids have the same distance.
    Should select the first P centroids (since insertion sort keeps earliest
    when distances are equal, depending on implementation).
    """
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    N = 8
    DIM = 128
    P = 3
    num_chunks = (DIM + 15) // 16  # 8

    # All distances identical
    distances = [100] * N

    dut.i_dim.value = DIM
    dut.i_metric.value = 0
    dut.i_probes.value = P
    dut.i_start.value = 1
    dut.i_query_valid.value = 1
    dut.i_query_vec_a.value = 0
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    for ci in range(1, num_chunks):
        await RisingEdge(dut.clk)
    dut.i_query_valid.value = 0

    # Wait for scan state
    for ci in range(N):
        for ch in range(num_chunks):
            await RisingEdge(dut.clk)
            dut.i_centroid_rdata.value = 0
            dut.i_dcu_vec_a_ready.value = 1

        await ClockCycles(dut.clk, 2)
        dut.i_dcu_distance.value = distances[ci]
        dut.i_dcu_valid.value = 1
        await RisingEdge(dut.clk)
        dut.i_dcu_valid.value = 0
        dut.i_dcu_vec_a_ready.value = 0

    # Wait for done
    dut.i_dcu_vec_a_ready.value = 1
    timeout = 200
    while timeout > 0:
        await RisingEdge(dut.clk)
        timeout -= 1
        if dut.o_done.value == 1:
            break

    assert timeout > 0, "Timeout waiting for o_done"
    count = dut.o_cluster_count.value
    assert count == P, f"Expected cluster_count={P}, got {count}"
    cocotb.log.info(f"All-same-distance test PASS, count={count}")


@cocotb.test()
async def test_coarse_search_max_probes(dut):
    """
    Test with MAX_PROBES=8, verifying all 8 slots fill correctly.
    """
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    N = 32
    DIM = 256
    P = 8
    num_chunks = (DIM + 15) // 16

    # Monotonically increasing distances: centroids 0-31 have dist 1000..1031
    distances = [1000 + i for i in range(N)]
    # Expected top-8: indices 0..7
    expected_top8 = list(range(8))

    dut.i_dim.value = DIM
    dut.i_metric.value = 0
    dut.i_probes.value = P
    dut.i_start.value = 1
    dut.i_query_valid.value = 1
    dut.i_query_vec_a.value = 0
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    for ci in range(1, num_chunks):
        await RisingEdge(dut.clk)
    dut.i_query_valid.value = 0

    for ci in range(N):
        for ch in range(num_chunks):
            await RisingEdge(dut.clk)
            dut.i_centroid_rdata.value = 0
            dut.i_dcu_vec_a_ready.value = 1

        await ClockCycles(dut.clk, 2)
        dut.i_dcu_distance.value = distances[ci]
        dut.i_dcu_valid.value = 1
        await RisingEdge(dut.clk)
        dut.i_dcu_valid.value = 0
        dut.i_dcu_vec_a_ready.value = 0

    dut.i_dcu_vec_a_ready.value = 1
    timeout = 400
    while timeout > 0:
        await RisingEdge(dut.clk)
        timeout -= 1
        if dut.o_done.value == 1:
            break

    assert timeout > 0, "Timeout waiting for o_done"
    count = dut.o_cluster_count.value
    assert count == P, f"Expected cluster_count={P}, got {count}"

    for rank in range(P):
        cid = dut.o_cluster_id[rank].value
        assert cid == expected_top8[rank], (
            f"Rank {rank}: expected cluster_id={expected_top8[rank]}, got {cid}"
        )
    cocotb.log.info(f"Max probes ({P}) test PASS")


@cocotb.test()
async def test_coarse_search_repeated_start(dut):
    """
    Test that the module can be started multiple times.
    """
    clock = Clock(dut.clk, 3, units="ns")
    cocotb.start_soon(clock.start())

    await drive_reset(dut, 5)

    DIM = 64
    P = 2
    num_chunks = (DIM + 15) // 16  # 4

    for trial in range(3):
        distances = [trial * 100 + i for i in range(8)]

        dut.i_dim.value = DIM
        dut.i_metric.value = 0
        dut.i_probes.value = P
        dut.i_start.value = 1
        dut.i_query_valid.value = 1
        dut.i_query_vec_a.value = 0
        await RisingEdge(dut.clk)
        dut.i_start.value = 0

        for ci in range(1, num_chunks):
            await RisingEdge(dut.clk)
        dut.i_query_valid.value = 0

        for ci in range(8):
            for ch in range(num_chunks):
                await RisingEdge(dut.clk)
                dut.i_centroid_rdata.value = 0
                dut.i_dcu_vec_a_ready.value = 1

            await ClockCycles(dut.clk, 2)
            dut.i_dcu_distance.value = distances[ci]
            dut.i_dcu_valid.value = 1
            await RisingEdge(dut.clk)
            dut.i_dcu_valid.value = 0
            dut.i_dcu_vec_a_ready.value = 0

        dut.i_dcu_vec_a_ready.value = 1
        timeout = 200
        while timeout > 0:
            await RisingEdge(dut.clk)
            timeout -= 1
            if dut.o_done.value == 1:
                break

        assert timeout > 0, f"Trial {trial}: timeout waiting for o_done"
        count = dut.o_cluster_count.value
        assert count == P, f"Trial {trial}: Expected count={P}, got {count}"
        cocotb.log.info(f"Trial {trial}: done with count={count}")

        # Wait a cycle before restarting
        await RisingEdge(dut.clk)

    cocotb.log.info("Repeated start test PASS")
