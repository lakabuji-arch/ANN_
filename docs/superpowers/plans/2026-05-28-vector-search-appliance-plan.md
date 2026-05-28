# 100G 向量检索引擎 (Vector Search Appliance) 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 XCKU5P FPGA 上构建基于 IVF 算法的 ANN 向量检索引擎，搭配 PC 端 FastAPI + Vue Web 管理面板，实现完整的独立向量搜索产品。

**Architecture:** FPGA 侧 8 个新模块运行在 ddr4_ui_clk (333MHz)，复用现有 cmac_100g_wrapper 网络栈，通过 UDP:8001/8002 双端口与 PC 通信。PC 侧 FastAPI 后端 + Vue3 前端 + Faiss k-means 引擎。TDD 开发流程，cocotb 模块级仿真先行。

**Tech Stack:** SystemVerilog (FPGA), cocotb (仿真), Python/FastAPI (后端), Vue3/ECharts (前端), Faiss/numpy (实验)

**文件位置基准:** `d:/user/wangshihao/CMAC/CMAC_DDR4/`

---

## 文件结构

```
cmac_usplus_0_ex.srcs/
├── sources_1/new/                    ← 现有 RTL (12 文件, 不变)
│   ├── rx_demux.sv                   ← [修改] 新增 Ch4: UDP:8002
│   ├── search_engine/                ← [新建] FPGA 搜索模块
│   │   ├── search_engine_top.sv
│   │   ├── search_cmd_dispatcher.sv
│   │   ├── ann_coarse_search.sv
│   │   ├── ddr4_scanner.sv
│   │   ├── index_manager.sv
│   │   ├── distance_compute_unit.sv
│   │   ├── topk_heap.sv
│   │   └── ddr4_arbiter.sv
│   └── search_engine_pkg.sv          ← [新建] 共享参数包
├── sim_1/new/                        ← cocotb 测试
│   ├── test_distance_compute.py
│   ├── test_topk_heap.py
│   ├── test_ann_coarse_search.py
│   ├── test_ddr4_scanner.py
│   ├── test_index_manager.py
│   ├── test_cmd_dispatcher.py
│   ├── test_search_engine_full.py
│   └── test_reindex_flow.py
├── constrs_1/new/
│   └── integrated.xdc               ← [修改] 新增 search_engine 时钟约束
└── pc/                               ← [新建] PC 端软件
    ├── backend/
    │   ├── main.py                   ← FastAPI 入口
    │   ├── udp_client.py             ← UDP 通信层
    │   ├── protocol.py               ← 命令编解码
    │   ├── kmeans_engine.py          ← k-means 聚类
    │   └── requirements.txt
    ├── frontend/
    │   ├── src/
    │   │   ├── App.vue
    │   │   ├── components/
    │   │   │   ├── Dashboard.vue
    │   │   │   ├── VectorBrowser.vue
    │   │   │   ├── IndexManager.vue
    │   │   │   └── LatencyChart.vue
    │   │   └── main.js
    │   ├── package.json
    │   └── vite.config.js
    └── experiments/
        ├── generate_dataset.py
        ├── bench_fpga.py
        ├── bench_cpu_faiss.py
        └── plot_results.py
```

---

## Phase 1: FPGA 基础设施模块 (TDD)

### Task 1: 共享参数包 search_engine_pkg

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine_pkg.sv`

- [ ] **Step 1: 创建参数包**

```systemverilog
// search_engine_pkg.sv — 全搜索引擎共享参数
package search_engine_pkg;

    // 索引参数
    parameter int NCLUSTERS       = 1024;         // k-means 簇数
    parameter int MAX_PROBES      = 8;            // 最大探测簇数
    parameter int DEFAULT_PROBES  = 2;            // 默认探测簇数
    parameter int DEFAULT_TOPK    = 10;           // 默认 TopK
    parameter int MAX_TOPK        = 256;          // 最大 TopK
    parameter int MAX_DIM         = 1536;         // 最大向量维度
    parameter int DEFAULT_DIM     = 256;          // 默认维度

    // 距离计算参数
    parameter int DCU_PARALLEL    = 64;           // 每周期并行维度数
    parameter int DCU_LATENCY     = 4;            // 流水线延迟

    // DDR4 布局
    parameter logic [31:0] ZONE_A_BASE = 32'h0000_0000;
    parameter logic [31:0] ZONE_B_BASE = 32'h4000_0000;
    parameter logic [31:0] ZONE_SIZE    = 32'h4000_0000;  // 1GB

    // 命令码
    typedef enum logic [7:0] {
        CMD_SEARCH       = 8'h01,
        CMD_INSERT       = 8'h02,
        CMD_BATCH_SEARCH = 8'h03,
        CMD_REINDEX      = 8'h04,
        CMD_DELETE       = 8'h05,
        CMD_GET_STATUS   = 8'h06,
        CMD_EXPORT       = 8'h07,
        CMD_COMMIT_SWITCH= 8'h08,
        RESP_SEARCH       = 8'h81,
        RESP_INSERT       = 8'h82,
        RESP_BATCH        = 8'h83,
        RESP_REINDEX      = 8'h84,
        RESP_DELETE       = 8'h85,
        RESP_STATUS       = 8'h86,
        RESP_EXPORT       = 8'h87,
        RESP_SWITCH_DONE  = 8'h88
    } cmd_code_t;

    // 距离度量类型
    typedef enum logic [1:0] {
        METRIC_L2     = 2'b00,
        METRIC_COSINE = 2'b01,
        METRIC_IP     = 2'b10
    } metric_t;

    // 数据类型
    typedef enum logic [1:0] {
        DTYPE_FLOAT32 = 2'b00,
        DTYPE_FLOAT16 = 2'b01,
        DTYPE_INT8    = 2'b10
    } data_type_t;

endpackage
```

- [ ] **Step 2: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine_pkg.sv
git commit -m "feat: add search_engine_pkg shared parameter package"
```

---

### Task 2: distance_compute_unit (DCU)

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/distance_compute_unit.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_distance_compute.py`

**依赖:** search_engine_pkg

- [ ] **Step 1: 创建 Makefile 用于 cocotb 仿真**

```makefile
# sim/Makefile
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = ../cmac_usplus_0_ex.srcs/sources_1/new/search_engine/distance_compute_unit.sv
TOPLEVEL = distance_compute_unit
MODULE = test_distance_compute
```

- [ ] **Step 2: 写测试 — L2 距离计算**

```python
# sim/test_distance_compute.py
import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np

@cocotb.test()
async def test_l2_distance_basic(dut):
    """L2 distance: two 4-element vectors, known result"""
    cocotb.start_soon(Clock(dut.clk, 3, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    # vector a = [1.0, 2.0, 3.0, 4.0]
    # vector b = [4.0, 3.0, 2.0, 1.0]
    # expected L2 = (3^2 + 1^2 + 1^2 + 3^2) = 20
    a = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float32)
    b = np.array([4.0, 3.0, 2.0, 1.0], dtype=np.float32)
    expected = np.sum((a - b) ** 2)

    # Write query vector to DCU ports (simplified — actual port names from module)
    # The DCU receives vectors as 512-bit packed floats
    # 512/32 = 16 floats per cycle
    dut.i_dim.value = 4
    dut.i_metric.value = 0  # L2
    dut.i_start.value = 1

    # The DCU is a multi-cycle pipeline; wait for o_valid
    while not dut.o_valid.value:
        await RisingEdge(dut.clk)
        dut.i_start.value = 0  # deassert after first cycle

    result = float(dut.o_distance.value)
    cocotb.log.info(f"Expected L2={expected:.4f}, Got={result:.4f}")

    assert abs(result - expected) < 0.01, \
        f"L2 mismatch: expected {expected}, got {result}"
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd sim && make 2>&1 | tail -20
# Expected: FAIL — module not found or output wrong
```

- [ ] **Step 4: 实现 distance_compute_unit**

```systemverilog
// distance_compute_unit.sv — 流式向量距离计算
// N_PARALLEL=64, 支持 L2/余弦/IP, float32
module distance_compute_unit #(
    parameter N_PARALLEL = 64,
    parameter MAX_DIM    = 1536
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         i_start,
    input  wire [10:0]  i_dim,           // 实际维度 (1-1536)
    input  wire [1:0]   i_metric,        // 0=L2, 1=cosine, 2=IP

    // 向量 A: 查询向量, 每周期 N_PARALLEL/4 个 float32 = 512b
    input  wire [511:0] i_vec_a_tdata,
    input  wire         i_vec_a_tvalid,
    output wire         o_vec_a_tready,

    // 向量 B: 数据库向量, 同格式
    input  wire [511:0] i_vec_b_tdata,
    input  wire         i_vec_b_tvalid,
    output wire         o_vec_b_tready,

    output wire         o_valid,
    output wire [31:0]  o_distance       // float32 距离值
);
    // 流水线状态
    localparam ST_IDLE = 0, ST_COMPUTE = 1, ST_DONE = 2;
    reg [1:0] state = ST_IDLE;

    // 维度计数器: 每周期处理 N_PARALLEL/4 = 16 个 float32
    reg [10:0] dim_cnt;
    reg [31:0] accum;                    // 累加器

    // 16 路并行浮点减法 + 乘法
    wire [31:0] diff_sq [0:15];
    wire [31:0] a_floats [0:15];
    wire [31:0] b_floats [0:15];

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_diff
            assign a_floats[i] = i_vec_a_tdata[i*32 +: 32];
            assign b_floats[i] = i_vec_b_tdata[i*32 +: 32];

            // float32 subtract
            wire [31:0] diff;
            fp_sub u_sub (.a(a_floats[i]), .b(b_floats[i]), .result(diff));
            // float32 multiply
            fp_mul u_mul (.a(diff), .b(diff), .result(diff_sq[i]));
        end
    endgenerate

    // 累加器加法树 (4 级流水线)
    // Stage 1: 16→8
    wire [31:0] s1 [0:7];
    // Stage 2: 8→4
    wire [31:0] s2 [0:3];
    // Stage 3: 4→2
    wire [31:0] s3 [0:1];
    // Stage 4: 2→1
    wire [31:0] cycle_sum;

    // ... (浮点加法器连接, 省略详细连线以保持可读性)
    // 每个 add 延迟 1 cycle, 4 级流水线 = 4 cycle latency

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            dim_cnt <= 0;
            accum <= 32'h0000_0000;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (i_start) begin
                        state <= ST_COMPUTE;
                        dim_cnt <= 0;
                        accum <= 32'h0000_0000;
                    end
                end

                ST_COMPUTE: begin
                    if (i_vec_a_tvalid && i_vec_b_tvalid) begin
                        dim_cnt <= dim_cnt + 16;
                        // FP add cycle_sum to accum (pipeline aligned)
                        wire [31:0] sum_out;
                        fp_add u_final (.a(accum), .b(cycle_sum), .result(sum_out));
                        accum <= sum_out;
                    end

                    if (dim_cnt + 16 >= i_dim)
                        state <= ST_DONE;
                end

                ST_DONE: state <= ST_IDLE;
            endcase
        end
    end

    assign o_valid = (state == ST_DONE);
    assign o_distance = accum;
    assign o_vec_a_tready = (state == ST_COMPUTE);
    assign o_vec_b_tready = (state == ST_COMPUTE);

endmodule
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd sim && make 2>&1 | tail -5
# Expected: PASS
```

- [ ] **Step 6: 扩写测试 — 余弦相似度、内积、边界维度**

```python
@cocotb.test()
async def test_cosine_distance(dut):
    """Cosine: normalized dot product"""
    # a = [1,0,0,0], b = [1,0,0,0] → cosine = 0 (identical)
    ...

@cocotb.test()
async def test_ip_distance(dut):
    """Inner product: a·b, negative for dissimilar"""
    ...

@cocotb.test()
async def test_dim_boundaries(dut):
    """Test dim=1, dim=256, dim=1536"""
    for dim in [1, 16, 256, 768, 1536]:
        ...

@cocotb.test()
async def test_pipeline_backpressure(dut):
    """Verify TREADY deassertion stalls pipeline correctly"""
    ...
```

- [ ] **Step 7: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/distance_compute_unit.sv \
        cmac_usplus_0_ex.srcs/sources_1/new/search_engine/search_engine_pkg.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_distance_compute.py
git commit -m "feat: add distance_compute_unit with L2/cosine/IP support"
```

---

### Task 3: topk_heap

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/topk_heap.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_topk_heap.py`

**依赖:** search_engine_pkg

- [ ] **Step 1: 写测试**

```python
# sim/test_topk_heap.py
import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np

@cocotb.test()
async def test_topk_basic(dut):
    """Insert 100 distances, verify top-10 are the smallest 10"""
    cocotb.start_soon(Clock(dut.clk, 3, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    dut.i_k.value = 10

    # Random distances
    np.random.seed(42)
    distances = np.random.uniform(0, 100, 100).astype(np.float32)
    expected_top10 = np.sort(distances)[:10]

    # Insert one per cycle
    for i, d in enumerate(distances):
        dut.i_push.value = 1
        dut.i_distance.value = int.from_bytes(np.float32(d).tobytes(), 'little')
        dut.i_vector_id.value = i
        await RisingEdge(dut.clk)

    dut.i_push.value = 0
    await ClockCycles(dut.clk, 20)  # Wait for completion

    # Read back top-K
    dut.i_read_en.value = 1
    results = []
    for _ in range(10):
        await RisingEdge(dut.clk)
        vid = int(dut.o_vector_id.value)
        dist = float(np.frombuffer(int(dut.o_distance.value).to_bytes(4, 'little'), dtype=np.float32)[0])
        results.append((dist, vid))

    results.sort(key=lambda x: x[0])
    for (rd, _), ed in zip(results, expected_top10):
        assert abs(rd - ed) < 0.01, f"TopK mismatch: {rd} vs {ed}"
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd sim && make MODULE=test_topk_heap 2>&1 | tail -5
# Expected: FAIL
```

- [ ] **Step 3: 实现 topk_heap**

```systemverilog
// topk_heap.sv — 浮点最小堆, 维护 TopK 个最小距离
module topk_heap #(
    parameter MAX_K = 256,
    parameter ID_WIDTH = 32
) (
    input  wire         clk,
    input  wire         rst,

    input  wire [7:0]   i_k,              // K 值 (1-256)
    input  wire         i_push,           // 插入新元素
    input  wire [31:0]  i_distance,       // float32 距离
    input  wire [ID_WIDTH-1:0] i_vector_id,

    output wire         o_full,           // 堆已满
    output wire         o_ready,          // 可以读取结果

    // 结果读出接口
    input  wire         i_read_en,
    output wire [31:0]  o_distance,
    output wire [ID_WIDTH-1:0] o_vector_id,
    output wire         o_valid,
    output wire [7:0]   o_count           // 实际堆内元素数
);
    // 堆存储: (distance, vector_id) pairs
    // heap[0] 是最大值 (根节点), 新元素比根小则替换
    reg [31:0] heap_dist [0:MAX_K-1];
    reg [ID_WIDTH-1:0] heap_id [0:MAX_K-1];  // 应该是 ID_WIDTH, 修复 typo
    reg [7:0] heap_size;

    // 浮点比较器
    wire gt;
    fp_compare u_cmp (.a(i_distance), .b(heap_dist[0]), .gt(gt));

    always @(posedge clk) begin
        if (rst) begin
            heap_size <= 0;
        end else if (i_push) begin
            if (heap_size < i_k) begin
                // 还没满, 直接插入
                heap_dist[heap_size] <= i_distance;
                heap_id[heap_size] <= i_vector_id;
                heap_size <= heap_size + 1;
                // 上浮新元素
            end else if (gt) begin
                // 新元素比堆顶(最大)小, 替换堆顶并下沉
                heap_dist[0] <= i_distance;
                heap_id[0] <= i_vector_id;
                // sift_down(0)
            end
        end
    end

    // sift_down 状态机 (省略详细实现, ~50行)

    assign o_full  = (heap_size >= i_k);
    assign o_ready = (heap_size == i_k);
    assign o_count = heap_size;

    // 结果读出: 顺序输出堆内元素
    // (详细读出逻辑省略, ~30行)
endmodule
```

- [ ] **Step 4-6: 运行测试、扩写测试 (K=1, K=256, 全相同值)、提交**

```bash
cd sim && make MODULE=test_topk_heap 2>&1 | tail -5
# Expected: PASS

git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/topk_heap.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_topk_heap.py
git commit -m "feat: add topk_heap for float32 min-heap"
```

---

### Task 4: ddr4_arbiter

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ddr4_arbiter.sv`

**依赖:** search_engine_pkg

- [ ] **Step 1: 实现 ddr4_arbiter (无独立 testbench, 由集成测试验证)**

```systemverilog
// ddr4_arbiter.sv — DDR4 AXI 读写仲裁
// 三端口: 搜索扫描 (最高优先), INSERT 写入, EXPORT 读出
// 读和写走不同 AXI 通道, 可以同时进行
// 同方向资源冲突时按优先级排队
module ddr4_arbiter (
    input  wire         clk,
    input  wire         rst,

    // === 连接到 MIG ===
    // AXI Read Address Channel
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    // AXI Read Data Channel
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,
    // AXI Write Address Channel
    output wire [31:0]  m_axi_awaddr,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    // AXI Write Data Channel
    output wire [511:0] m_axi_wdata,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // === Scanner 读请求 (优先级 0: 最高) ===
    input  wire [31:0]  s_scan_araddr,
    input  wire         s_scan_arvalid,
    output wire         s_scan_arready,
    output wire [511:0] s_scan_rdata,
    output wire         s_scan_rvalid,
    input  wire         s_scan_rready,

    // === INSERT 写请求 (优先级 1) ===
    input  wire [31:0]  s_insert_awaddr,
    input  wire         s_insert_awvalid,
    output wire         s_insert_awready,
    input  wire [511:0] s_insert_wdata,
    input  wire         s_insert_wvalid,
    output wire         s_insert_wready,

    // === EXPORT 读请求 (优先级 2: 最低) ===
    input  wire [31:0]  s_export_araddr,
    input  wire         s_export_arvalid,
    output wire         s_export_arready,
    output wire [511:0] s_export_rdata,
    output wire         s_export_rvalid,
    input  wire         s_export_rready
);
    // 读写完全独立, 读通道在 scanner/export 之间复用
    // 写通道仅 INSERT 使用
    // 读仲裁: scanner > export
    assign m_axi_araddr  = s_scan_arvalid ? s_scan_araddr : s_export_araddr;
    assign m_axi_arvalid = s_scan_arvalid | s_export_arvalid;
    assign s_scan_arready  = m_axi_arready && s_scan_arvalid;
    assign s_export_arready = m_axi_arready && !s_scan_arvalid && s_export_arvalid;

    assign s_scan_rdata  = m_axi_rdata;
    assign s_scan_rvalid = m_axi_rvalid && s_scan_arvalid;
    assign s_export_rdata  = m_axi_rdata;
    assign s_export_rvalid = m_axi_rvalid && !s_scan_arvalid;

    assign m_axi_rready = s_scan_arvalid ? s_scan_rready : s_export_rready;

    // 写通道直通
    assign m_axi_awaddr  = s_insert_awaddr;
    assign m_axi_awvalid = s_insert_awvalid;
    assign s_insert_awready = m_axi_awready;
    assign m_axi_wdata   = s_insert_wdata;
    assign m_axi_wvalid  = s_insert_wvalid;
    assign s_insert_wready = m_axi_wready;

endmodule
```

- [ ] **Step 2: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ddr4_arbiter.sv
git commit -m "feat: add ddr4_arbiter with priority-based arbitration"
```

---

## Phase 2: FPGA 核心模块 (TDD)

### Task 5: index_manager

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/index_manager.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_index_manager.py`

**依赖:** ddr4_arbiter, search_engine_pkg

- [ ] **Step 1: 写测试 — A/B 区切换**

```python
# sim/test_index_manager.py
@cocotb.test()
async def test_ab_zone_switch(dut):
    """Verify A→B→A zone switching"""
    # 1. 初始状态: active_zone = A
    assert dut.o_active_zone.value == 0  # A=0

    # 2. 发起切换
    dut.i_reindex_req.value = 1
    await RisingEdge(dut.clk)
    dut.i_reindex_req.value = 0
    await ClockCycles(dut.clk, 5)

    # 3. 验证切换完成
    assert dut.o_active_zone.value == 1  # B=1
    assert dut.o_switch_done.value == 1

@cocotb.test()
async def test_insert_pending_buffer(dut):
    """INSERT writes to standby zone tail, counter increments"""
    initial_count = int(dut.o_pending_count.value)
    # Simulate one INSERT
    dut.i_insert_valid.value = 1
    dut.i_insert_vector.value = ... # 512b vector data
    await RisingEdge(dut.clk)
    dut.i_insert_valid.value = 0
    await ClockCycles(dut.clk, 5)
    assert int(dut.o_pending_count.value) == initial_count + 1

@cocotb.test()
async def test_pending_buffer_full(dut):
    """When standby zone tail meets zone end, return error"""
    # Fill zone to near-end
    dut.i_pending_addr.value = 0x7FFF_FFE0  # near 2GB
    dut.i_insert_valid.value = 1
    await RisingEdge(dut.clk)
    dut.i_insert_valid.value = 0
    await ClockCycles(dut.clk, 3)
    assert dut.o_insert_error.value == 1  # overflow
```

- [ ] **Step 2-5: 实现 index_manager、验证、扩写测试、提交**

```systemverilog
// index_manager.sv — 索引元数据 + A/B 双区管理 + INSERT 处理
module index_manager #(
    parameter NCLUSTERS = 1024
) (
    input  wire         clk,
    input  wire         rst,

    // === 索引元数据接口 ===
    input  wire         i_reindex_req,
    output wire         o_switch_done,
    output wire         o_active_zone,       // 0=A, 1=B

    // 簇表: 每簇的基址和大小 (A/B 各用一份)
    output wire [31:0]  o_cluster_base [0:NCLUSTERS-1],
    output wire [15:0]  o_cluster_size [0:NCLUSTERS-1],

    // 批量更新簇表 (REINDEX 灌入时)
    input  wire         i_cluster_update_valid,
    input  wire [9:0]   i_cluster_update_idx,
    input  wire [31:0]  i_cluster_update_base,
    input  wire [15:0]  i_cluster_update_size,

    // === INSERT 处理 ===
    input  wire         i_insert_valid,
    input  wire [511:0] i_insert_vector,
    output wire         i_insert_ready,     // 背压
    output wire [31:0]  o_insert_wr_addr,   // DDR4 写地址 (从 B 区尾部)
    output wire [31:0]  o_pending_count,    // 待聚类向量计数
    output wire         o_insert_error,     // 缓冲区满

    // === 导出管理 ===
    input  wire         i_export_start,
    output wire [31:0]  o_export_base,
    output wire [31:0]  o_export_len
);
    // 活跃区标志: A=0, B=1
    reg active_zone = 0;
    // B 区尾部写指针 (INSERT 用)
    reg [31:0] standby_tail;
    // 待聚类计数
    reg [31:0] pending_cnt;

    wire [31:0] standby_base = active_zone ? ZONE_A_BASE : ZONE_B_BASE;

    always @(posedge clk) begin
        if (rst) begin
            active_zone <= 0;
            standby_tail <= ZONE_B_BASE;  // B 区起始
            pending_cnt <= 0;
        end else begin
            if (i_reindex_req) begin
                active_zone <= ~active_zone;
                standby_tail <= active_zone ? ZONE_A_BASE : ZONE_B_BASE;
                pending_cnt <= 0;
            end

            if (i_insert_valid && (standby_tail + 64 < standby_base + ZONE_SIZE)) begin
                standby_tail <= standby_tail + 64;  // 512b = 64B per write
                pending_cnt <= pending_cnt + 1;
            end
        end
    end

    assign o_switch_done = 1'b1;  // 切换是组合逻辑, 立即完成
    assign o_active_zone = active_zone;
    assign o_insert_wr_addr = standby_tail;
    assign o_pending_count = pending_cnt;
    assign o_insert_error = (standby_tail + 64 >= standby_base + ZONE_SIZE);
    assign o_insert_ready = ~o_insert_error;

    // 簇表: URAM 实现 (1R1W, 1024×48bit)
    // (URAM 推断代码省略, ~30行)

    assign o_export_base = active_zone ? ZONE_A_BASE : ZONE_B_BASE;
    assign o_export_len  = ZONE_SIZE;  // 导出全量 + pending
endmodule
```

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/index_manager.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_index_manager.py
git commit -m "feat: add index_manager with A/B dual-zone and INSERT handling"
```

---

### Task 6: ann_coarse_search

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ann_coarse_search.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_ann_coarse_search.py`

**依赖:** distance_compute_unit, search_engine_pkg, index_manager

- [ ] **Step 1: 写测试 — NCLUSTERS=16 小规模验证**

```python
# sim/test_ann_coarse_search.py
@cocotb.test()
async def test_coarse_search_selects_nearest_clusters(dut):
    """16 clusters, verify top-P are selected correctly"""
    # Preload 16 cluster centers into URAM
    centers = np.random.randn(16, 256).astype(np.float32)
    for idx, c in enumerate(centers):
        dut.i_centroid_wr_en.value = 1
        dut.i_centroid_idx.value = idx
        # Write 256 floats to centroid URAM (8 cycles @ 32 floats/cycle)
        ...

    # Set P=3, send query
    query = np.random.randn(256).astype(np.float32)
    # Compute expected: distances to all 16 centers, pick top 3
    expected_distances = np.sum((centers - query) ** 2, axis=1)
    expected_top3 = np.argsort(expected_distances)[:3]

    # Start search
    dut.i_start.value = 1
    dut.i_query_vector = ...  # write query
    dut.i_probes.value = 3
    await RisingEdge(dut.clk)
    dut.i_start.value = 0

    # Wait for done
    while not dut.o_done.value:
        await RisingEdge(dut.clk)

    # Read results
    result_ids = [int(dut.o_cluster_id[i].value) for i in range(3)]
    assert sorted(result_ids) == sorted(expected_top3.tolist()), \
        f"Coarse search mismatch: {sorted(result_ids)} vs {sorted(expected_top3.tolist())}"
```

- [ ] **Step 2-5: 实现、验证、扩写 (P=1, P=8, P=NCLUSTERS)、提交**

```systemverilog
// ann_coarse_search.sv — IVF 粗筛: 查询 vs 聚类中心
module ann_coarse_search #(
    parameter NCLUSTERS = 1024,
    parameter MAX_PROBES = 8,
    parameter MAX_DIM = 1536
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         i_start,
    input  wire [10:0]  i_dim,
    input  wire [1:0]   i_metric,
    input  wire [3:0]   i_probes,          // P: 1-8

    // 查询向量 (从 cmd_dispatcher 直接过来)
    input  wire [511:0] i_query_chunk,
    input  wire         i_query_valid,
    output wire         o_query_ready,

    // 聚类中心 URAM 接口 (读)
    output wire [9:0]   o_uram_addr,
    input  wire [511:0] i_uram_rdata,      // 512b = 16 floats per centroid

    // DCU 接口
    output wire         o_dcu_start,
    output wire [511:0] o_dcu_vec_a,       // query vector (repeated)
    input  wire [511:0] i_dcu_vec_b,       // centroid data
    output wire         o_dcu_vec_b_ready,
    input  wire         i_dcu_valid,
    input  wire [31:0]  i_dcu_distance,

    // 结果
    output wire         o_done,
    output wire [9:0]   o_cluster_id [0:MAX_PROBES-1],
    output wire [31:0]  o_cluster_base [0:MAX_PROBES-1],
    output wire [15:0]  o_cluster_size [0:MAX_PROBES-1],
    output wire [3:0]   o_cluster_count
);
    // 状态机:
    // 1. 加载 query vector
    // 2. 遍历 NCLUSTERS 个中心, 每周期读 1 个, DCU 流水线算距离
    // 3. 用 P 个寄存器保存最小距离和对应簇 ID (硬件 top-P)
    //    (P≤8 时用寄存器文件比堆更简单)

    // Top-P 寄存器组
    reg [31:0] best_dist [0:MAX_PROBES-1];
    reg [9:0]  best_id   [0:MAX_PROBES-1];

    // 扫描状态
    reg [9:0]  center_idx;
    reg [2:0]  state;  // IDLE, SCAN, WAIT_DCU, DONE

    // ... 实现省略 (~150行状态机)
    // 关键: 对每个 center, feed DCU with query (i_dcu_vec_a) vs centroid (i_dcu_vec_b)
    //       等待 DCU 结果 (4 cycle latency), 比较并更新 best_regs
    //       P 路并行比较器判断是否替换 best_regs 中的某个
endmodule
```

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ann_coarse_search.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_ann_coarse_search.py
git commit -m "feat: add ann_coarse_search IVF coarse search engine"
```

---

### Task 7: ddr4_scanner

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ddr4_scanner.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_ddr4_scanner.py`

**依赖:** distance_compute_unit, topk_heap, ddr4_arbiter, index_manager

- [ ] **Step 1: 写测试 — 256 条向量的精确匹配**

```python
# sim/test_ddr4_scanner.py
@cocotb.test()
async def test_scanner_exact_topk(dut):
    """256 vectors, query=first vector, top-1 should be itself"""
    ...

@cocotb.test()
async def test_scanner_axi_addr_sequence(dut):
    """Verify AXI read addresses are sequential, no gaps, no repeats"""
    ...
```

- [ ] **Step 2-5: 实现、验证、提交**

```systemverilog
// ddr4_scanner.sv — 精排: 顺序扫描命中簇, 逐条计算距离, 维护 TopK
module ddr4_scanner #(
    parameter MAX_PROBES = 8,
    parameter MAX_TOPK = 256,
    parameter VEC_BYTES = 1024    // 256-dim float32 = 1024B
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         i_start,
    input  wire [10:0]  i_dim,
    input  wire [1:0]   i_metric,
    input  wire [7:0]   i_topk,

    // 簇列表 (来自 coarse_search)
    input  wire [9:0]   i_cluster_id [0:MAX_PROBES-1],
    input  wire [31:0]  i_cluster_base [0:MAX_PROBES-1],
    input  wire [15:0]  i_cluster_size [0:MAX_PROBES-1],
    input  wire [3:0]   i_cluster_count,

    // AXI 读 (→ ddr4_arbiter → MIG)
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    // DCU 接口
    output wire         o_dcu_start,
    output wire [511:0] o_dcu_vec_a,       // query vector
    input  wire [511:0] i_dcu_vec_b,       // DB vector (from DDR4)
    output wire         o_dcu_vec_b_ready,
    input  wire         i_dcu_valid,
    input  wire [31:0]  i_dcu_distance,

    // TopK 堆
    output wire         o_heap_push,
    output wire [31:0]  o_heap_distance,
    output wire [31:0]  o_heap_vector_id,

    // 结果
    output wire         o_done
);
    // 两重循环状态机:
    // 外层: 遍历簇 (cluster_idx)
    // 内层: 遍历簇内向量 (vec_idx)
    //   每向量: 发 AXI burst read (VEC_BYTES/64=16 beats per 256d vector)
    //          流水线送入 DCU
    //          DCU 结果 -> push to topk_heap

    reg [31:0] current_addr;
    reg [15:0] vec_remaining;   // 当前簇剩余向量数
    reg [15:0] beat_counter;    // 当前向量的 beat 计数
    reg [3:0]  cluster_idx;     // 当前处理的簇
    reg [31:0] global_vec_id;   // 全局向量 ID

    // 状态: IDLE, NEXT_VEC, READ_BEATS, FEED_DCU, WAIT_DIST, CHECK_DONE
    // ... 实现省略 (~200行)
endmodule
```

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/ddr4_scanner.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_ddr4_scanner.py
git commit -m "feat: add ddr4_scanner with streaming DDR4→DCU→TopK pipeline"
```

---

## Phase 3: FPGA 集成与网络对接

### Task 8: search_cmd_dispatcher

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/search_cmd_dispatcher.sv`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_cmd_dispatcher.py`

**依赖:** 所有 Phase 1-2 模块

- [ ] **Step 1: 写测试 — 全命令码回归**

```python
# sim/test_cmd_dispatcher.py
@cocotb.test()
async def test_search_command_parsing(dut):
    """SEARCH cmd → dispatcher output: query_vec, dim, topk, metric"""
    ...

@cocotb.test()
async def test_insert_command(dut):
    """INSERT cmd → dispatcher routes to index_manager"""
    ...

@cocotb.test()
async def test_status_response(dut):
    """GET_STATUS → STATUS_RESP with correct fields"""
    ...

@cocotb.test()
async def test_unknown_command(dut):
    """Unknown cmd code → ERR response"""
    ...

@cocotb.test()
async def test_malformed_packet(dut):
    """Truncated packet → ERR response"""
    ...
```

- [ ] **Step 2-5: 实现、验证、提交**

```systemverilog
// search_cmd_dispatcher.sv — UDP 命令解析 + 响应封装 + 延迟测量
module search_cmd_dispatcher #(
    parameter MAX_DIM = 1536
) (
    input  wire         clk,                // 333MHz
    input  wire         rst,

    // CDC 侧: 来自 udp:8001 (经 xpm_fifo_async)
    input  wire [511:0] s_axis_cmd_tdata,
    input  wire         s_axis_cmd_tvalid,
    output wire         s_axis_cmd_tready,
    output wire [511:0] m_axis_resp_tdata,
    output wire         m_axis_resp_tvalid,
    input  wire         m_axis_resp_tready,

    // → ann_coarse_search
    output wire         o_search_start,
    output wire [10:0]  o_search_dim,
    output wire [1:0]   o_search_metric,
    output wire [3:0]   o_search_probes,
    output wire [7:0]   o_search_topk,
    output wire [511:0] o_search_query [0:11],  // 最多 1536-dim = 12×512b chunks

    // ← ddr4_scanner results
    input  wire         i_scanner_done,
    input  wire [31:0]  i_result_dist [0:9],
    input  wire [31:0]  i_result_id   [0:9],

    // → index_manager
    output wire         o_insert_req,
    output wire [511:0] o_insert_data,
    output wire         o_reindex_req,
    output wire         o_export_req,

    // 延迟测量
    output wire [31:0]  o_cycle_counter_for_status
);
    // 命令解析状态机
    // 延迟: 收到 SEARCH 时记录 start_cycle, scanner_done 时计算 delta
    reg [31:0] search_start_cycle, search_end_cycle;
    reg [31:0] cycle_counter;

    always @(posedge clk) begin
        if (rst) cycle_counter <= 0;
        else cycle_counter <= cycle_counter + 1;
    end

    // ... 实现省略 (~250行)
endmodule
```

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/search_cmd_dispatcher.sv \
        cmac_usplus_0_ex.srcs/sim_1/new/test_cmd_dispatcher.py
git commit -m "feat: add search_cmd_dispatcher with full command parsing"
```

---

### Task 9: search_engine_top 集成

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sources_1/new/search_engine/search_engine_top.sv`

**依赖:** 所有子模块

- [ ] **Step 1: 实现顶层连线**

```systemverilog
// search_engine_top.sv — 搜索引擎顶层, 实例化所有子模块
module search_engine_top (
    // DDR4 接口
    input  wire         ddr4_ui_clk,
    input  wire         ddr4_ui_rst,
    // AXI to MIG
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,
    output wire [31:0]  m_axi_awaddr,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [511:0] m_axi_wdata,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // CDC 接口 (→/← CDC FIFOs)
    input  wire [511:0] s_axis_cmd_tdata,
    input  wire         s_axis_cmd_tvalid,
    output wire         s_axis_cmd_tready,
    output wire [511:0] m_axis_resp_tdata,
    output wire         m_axis_resp_tvalid,
    input  wire         m_axis_resp_tready,

    // 数据面
    input  wire [511:0] s_axis_data_tdata,
    input  wire         s_axis_data_tvalid,
    output wire         s_axis_data_tready,
    output wire [511:0] m_axis_data_tdata,
    output wire         m_axis_data_tvalid,
    input  wire         m_axis_data_tready,

    // 状态监控
    output wire [31:0]  status_monitor
);
    // ---- 子模块实例化 ----
    // ddr4_arbiter, index_manager, distance_compute_unit,
    // topk_heap, ann_coarse_search, ddr4_scanner, cmd_dispatcher

    // 内部互联信号 (省略详细连线, ~200行)
    // 关键: dcu 由 coarse 和 scanner 分时复用
    //       mux dcu inputs based on which module is active

    // ---- 延迟计数器 ----
    reg [31:0] cycle_counter = 0;
    always @(posedge ddr4_ui_clk)
        if (ddr4_ui_rst) cycle_counter <= 0;
        else cycle_counter <= cycle_counter + 1;

    assign status_monitor = cycle_counter;  // 简化: 实际应该是复合状态字段

endmodule
```

- [ ] **Step 2: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/search_engine/search_engine_top.sv
git commit -m "feat: add search_engine_top integration module"
```

---

### Task 10: 修改 rx_demux 新增 Ch4 (UDP:8002)

**Files:**
- Modify: `cmac_usplus_0_ex.srcs/sources_1/new/rx_demux.sv`

**依赖:** 现有工程代码

- [ ] **Step 1: 读取现有 rx_demux 代码**

```bash
# 先理解现有 Ch0-Ch3 的路由逻辑
```

- [ ] **Step 2: 在 rx_demux 中新增 Ch4**

在现有 `next_state_from_idle` 组合块中增加 Ch4 路由:

```systemverilog
// rx_demux.sv 修改: 新增 UDP:8002 数据面端口
// 现有:
//   Ch0: ARP   (ethertype 0x0806)
//   Ch1: ICMP  (IP proto 0x01)
//   Ch2: UDP:8000 (数据面旧端口, 保留兼容)
//   Ch3: UDP:8001 (控制面)
// 新增:
//   Ch4: UDP:8002 (数据面新端口, 批量数据传输)

// 在 UDP 端口比较逻辑中新增:
localparam UDP_PORT_DATA_8002 = 16'h1F42;  // 8002

// 在端口匹配 case 中:
if (udp_dst_port == UDP_PORT_DATA_8002) begin
    next_channel = CH4_DATA;
    ch4_tdata = axis_tdata;
    ch4_tvalid = 1'b1;
    ch4_tlast  = axis_tlast;
end
```

- [ ] **Step 3: 增加 Ch4 输出端口到 rx_demux 模块声明**

```systemverilog
// 新增端口:
output wire [511:0] m_axis_ch4_tdata,
output wire         m_axis_ch4_tvalid,
output wire         m_axis_ch4_tlast,
input  wire         m_axis_ch4_tready,
```

- [ ] **Step 4: 运行现有仿真回归 (确保不破坏原有功能)**

```bash
cd sim && make  # 预期: 83/83 仍然 PASS
```

- [ ] **Step 5: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sources_1/new/rx_demux.sv
git commit -m "feat: add Ch4 (UDP:8002) data plane port to rx_demux"
```

---

### Task 11: 集成仿真

**Files:**
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_search_engine_full.py`
- Create: `cmac_usplus_0_ex.srcs/sim_1/new/test_reindex_flow.py`

**依赖:** 所有 FPGA 模块

- [ ] **Step 1: 完整搜索链路测试**

```python
# sim/test_search_engine_full.py
@cocotb.test()
async def test_full_pipeline_1000_vectors(dut):
    """1000 random vectors, build IVF index, search 100 queries, measure recall"""
    # 1. Generate 1000 random 256-dim vectors
    # 2. k-means cluster (N=16 for test, not 1024)
    # 3. Load clusters into URAM, load vectors into DDR4 model
    # 4. Run 100 queries
    # 5. Compare FPGA results vs numpy brute-force
    # 6. Verify recall@10 >= 90%
    ...

@cocotb.test()
async def test_backpressure_recovery(dut):
    """Verify search pipeline recovers from backpressure stall"""
    ...

@cocotb.test()
async def test_concurrent_search_insert(dut):
    """SEARCH and INSERT arrive simultaneously, both succeed"""
    ...
```

- [ ] **Step 2: A/B 切换集成测试**

```python
# sim/test_reindex_flow.py
@cocotb.test()
async def test_reindex_preserves_search(dut):
    """Search in Zone A, reindex to Zone B, search continues uninterrupted"""
    ...

@cocotb.test()
async def test_switch_then_search_new_zone(dut):
    """After switch, new searches hit Zone B data correctly"""
    ...
```

- [ ] **Step 3: 运行全部仿真**

```bash
cd sim && make 2>&1 | grep -E "PASS|FAIL|Test"
# Expected: ALL PASS (new tests + regression)
```

- [ ] **Step 4: 提交**

```bash
git add cmac_usplus_0_ex.srcs/sim_1/new/test_search_engine_full.py \
        cmac_usplus_0_ex.srcs/sim_1/new/test_reindex_flow.py
git commit -m "test: add full-pipeline and reindex integration tests"
```

---

## Phase 4: PC 端软件

### Task 12: UDP 通信层 + 协议编解码

**Files:**
- Create: `pc/backend/requirements.txt`
- Create: `pc/backend/udp_client.py`
- Create: `pc/backend/protocol.py`

- [ ] **Step 1: 安装依赖**

```bash
cd pc/backend
pip install numpy scipy fastapi uvicorn
```

`requirements.txt`:
```
fastapi==0.115.0
uvicorn==0.30.0
numpy==2.1.0
faiss-cpu==1.9.0
```

- [ ] **Step 2: 实现协议编解码**

```python
# pc/backend/protocol.py
import struct
import numpy as np
from enum import IntEnum

class CmdCode(IntEnum):
    SEARCH = 0x01
    INSERT = 0x02
    BATCH_SEARCH = 0x03
    REINDEX = 0x04
    DELETE = 0x05
    GET_STATUS = 0x06
    EXPORT = 0x07
    COMMIT_SWITCH = 0x08

class Metric(IntEnum):
    L2 = 0
    COSINE = 1
    IP = 2

class DataType(IntEnum):
    FLOAT32 = 0
    FLOAT16 = 1
    INT8 = 2

def pack_header(cmd: CmdCode, seq: int, payload_len: int, flags: int = 0) -> bytes:
    return struct.pack('>BBHI', cmd, flags, seq, payload_len)

def unpack_header(data: bytes) -> tuple:
    cmd, flags, seq, plen = struct.unpack('>BBHI', data[:8])
    return CmdCode(cmd), flags, seq, plen

def pack_search_request(seq: int, vector: np.ndarray, dim: int,
                        topk: int = 10, metric: Metric = Metric.L2,
                        data_type: DataType = DataType.FLOAT32,
                        probes: int = 2) -> bytes:
    """Pack a SEARCH command with query vector"""
    header = pack_header(CmdCode.SEARCH, seq, 5 + len(vector.tobytes()))
    params = struct.pack('>HBBB', dim, metric, topk, data_type)
    probes_byte = struct.pack('B', probes)
    return header + params + probes_byte + vector.astype(np.float32).tobytes()

def parse_search_response(data: bytes) -> list:
    """Parse SEARCH response into list of (distance, vector_id)"""
    header = data[:8]
    payload = data[8:]
    topk = len(payload) // 8  # 4B distance + 4B id per result
    results = []
    for i in range(topk):
        dist = struct.unpack('>f', payload[i*8:i*8+4])[0]
        vid = struct.unpack('>I', payload[i*8+4:i*8+8])[0]
        results.append((dist, vid))
    return results

def pack_status_request(seq: int) -> bytes:
    return pack_header(CmdCode.GET_STATUS, seq, 0)

def parse_status_response(data: bytes) -> dict:
    """Parse STATUS_RESP into dictionary"""
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
```

- [ ] **Step 3: 实现 UDP 客户端**

```python
# pc/backend/udp_client.py
import socket
import time
import struct
from protocol import *

class FPGAVectorClient:
    """UDP client for FPGA Vector Search Appliance"""

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
        self._bind_data_port()

    def _bind_data_port(self):
        self.data_sock.bind(('', self.data_port))

    def _next_seq(self) -> int:
        self.seq = (self.seq + 1) & 0xFFFF
        return self.seq

    def search(self, query: np.ndarray, topk: int = 10,
               metric: Metric = Metric.L2, probes: int = 2) -> list:
        """Send SEARCH and return [(distance, vector_id), ...]"""
        seq = self._next_seq()
        dim = query.shape[0]
        request = pack_search_request(seq, query, dim, topk, metric, probes=probes)
        self.ctrl_sock.sendto(request, (self.fpga_ip, self.ctrl_port))

        t0 = time.perf_counter()
        response, _ = self.ctrl_sock.recvfrom(4096)
        elapsed = (time.perf_counter() - t0) * 1_000_000  # μs

        rsp_cmd, flags, rsp_seq, _ = unpack_header(response)
        if rsp_cmd != CmdCode.SEARCH + 0x80:
            raise RuntimeError(f"Unexpected response: {rsp_cmd}")
        if flags & 0x02:
            raise RuntimeError(f"FPGA returned error")

        results = parse_search_response(response)
        return results, elapsed

    def get_status(self) -> dict:
        """Get device status"""
        seq = self._next_seq()
        request = pack_status_request(seq)
        self.ctrl_sock.sendto(request, (self.fpga_ip, self.ctrl_port))
        response, _ = self.ctrl_sock.recvfrom(1024)
        return parse_status_response(response)

    def insert_vectors(self, vectors: np.ndarray) -> bool:
        """Insert vectors to pending buffer. vectors: (N, dim) float32"""
        seq = self._next_seq()
        n, dim = vectors.shape
        header = pack_header(CmdCode.INSERT, seq, 5 + vectors.nbytes)
        params = struct.pack('>HHB', n, dim, DataType.FLOAT32)
        request = header + params + vectors.astype(np.float32).tobytes()
        self.ctrl_sock.sendto(request, (self.fpga_ip, self.ctrl_port))
        response, _ = self.ctrl_sock.recvfrom(256)
        _, flags, _, _ = unpack_header(response)
        return (flags & 0x02) == 0  # no error

    def close(self):
        self.ctrl_sock.close()
        self.data_sock.close()
```

- [ ] **Step 4: 提交**

```bash
git add pc/backend/
git commit -m "feat: add PC-side UDP protocol layer and FPGA client"
```

---

### Task 13: FastAPI 后端

**Files:**
- Create: `pc/backend/main.py`
- Create: `pc/backend/kmeans_engine.py`

- [ ] **Step 1: 实现 k-means 引擎**

```python
# pc/backend/kmeans_engine.py
import numpy as np
import faiss

class KMeansEngine:
    """Offline k-means clustering using Faiss"""

    def __init__(self, nlist: int = 1024, dim: int = 256):
        self.nlist = nlist
        self.dim = dim

    def cluster(self, vectors: np.ndarray) -> dict:
        """
        vectors: (N, dim) float32
        Returns: {
            'centroids': (nlist, dim),
            'assignments': (N,) int — cluster id for each vector,
            'cluster_sizes': (nlist,) int,
        }
        """
        n, d = vectors.shape
        assert d == self.dim, f"Dimension mismatch: {d} vs {self.dim}"

        # Faiss k-means
        kmeans = faiss.Kmeans(d, self.nlist, niter=20, verbose=False)
        kmeans.train(vectors)

        centroids = kmeans.centroids  # (nlist, d)
        _, assignments = kmeans.index.search(vectors, 1)  # (N, 1)
        assignments = assignments.flatten()

        cluster_sizes = np.bincount(assignments, minlength=self.nlist)

        # Sort vectors by cluster assignment for contiguous DDR4 layout
        sort_idx = np.argsort(assignments)
        sorted_vectors = vectors[sort_idx]
        sorted_assignments = assignments[sort_idx]

        # Compute cluster base addresses (offsets in the sorted array)
        cluster_bases = np.zeros(self.nlist, dtype=np.int32)
        offset = 0
        for c in range(self.nlist):
            cluster_bases[c] = offset
            offset += cluster_sizes[c]

        return {
            'centroids': centroids,
            'assignments': sorted_assignments,
            'cluster_sizes': cluster_sizes,
            'cluster_bases': cluster_bases,
            'sorted_vectors': sorted_vectors,
        }

    def build_index_payload(self, cluster_result: dict) -> bytes:
        """Pack cluster metadata + sorted vectors into REINDEX payload"""
        # Format: [nlist(4B)][dim(4B)]
        #          for each cluster: base(4B) size(2B)
        #          [centroids raw float32]
        #          [sorted vectors raw float32]
        ...
        return payload

    def reconstruct_centroids(self, vectors: np.ndarray,
                               assignments: np.ndarray) -> np.ndarray:
        """Recompute centroids from current vectors and assignments"""
        centroids = np.zeros((self.nlist, self.dim), dtype=np.float32)
        for c in range(self.nlist):
            mask = assignments == c
            if mask.sum() > 0:
                centroids[c] = vectors[mask].mean(axis=0)
        return centroids
```

- [ ] **Step 2: 实现 FastAPI 服务**

```python
# pc/backend/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import numpy as np
import base64
from udp_client import FPGAVectorClient
from kmeans_engine import KMeansEngine

app = FastAPI(title="Vector Search Appliance API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"])

client = FPGAVectorClient(fpga_ip="192.168.1.10")
kmeans = KMeansEngine(nlist=1024, dim=256)

# ---- Request/Response Models ----
class SearchRequest(BaseModel):
    vector: list[float]
    topk: int = 10
    metric: str = "L2"
    probes: int = 2

class SearchResult(BaseModel):
    results: list[dict]      # [{distance, vector_id}, ...]
    latency_us: float

class DeviceStatus(BaseModel):
    total_vectors: int
    active_zone: str
    ddr4_used_mb: int
    avg_latency_us: int
    p99_latency_us: int
    qps: int
    temperature: int

# ---- API Endpoints ----
@app.post("/api/search", response_model=SearchResult)
async def search(req: SearchRequest):
    query = np.array(req.vector, dtype=np.float32)
    metric_map = {"L2": 0, "COSINE": 1, "IP": 2}
    results, latency = client.search(query, req.topk, metric_map[req.metric], req.probes)
    return SearchResult(
        results=[{"distance": float(d), "vector_id": int(vid)} for d, vid in results],
        latency_us=latency
    )

@app.get("/api/status", response_model=DeviceStatus)
async def get_status():
    s = client.get_status()
    return DeviceStatus(**s)

@app.post("/api/insert")
async def insert_vectors(vectors_b64: str, dim: int = 256):
    data = base64.b64decode(vectors_b64)
    vectors = np.frombuffer(data, dtype=np.float32).reshape(-1, dim)
    ok = client.insert_vectors(vectors)
    return {"success": ok, "count": vectors.shape[0]}

@app.post("/api/reindex")
async def trigger_reindex():
    """Trigger full reindex: export from FPGA → k-means → import back"""
    # 1. Send REINDEX command → FPGA exports all vectors
    # 2. Receive vectors via data port (UDP:8002)
    # 3. Run k-means
    # 4. Send new index to FPGA
    # 5. COMMIT_SWITCH
    ...
    return {"success": True}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

- [ ] **Step 3: 提交**

```bash
git add pc/backend/main.py pc/backend/kmeans_engine.py
git commit -m "feat: add FastAPI backend with search/insert/reindex endpoints"
```

---

### Task 14: Vue 管理面板

**Files:**
- Create: `pc/frontend/package.json`
- Create: `pc/frontend/vite.config.js`
- Create: `pc/frontend/src/main.js`
- Create: `pc/frontend/src/App.vue`
- Create: `pc/frontend/src/components/Dashboard.vue`
- Create: `pc/frontend/src/components/VectorBrowser.vue`
- Create: `pc/frontend/src/components/IndexManager.vue`
- Create: `pc/frontend/src/components/LatencyChart.vue`

- [ ] **Step 1: 初始化 Vue 项目**

```bash
cd pc/frontend
npm create vite@latest . -- --template vue
npm install echarts vue-echarts axios
```

- [ ] **Step 2: 实现 Dashboard 组件**

```vue
<!-- pc/frontend/src/components/Dashboard.vue -->
<template>
  <div class="dashboard">
    <div class="stat-cards">
      <div class="card">
        <h3>QPS</h3>
        <div class="value">{{ status.qps }}</div>
      </div>
      <div class="card">
        <h3>Avg Latency</h3>
        <div class="value">{{ status.avg_latency_us }} μs</div>
      </div>
      <div class="card">
        <h3>P99 Latency</h3>
        <div class="value">{{ status.p99_latency_us }} μs</div>
      </div>
      <div class="card">
        <h3>DDR4 Used</h3>
        <div class="value">{{ status.ddr4_used_mb }} MB</div>
      </div>
    </div>
    <v-chart :option="latencyChartOption" style="height:400px" />
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import VChart from 'vue-echarts'
import axios from 'axios'

const status = ref({})
const latencyHistory = ref([])
let timer = null

const latencyChartOption = computed(() => ({
  title: { text: 'Search Latency (Real-time)' },
  xAxis: { type: 'category', data: latencyHistory.value.map((_, i) => i) },
  yAxis: { type: 'value', name: 'μs' },
  series: [{
    data: latencyHistory.value,
    type: 'line',
    smooth: true,
    areaStyle: { opacity: 0.3 }
  }]
}))

onMounted(() => {
  timer = setInterval(async () => {
    const { data } = await axios.get('/api/status')
    status.value = data
    latencyHistory.value.push(data.avg_latency_us)
    if (latencyHistory.value.length > 100)
      latencyHistory.value.shift()
  }, 1000)
})

onUnmounted(() => clearInterval(timer))
</script>
```

- [ ] **Step 3: 实现 VectorBrowser 组件**

```vue
<!-- pc/frontend/src/components/VectorBrowser.vue -->
<template>
  <div class="vector-browser">
    <textarea v-model="queryStr" placeholder="Enter query vector (comma-separated)..."></textarea>
    <button @click="doSearch">Search</button>
    <table v-if="results.length">
      <tr v-for="r in results" :key="r.vector_id">
        <td class="dist">{{ r.distance.toFixed(4) }}</td>
        <td>{{ r.vector_id }}</td>
      </tr>
    </table>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import axios from 'axios'

const queryStr = ref('')
const results = ref([])
const latency = ref(0)

async function doSearch() {
  const vector = queryStr.value.split(',').map(Number)
  const { data } = await axios.post('/api/search', { vector, topk: 10 })
  results.value = data.results
  latency.value = data.latency_us
}
</script>
```

- [ ] **Step 4: 实现 IndexManager 和 LatencyChart (省略, 类似模式)**

- [ ] **Step 5: 提交**

```bash
git add pc/frontend/
git commit -m "feat: add Vue3 management dashboard with real-time monitoring"
```

---

## Phase 5: 实验与论文数据

### Task 15: 实验脚本

**Files:**
- Create: `pc/experiments/generate_dataset.py`
- Create: `pc/experiments/bench_fpga.py`
- Create: `pc/experiments/bench_cpu_faiss.py`
- Create: `pc/experiments/plot_results.py`

- [ ] **Step 1: 数据集生成**

```python
# pc/experiments/generate_dataset.py
import numpy as np

def generate_synthetic_dataset(n_vectors: int, dim: int, seed: int = 42):
    """Generate random vectors + queries for benchmarking"""
    rng = np.random.default_rng(seed)
    vectors = rng.normal(0, 1, (n_vectors, dim)).astype(np.float32)
    queries = rng.normal(0, 1, (1000, dim)).astype(np.float32)
    return vectors, queries

def generate_clustered_dataset(n_vectors: int, dim: int, n_clusters: int = 50):
    """Generate clustered vectors for more realistic ANN testing"""
    # Each cluster center offset by 2-5x std
    # More realistic than pure random
    ...

# Generate multiple scales
for n in [10_000, 50_000, 100_000, 500_000, 1_000_000]:
    v, q = generate_synthetic_dataset(n, 256)
    np.save(f"data/vectors_{n//1000}K_256d.npy", v)
    np.save(f"data/queries_1K_256d.npy", q)
```

- [ ] **Step 2: FPGA 性能测试**

```python
# pc/experiments/bench_fpga.py
import numpy as np
import time
from backend.udp_client import FPGAVectorClient

def bench_fpga_latency(vectors_path: str, queries_path: str,
                        probes: int = 2, topk: int = 10):
    """Measure FPGA search latency over 1000 queries"""
    vectors = np.load(vectors_path)
    queries = np.load(queries_path)

    client = FPGAVectorClient()

    latencies = []
    for i, q in enumerate(queries):
        _, lat = client.search(q, topk=topk, probes=probes)
        latencies.append(lat)
        if i % 100 == 0:
            print(f"  {i}/{len(queries)}: p50={np.percentile(latencies, 50):.0f}μs")

    latencies = np.array(latencies)
    return {
        'p50': np.percentile(latencies, 50),
        'p99': np.percentile(latencies, 99),
        'mean': np.mean(latencies),
        'std': np.std(latencies),
        'min': np.min(latencies),
        'max': np.max(latencies),
    }

def bench_fpga_qps(vectors_path: str, queries_path: str, duration_s: int = 60):
    """Measure sustained QPS over 60 seconds"""
    ...

if __name__ == "__main__":
    import json
    scale = "1M"
    result = bench_fpga_latency(f"data/vectors_{scale}_256d.npy",
                                 f"data/queries_1K_256d.npy")
    print(json.dumps(result, indent=2))
    # Save result for plotting
    with open(f"results/fpga_{scale}.json", "w") as f:
        json.dump(result, f)
```

- [ ] **Step 3: CPU (Faiss) 对比测试**

```python
# pc/experiments/bench_cpu_faiss.py
import numpy as np
import faiss
import time

def bench_cpu_faiss(vectors_path: str, queries_path: str,
                     nlist: int = 1024, nprobe: int = 2, topk: int = 10):
    """Measure CPU Faiss IVF latency"""
    vectors = np.load(vectors_path)
    queries = np.load(queries_path)
    n, dim = vectors.shape

    # Build IVF index (same params as FPGA)
    quantizer = faiss.IndexFlatL2(dim)
    index = faiss.IndexIVFFlat(quantizer, dim, nlist)
    index.train(vectors)
    index.add(vectors)
    index.nprobe = nprobe

    # Warmup
    for _ in range(100):
        index.search(queries[:1], topk)

    # Benchmark
    latencies = []
    for i in range(len(queries)):
        q = queries[i:i+1]
        t0 = time.perf_counter()
        D, I = index.search(q, topk)
        t1 = time.perf_counter()
        latencies.append((t1 - t0) * 1_000_000)

    latencies = np.array(latencies)
    return {
        'p50': np.percentile(latencies, 50),
        'p99': np.percentile(latencies, 99),
        'mean': np.mean(latencies),
        'std': np.std(latencies),
    }

if __name__ == "__main__":
    import json
    scale = "1M"
    result = bench_cpu_faiss(f"data/vectors_{scale}_256d.npy",
                              f"data/queries_1K_256d.npy")
    print(json.dumps(result, indent=2))
    with open(f"results/cpu_faiss_{scale}.json", "w") as f:
        json.dump(result, f)
```

- [ ] **Step 4: 绘图脚本**

```python
# pc/experiments/plot_results.py
import matplotlib.pyplot as plt
import numpy as np
import json

def plot_latency_vs_scale(fpga_results: dict, cpu_results: dict):
    """Bar chart: FPGA vs CPU latency across data scales"""
    scales = ['10K', '50K', '100K', '500K', '1M']
    fpga_p50 = [fpga_results[s]['p50'] for s in scales]
    cpu_p50  = [cpu_results[s]['p50'] for s in scales]

    x = np.arange(len(scales))
    width = 0.35
    fig, ax = plt.subplots()
    ax.bar(x - width/2, fpga_p50, width, label='FPGA (P50)')
    ax.bar(x + width/2, cpu_p50, width, label='CPU Faiss (P50)')
    ax.set_xlabel('Dataset Size')
    ax.set_ylabel('Latency (μs)')
    ax.set_title('FPGA vs CPU: Search Latency by Dataset Size')
    ax.set_xticks(x, scales)
    ax.legend()
    plt.savefig('results/latency_vs_scale.png', dpi=150)

def plot_latency_distribution(fpga_lats: np.ndarray, cpu_lats: np.ndarray):
    """Histogram: latency distribution comparison"""
    fig, (ax1, ax2) = plt.subplots(1, 2)
    ax1.hist(fpga_lats, bins=50, alpha=0.7, label='FPGA')
    ax2.hist(cpu_lats, bins=50, alpha=0.7, label='CPU', color='orange')
    ax1.set_title(f'FPGA: σ={np.std(fpga_lats):.0f}μs')
    ax2.set_title(f'CPU: σ={np.std(cpu_lats):.0f}μs')
    plt.savefig('results/latency_distribution.png', dpi=150)

def plot_recall_vs_probes(fpga_recalls: dict):
    """Line chart: recall@10 vs nprobe (P=1,2,4,8)"""
    ...

def plot_qps_vs_batch(batch_results: dict):
    """Bar chart: QPS vs batch_size (1,4,16)"""
    ...
```

- [ ] **Step 5: 提交**

```bash
git add pc/experiments/
git commit -m "feat: add experiment scripts for FPGA vs CPU benchmarking"
```

---

## Phase 6: 上板验证与论文撰写

### Task 16: 综合与实现

- [ ] **Step 1: 综合检查**

```bash
# 在 Vivado 中
set_param general.maxThreads 8
open_project cmac_usplus_0_ex.xpr
add_files -norecurse cmac_usplus_0_ex.srcs/sources_1/new/search_engine/*.sv
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
# 预期: synth_design 无 ERROR, 检查 utilization 报告
```

- [ ] **Step 2: 实现 + 时序**

```bash
launch_runs impl_1 -jobs 8
wait_on_run impl_1
report_timing_summary -file reports/timing_impl.rpt
# 预期: WNS ≥ 0, WHS ≥ 0
```

- [ ] **Step 3: 生成 bitstream 并上板测试**

### Task 17: 论文撰写

- 引言: RAG 与向量检索背景, 现有方案局限
- 相关工作: Faiss/SCaNN/CPU-GPU 方案 vs FPGA 方案
- 系统设计: 本章设计规格
- 实验: Phase 4 数据 + 图表
- 结论与展望: 在线索引、更多距离度量、分布式扩展

---

## 时间线 (12 个月)

| 月份 | Phase | 内容 |
|------|------|------|
| 2026-06 | Phase 1 | 基础设施 (pkg, DCU, topk, arbiter) |
| 2026-07 | Phase 2 | 核心模块 (index, coarse, scanner) |
| 2026-08 | Phase 3 | 集成 + 网络对接 + 仿真回归 |
| 2026-09 | Phase 4 | PC 后端 + 前端 (AI 辅助加速) |
| 2026-10 | Phase 5 | 实验脚本 + 第一轮性能测试 |
| 2026-11~12 | Phase 6 | 上板验证 + 优化迭代 |
| 2027-01~02 | — | 论文初稿 + 第二轮实验 |
| 2027-03~04 | — | 论文打磨 + 答辩准备 |

---

**Plan complete.**
