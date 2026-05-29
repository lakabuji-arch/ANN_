"""Vector Search Appliance — FastAPI Backend."""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import numpy as np
import base64
import json
from udp_client import FPGAVectorClient, Metric
from kmeans_engine import KMeansEngine

app = FastAPI(title="Vector Search Appliance API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Configuration
FPGA_IP = "192.168.1.10"
DEFAULT_DIM = 256
NLIST = 1024

client = FPGAVectorClient(fpga_ip=FPGA_IP)
kmeans = KMeansEngine(nlist=NLIST, dim=DEFAULT_DIM)


# ─── Pydantic models ───
class SearchRequest(BaseModel):
    vector: list[float]
    topk: int = 10
    metric: str = "L2"
    probes: int = 2

class SearchResult(BaseModel):
    results: list[dict]
    latency_us: float

class DeviceStatus(BaseModel):
    total_vectors: int = 0
    num_clusters: int = 0
    active_zone: str = "A"
    ddr4_used_mb: int = 0
    avg_latency_us: int = 0
    p99_latency_us: int = 0
    qps: int = 0
    uram_usage_pct: int = 0
    temperature: int = 0

class InsertRequest(BaseModel):
    vectors_b64: str
    dim: int = 256

class IndexInfo(BaseModel):
    total_vectors: int
    num_clusters: int
    cluster_sizes: list[int]
    active_zone: str


# ─── Endpoints ───
@app.get("/")
def root():
    return {"service": "Vector Search Appliance", "version": "1.0.0"}

@app.post("/api/search", response_model=SearchResult)
async def search(req: SearchRequest):
    """Execute a vector similarity search."""
    try:
        query = np.array(req.vector, dtype=np.float32)
        metric_map = {"L2": Metric.L2, "COSINE": Metric.COSINE, "IP": Metric.IP}
        metric = metric_map.get(req.metric.upper(), Metric.L2)

        results, latency = client.search(query, req.topk, metric, req.probes)

        return SearchResult(
            results=[{"distance": float(d), "vector_id": int(vid)} for d, vid in results],
            latency_us=latency
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/status", response_model=DeviceStatus)
async def get_status():
    """Get device status."""
    try:
        s = client.get_status()
        return DeviceStatus(**s)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/insert")
async def insert_vectors(req: InsertRequest):
    """Insert vectors into FPGA pending buffer."""
    try:
        data = base64.b64decode(req.vectors_b64)
        vectors = np.frombuffer(data, dtype=np.float32).reshape(-1, req.dim)
        ok = client.insert(vectors)
        return {"success": ok, "count": vectors.shape[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/cluster")
async def cluster_vectors(vectors_b64: str, dim: int = 256):
    """Run k-means clustering on a set of vectors."""
    try:
        data = base64.b64decode(vectors_b64)
        vectors = np.frombuffer(data, dtype=np.float32).reshape(-1, dim)
        result = kmeans.cluster(vectors)

        # Return cluster sizes for visualization
        return {
            "nlist": kmeans.nlist,
            "total_vectors": vectors.shape[0],
            "cluster_sizes": result['cluster_sizes'].tolist(),
            "empty_clusters": int((result['cluster_sizes'] == 0).sum()),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/reindex")
async def trigger_reindex():
    """Trigger a full index rebuild cycle."""
    try:
        client.reindex()
        return {"success": True, "message": "Reindex triggered"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/commit-switch")
async def commit_switch():
    """Commit A/B zone switch after reindex data import."""
    try:
        client.commit_switch()
        return {"success": True, "message": "Zone switch committed"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/health")
async def health():
    """Health check endpoint."""
    try:
        client.get_status()
        return {"fpga_connected": True}
    except Exception:
        return {"fpga_connected": False}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
