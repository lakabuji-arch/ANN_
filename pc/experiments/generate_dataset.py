"""Generate synthetic vector datasets for benchmarking."""

import numpy as np
import os
import argparse


def generate_random(n_vectors: int, dim: int, seed: int = 42):
    """Gaussian random vectors."""
    rng = np.random.default_rng(seed)
    return rng.normal(0, 1, (n_vectors, dim)).astype(np.float32)


def generate_clustered(n_vectors: int, dim: int, n_clusters: int = 50, seed: int = 42):
    """Clustered vectors: more realistic for ANN testing."""
    rng = np.random.default_rng(seed)
    # Generate cluster centers
    centers = rng.normal(0, 3, (n_clusters, dim)).astype(np.float32)
    # Assign vectors to clusters
    per_cluster = n_vectors // n_clusters
    vectors = []
    for c in range(n_clusters):
        cluster_vecs = centers[c] + rng.normal(0, 0.5, (per_cluster, dim))
        vectors.append(cluster_vecs.astype(np.float32))
    # Fill remainder
    rem = n_vectors - len(vectors) * per_cluster
    if rem > 0:
        vectors.append(centers[0] + rng.normal(0, 0.5, (rem, dim)).astype(np.float32))
    return np.vstack(vectors).astype(np.float32)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dim', type=int, default=256)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--clustered', action='store_true')
    parser.add_argument('--outdir', type=str, default='data')
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    gen = generate_clustered if args.clustered else generate_random

    scales = [10_000, 50_000, 100_000, 500_000, 1_000_000]
    for n in scales:
        label = f"{n//1000}K"
        vectors = gen(n, args.dim, seed=args.seed)
        path = os.path.join(args.outdir, f"vectors_{label}_{args.dim}d.npy")
        np.save(path, vectors)
        mb = vectors.nbytes / (1024 * 1024)
        print(f"Generated {label} x {args.dim}d: {mb:.1f} MB -> {path}")

    # Also generate 1000 query vectors
    rng = np.random.default_rng(args.seed + 999)
    queries = rng.normal(0, 1, (1000, args.dim)).astype(np.float32)
    qpath = os.path.join(args.outdir, f"queries_1K_{args.dim}d.npy")
    np.save(qpath, queries)
    print(f"Generated 1000 queries -> {qpath}")


if __name__ == "__main__":
    main()
