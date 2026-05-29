"""Benchmark CPU Faiss IVF search for comparison with FPGA."""

import numpy as np
import faiss
import time
import json
import argparse


def bench_cpu_faiss(vectors_path: str, queries_path: str,
                     nlist: int = 1024, nprobe: int = 2, topk: int = 10) -> dict:
    """Measure CPU Faiss IVF latency."""
    vectors = np.load(vectors_path)
    queries = np.load(queries_path)
    n, dim = vectors.shape
    n_q = min(len(queries), 1000)

    print(f"Dataset: {n} vectors x {dim}d, nlist={nlist}, nprobe={nprobe}")
    print(f"Building Faiss IVF index...")

    t0 = time.perf_counter()
    quantizer = faiss.IndexFlatL2(dim)
    index = faiss.IndexIVFFlat(quantizer, dim, nlist)
    index.train(vectors)
    index.add(vectors)
    index.nprobe = nprobe
    build_time = time.perf_counter() - t0
    print(f"Index built in {build_time:.2f}s")

    # Warmup
    for _ in range(100):
        index.search(queries[:1], topk)

    # Benchmark
    latencies = []
    for i in range(n_q):
        q = queries[i:i+1]
        t0 = time.perf_counter()
        index.search(q, topk)
        lat = (time.perf_counter() - t0) * 1_000_000  # us
        latencies.append(lat)
        if (i + 1) % 100 == 0:
            a = np.array(latencies)
            print(f"  [{i+1}/{n_q}] p50={np.percentile(a,50):.1f}us p99={np.percentile(a,99):.1f}us")

    a = np.array(latencies)
    return {
        'n_vectors': int(n),
        'dim': dim,
        'nlist': nlist,
        'nprobe': nprobe,
        'topk': topk,
        'n_queries': n_q,
        'build_time_s': build_time,
        'p50_us': float(np.percentile(a, 50)),
        'p99_us': float(np.percentile(a, 99)),
        'mean_us': float(np.mean(a)),
        'std_us': float(np.std(a)),
        'min_us': float(np.min(a)),
        'max_us': float(np.max(a)),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=str, required=True)
    parser.add_argument('--queries', type=str, required=True)
    parser.add_argument('--nlist', type=int, default=1024)
    parser.add_argument('--nprobe', type=int, default=2)
    parser.add_argument('--topk', type=int, default=10)
    parser.add_argument('--output', type=str, default=None)
    args = parser.parse_args()

    result = bench_cpu_faiss(args.vectors, args.queries,
                              args.nlist, args.nprobe, args.topk)
    print(json.dumps(result, indent=2))

    if args.output:
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
