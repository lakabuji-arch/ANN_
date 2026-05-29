"""Benchmark FPGA ANN search latency and QPS."""

import sys
sys.path.insert(0, '../backend')

import numpy as np
import json
import time
import argparse
from udp_client import FPGAVectorClient, Metric


def bench_latency(client: FPGAVectorClient, vectors_path: str, queries_path: str,
                   probes: int = 2, topk: int = 10, metric: Metric = Metric.L2) -> dict:
    """Measure per-query latency over a query set."""
    vectors = np.load(vectors_path)
    queries = np.load(queries_path)
    n, dim = vectors.shape
    n_q = min(len(queries), 1000)

    print(f"Dataset: {n} vectors x {dim}d, {n_q} queries, nprobe={probes}")
    print(f"Total data: {vectors.nbytes / 1024**2:.1f} MB")

    latencies = []
    for i in range(n_q):
        q = queries[i]
        _, lat = client.search(q, topk=topk, metric=metric, probes=probes)
        latencies.append(lat)
        if (i + 1) % 100 == 0:
            a = np.array(latencies)
            print(f"  [{i+1}/{n_q}] p50={np.percentile(a,50):.1f}us p99={np.percentile(a,99):.1f}us")

    a = np.array(latencies)
    return {
        'n_vectors': int(n),
        'dim': dim,
        'n_queries': n_q,
        'nprobe': probes,
        'topk': topk,
        'p50_us': float(np.percentile(a, 50)),
        'p99_us': float(np.percentile(a, 99)),
        'mean_us': float(np.mean(a)),
        'std_us': float(np.std(a)),
        'min_us': float(np.min(a)),
        'max_us': float(np.max(a)),
    }


def bench_qps(client: FPGAVectorClient, queries_path: str,
               duration_s: int = 30, topk: int = 10) -> dict:
    """Measure sustained QPS."""
    queries = np.load(queries_path)
    n_q = len(queries)

    print(f"QPS test: {duration_s}s duration, {n_q} queries (cycling)")

    t_start = time.perf_counter()
    count = 0
    errors = 0
    while time.perf_counter() - t_start < duration_s:
        q = queries[count % n_q]
        try:
            client.search(q, topk=topk)
            count += 1
        except Exception:
            errors += 1

    elapsed = time.perf_counter() - t_start
    return {
        'duration_s': elapsed,
        'total_queries': count,
        'qps': count / elapsed,
        'errors': errors,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=str, required=True, help='Path to vectors .npy')
    parser.add_argument('--queries', type=str, required=True, help='Path to queries .npy')
    parser.add_argument('--fpga-ip', type=str, default='192.168.1.10')
    parser.add_argument('--probes', type=int, default=2)
    parser.add_argument('--topk', type=int, default=10)
    parser.add_argument('--qps', action='store_true', help='Run QPS test instead of latency')
    parser.add_argument('--duration', type=int, default=30)
    parser.add_argument('--output', type=str, default=None)
    args = parser.parse_args()

    client = FPGAVectorClient(fpga_ip=args.fpga_ip)

    if args.qps:
        result = bench_qps(client, args.queries, args.duration, args.topk)
    else:
        result = bench_latency(client, args.vectors, args.queries,
                               probes=args.probes, topk=args.topk)

    print(json.dumps(result, indent=2))

    if args.output:
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
        print(f"Saved to {args.output}")

    client.close()


if __name__ == "__main__":
    main()
