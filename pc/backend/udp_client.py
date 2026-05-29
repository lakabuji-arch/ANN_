"""FPGA Vector Search Appliance — UDP Client"""

import socket
import time
import struct
import numpy as np
from protocol import *


class FPGAVectorClient:
    """UDP client for communicating with the FPGA vector search appliance."""

    def __init__(self, fpga_ip: str = "192.168.1.10",
                 ctrl_port: int = 8001, data_port: int = 8002,
                 timeout: float = 5.0):
        self.fpga_ip = fpga_ip
        self.ctrl_port = ctrl_port
        self.data_port = data_port
        self.timeout = timeout

        self.ctrl_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.ctrl_sock.settimeout(timeout)
        self.data_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.data_sock.settimeout(timeout)

        self.seq = 0

    def _next_seq(self) -> int:
        self.seq = (self.seq + 1) & 0xFFFF
        return self.seq

    def _send_recv(self, request: bytes, expected_cmd: CmdCode) -> bytes:
        self.ctrl_sock.sendto(request, (self.fpga_ip, self.ctrl_port))
        response, _ = self.ctrl_sock.recvfrom(65536)
        cmd, flags, rsp_seq, _ = unpack_header(response)
        if flags & 0x02:
            raise RuntimeError(f"FPGA error: cmd=0x{int(cmd):02X}, seq={rsp_seq}")
        return response

    def search(self, query: np.ndarray, topk: int = 10,
               metric: Metric = Metric.L2, probes: int = 2) -> tuple:
        """Execute SEARCH. Returns (results_list, latency_us)."""
        seq = self._next_seq()
        request = pack_search_request(seq, query, topk, metric, probes)
        t0 = time.perf_counter()
        response = self._send_recv(request, CmdCode.RESP_SEARCH)
        elapsed = (time.perf_counter() - t0) * 1_000_000
        results = parse_search_response(response)
        return results, elapsed

    def insert(self, vectors: np.ndarray) -> bool:
        """Insert vectors into FPGA pending buffer. Returns success."""
        seq = self._next_seq()
        request = pack_insert_request(seq, vectors)
        try:
            self._send_recv(request, CmdCode.RESP_INSERT)
            return True
        except RuntimeError:
            return False

    def get_status(self) -> dict:
        """Get device status."""
        seq = self._next_seq()
        request = pack_status_request(seq)
        response = self._send_recv(request, CmdCode.RESP_STATUS)
        return parse_status_response(response)

    def reindex(self) -> bool:
        """Trigger index rebuild."""
        seq = self._next_seq()
        request = pack_reindex_request(seq)
        self._send_recv(request, CmdCode.RESP_REINDEX)
        return True

    def commit_switch(self) -> bool:
        """Commit A/B zone switch after reindex."""
        seq = self._next_seq()
        request = pack_commit_switch_request(seq)
        self._send_recv(request, CmdCode.RESP_SWITCH_DONE)
        return True

    def close(self):
        self.ctrl_sock.close()
        self.data_sock.close()
