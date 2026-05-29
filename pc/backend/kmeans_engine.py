"""K-means clustering engine using Faiss for offline index building."""

import numpy as np
import faiss
import struct


class KMeansEngine:
    """Builds IVF index for FPGA vector search appliance."""

    def __init__(self, nlist: int = 1024, dim: int = 256):
        self.nlist = nlist
        self.dim = dim

    def cluster(self, vectors: np.ndarray) -> dict:
        """
        vectors: (N, dim) float32
        Returns dict with centroids, assignments, cluster sizes, sorted vectors.
        """
        n, d = vectors.shape
        assert d == self.dim, f"Dim mismatch: {d} vs {self.dim}"
        assert n >= self.nlist, f"Need at least {self.nlist} vectors, got {n}"

        # Faiss k-means
        kmeans = faiss.Kmeans(d, self.nlist, niter=20, verbose=True)
        kmeans.train(vectors)

        centroids = kmeans.centroids.astype(np.float32)  # (nlist, dim)

        # Assign each vector to nearest centroid
        index_flat = faiss.IndexFlatL2(d)
        index_flat.add(centroids)
        _, assignments = index_flat.search(vectors, 1)
        assignments = assignments.flatten()

        cluster_sizes = np.bincount(assignments, minlength=self.nlist)

        # Sort vectors by cluster ID for contiguous DDR4 layout
        sort_idx = np.argsort(assignments)
        sorted_vectors = vectors[sort_idx].astype(np.float32)
        sorted_assignments = assignments[sort_idx]

        # Compute cluster base offsets
        cluster_bases = np.zeros(self.nlist, dtype=np.int32)
        offset = 0
        for c in range(self.nlist):
            cluster_bases[c] = offset
            offset += int(cluster_sizes[c])

        return {
            'centroids': centroids,
            'assignments': sorted_assignments,
            'cluster_sizes': cluster_sizes.astype(np.int32),
            'cluster_bases': cluster_bases,
            'sorted_vectors': sorted_vectors,
        }

    def build_index_payload(self, cluster_result: dict) -> bytes:
        """Pack cluster metadata + centroids + sorted vectors for FPGA import."""
        centroids = cluster_result['centroids']
        cluster_sizes = cluster_result['cluster_sizes']
        cluster_bases = cluster_result['cluster_bases']
        sorted_vectors = cluster_result['sorted_vectors']

        payload = b''
        # Header: nlist (2B) + dim (2B) + reserved (4B)
        payload += struct.pack('<HHI', self.nlist, self.dim, 0)

        # Cluster table: 1024 entries x (4B base + 2B size)
        for i in range(self.nlist):
            payload += struct.pack('<IH', int(cluster_bases[i]), int(cluster_sizes[i]))

        # Centroids: (nlist, dim) float32 raw
        payload += centroids.tobytes()

        # Sorted vectors: (N, dim) float32 raw
        payload += sorted_vectors.tobytes()

        return payload

    def reconstruct_centroids(self, vectors: np.ndarray,
                               assignments: np.ndarray) -> np.ndarray:
        """Recompute centroids from vectors and their cluster assignments."""
        centroids = np.zeros((self.nlist, self.dim), dtype=np.float32)
        counts = np.zeros(self.nlist, dtype=np.int32)
        for i in range(len(vectors)):
            c = assignments[i]
            centroids[c] += vectors[i]
            counts[c] += 1
        for c in range(self.nlist):
            if counts[c] > 0:
                centroids[c] /= counts[c]
        return centroids
