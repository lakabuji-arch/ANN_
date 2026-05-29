"""FPGA Vector Search Appliance — UDP Protocol Codec

Frame format (8-byte header + payload):
  Byte 0:   command code (request 0x01-0x7F, response 0x81-0xFF)
  Byte 1:   flags (bit0=ACK, bit1=ERR, bit2=MORE)
  Byte 2-3: sequence number (big-endian)
  Byte 4-7: payload length (big-endian)
  Byte 8-N: payload
"""

import struct
import numpy as np
from enum import IntEnum

FIXED_SCALE = 65536.0


class CmdCode(IntEnum):
    SEARCH = 0x01
    INSERT = 0x02
    BATCH_SEARCH = 0x03
    REINDEX = 0x04
    DELETE = 0x05
    GET_STATUS = 0x06
    EXPORT = 0x07
    COMMIT_SWITCH = 0x08
    # Responses
    RESP_SEARCH = 0x81
    RESP_INSERT = 0x82
    RESP_BATCH = 0x83
    RESP_REINDEX = 0x84
    RESP_DELETE = 0x85
    RESP_STATUS = 0x86
    RESP_EXPORT = 0x87
    RESP_SWITCH_DONE = 0x88


class Metric(IntEnum):
    L2 = 0
    COSINE = 1
    IP = 2


class DataType(IntEnum):
    FLOAT32 = 0
    FLOAT16 = 1
    INT8 = 2


def pack_header(cmd: CmdCode, seq: int, payload_len: int, flags: int = 0) -> bytes:
    return struct.pack('>BBHI', int(cmd), flags, seq & 0xFFFF, payload_len)


def unpack_header(data: bytes) -> tuple:
    cmd, flags, seq, plen = struct.unpack('>BBHI', data[:8])
    return CmdCode(cmd), flags, seq, plen


def float32_to_q16(arr: np.ndarray) -> np.ndarray:
    """Convert float32 numpy array to Q16.16 int32"""
    clipped = np.clip(arr * 65536.0, -2147483648, 2147483647)
    return clipped.astype(np.int32)


def q16_to_float32(arr: np.ndarray) -> np.ndarray:
    return arr.astype(np.float64) / 65536.0


def pack_search_request(seq: int, vector: np.ndarray, topk: int = 10,
                         metric: Metric = Metric.L2, probes: int = 2,
                         dtype: DataType = DataType.FLOAT32) -> bytes:
    """Pack a SEARCH command."""
    dim = vector.shape[0]
    if dtype == DataType.FLOAT32:
        vec_bytes = vector.astype(np.float32).tobytes()
    else:
        raise ValueError("Only FLOAT32 supported currently")

    payload = struct.pack('>HBBB', dim & 0xFFFF, int(metric), topk & 0xFF, int(dtype))
    payload += struct.pack('B', probes & 0xFF)
    payload += vec_bytes
    return pack_header(CmdCode.SEARCH, seq, len(payload)) + payload


def parse_search_response(data: bytes) -> tuple:
    """Parse SEARCH response. Returns (list_of_results, latency_us).
    Each result: (distance_float, vector_id)
    """
    _, flags, _, _ = unpack_header(data[:8])
    if flags & 0x02:
        raise RuntimeError("FPGA returned error flag")

    payload = data[8:]
    # Search response: topk pairs of (4B distance Q16.16, 4B vector_id)
    n_results = len(payload) // 8
    results = []
    for i in range(n_results):
        dist_raw = struct.unpack('>i', payload[i*8:i*8+4])[0]
        vid = struct.unpack('>I', payload[i*8+4:i*8+8])[0]
        results.append((dist_raw / 65536.0, vid))
    return results


def pack_insert_request(seq: int, vectors: np.ndarray,
                         dtype: DataType = DataType.FLOAT32) -> bytes:
    """Pack an INSERT command. vectors shape: (N, dim)"""
    n, dim = vectors.shape
    if dtype == DataType.FLOAT32:
        vec_bytes = vectors.astype(np.float32).tobytes()
    else:
        raise ValueError("Only FLOAT32 supported currently")

    payload = struct.pack('>HHB', n & 0xFFFF, dim & 0xFFFF, int(dtype))
    payload += vec_bytes
    return pack_header(CmdCode.INSERT, seq, len(payload)) + payload


def pack_status_request(seq: int) -> bytes:
    return pack_header(CmdCode.GET_STATUS, seq, 0)


def parse_status_response(data: bytes) -> dict:
    """Parse STATUS response into dictionary."""
    _, flags, _, _ = unpack_header(data[:8])
    if flags & 0x02:
        raise RuntimeError("FPGA returned error")

    payload = data[8:]
    return {
        'total_vectors': struct.unpack('>I', payload[0:4])[0],
        'num_clusters': struct.unpack('>H', payload[4:6])[0],
        'active_zone': 'A' if payload[6] == 0 else 'B',
        'ddr4_used_mb': struct.unpack('>I', payload[8:12])[0],
        'avg_latency_us': struct.unpack('>I', payload[12:16])[0],
        'p99_latency_us': struct.unpack('>I', payload[16:20])[0],
        'qps': struct.unpack('>I', payload[20:24])[0],
        'uram_usage_pct': payload[24],
        'temperature': payload[28],
    }


def pack_reindex_request(seq: int) -> bytes:
    return pack_header(CmdCode.REINDEX, seq, 0)


def pack_commit_switch_request(seq: int) -> bytes:
    return pack_header(CmdCode.COMMIT_SWITCH, seq, 0)


def pack_export_request(seq: int) -> bytes:
    return pack_header(CmdCode.EXPORT, seq, 0)
