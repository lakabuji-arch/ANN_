# 100G 向量检索引擎 (Vector Search Appliance) 设计规格

> 版本: v1.0 | 日期: 2026-05-28 | 状态: Ready for Review

## 概述

基于 XCKU5P FPGA 平台构建一台**独立向量搜索设备**，通过 100G 光纤与 PC 通信，对外提供 RAG 场景下的低延迟向量相似度检索服务。设备形态为独立盒子（光纤+电源），搭配 PC 端 Web 管理面板，实现 ANN 加速搜索、在线索引重建、以及完整的产品级服务闭环。

## 硬件平台

| 资源 | 数量 | 用途 |
|------|------|------|
| XCKU5P-FFVB676-2-I | 1 | FPGA 主芯片 |
| DSP Slices | 1,824 | 并行距离计算 |
| LUT | 217K | 控制逻辑、比较器、TopK 堆 |
| BRAM | 16.9 Mb | 流水线缓冲、FIFO |
| URAM | 18.0 Mb | 聚类中心存储 (1MB)、索引元数据 (16KB) |
| DDR4 (MT40A512M16LY ×2) | 2 GB @ 21 GB/s | 向量数据库存储 |
| GTY Transceivers | 16 × 32.75 Gbps | 100G 以太网 |
| 100G CMAC | — | 网络协议栈 (已就绪) |

## 系统架构

```
┌──────────────┐    100G 光纤     ┌─────────────────────────────┐
│     PC       │◄────────────────►│     FPGA 向量搜索设备       │
│              │  UDP:8001 控制面 │                             │
│  FastAPI     │  UDP:8002 数据面 │  ┌───────────────────────┐ │
│  Vue前端     │                  │  │  search_engine_top    │ │
│  k-means引擎 │                  │  │                       │ │
│  UDP通信层   │                  │  │  ┌──────┐ ┌────────┐ │ │
└──────────────┘                  │  │  │ ANN  │ │A/B双缓冲│ │ │
       ▲                          │  │  │ 搜索 │ │索引管理 │ │ │
       │ 浏览器访问                │  │  │ 引擎 │ └───┬────┘ │ │
  ┌────┴──────┐                   │  │  └──┬───┘     │      │ │
  │  浏览器    │                   │  │     │    ┌───┴───┐  │ │
  │  Web面板   │                   │  │     └────┤ DDR4  │  │ │
  └───────────┘                   │  │          │ 2GB   │  │ │
                                  │  │          └───────┘  │ │
                                  │  └───────────────────────┘ │
                                  └─────────────────────────────┘
```

### 关键设计决策

1. **双端口分离**：UDP:8001 控制面（命令/状态），UDP:8002 数据面（批量数据传输），避免 bulk 传输阻塞低延迟命令
2. **A/B 双缓冲索引**：DDR4 分 A/B 两个 1GB 区，搜索在活跃区服务时 PC 在待命区重建新索引，切换 <100μs
3. **复用现有网络栈**：直接复用 cmac_100g_wrapper 的 ARP/ICMP/UDP 处理，在 rx_demux 新增 Ch4 (UDP:8002)
4. **搜索模块单一时钟域**：全部搜索逻辑运行在 ddr4_ui_clk (333MHz)，避免跨域瓶颈

## 时钟域

| 时钟名 | 频率 | 来源 | 用途 |
|--------|------|------|------|
| usr_mac_clk | 322 MHz | CMAC IP | 网络协议栈 |
| c0_ddr4_ui_clk | 333 MHz | DDR4 MIG | 搜索引擎全部逻辑 |

新增搜索逻辑全部在 ddr4_ui_clk 下，与网络侧通过 xpm_fifo_async / xpm_cdc_pulse 跨域。不新增异步时钟组。

## FPGA 模块划分

```
search_engine_top (新模块, 333MHz ddr4_ui_clk)
│
├── search_cmd_dispatcher      ← 命令解析 + 响应封装
│   命令: SEARCH / BATCH_SEARCH / INSERT / REINDEX / GET_STATUS / EXPORT
│
├── ann_coarse_search           ← 粗筛：查询向量 vs URAM 聚类中心
│   DSP 距离计算阵列，输出 P 个命中簇的 DDR4 地址范围
│
├── ddr4_scanner                ← 精排：顺序扫描命中簇
│   逐条读 DDR4 → 流式距离计算 → TopK 堆更新
│
├── index_manager               ← 索引元数据 + A/B 双区管理
│   维护 URAM 中的簇表，处理 INSERT 追加、REINDEX 切换
│
├── distance_compute_unit       ← 可复用计算单元 (N_PARALLEL=64)
│   支持 L2 / 余弦 / 内积，coarse 和 scanner 分时共用
│
├── topk_heap                   ← TopK 最小堆 (默认 K=10)
│   维护 (score, vector_id) 对
│
└── ddr4_arbiter                ← DDR4 读写仲裁
    优先级: 搜索扫描 > INSERT 写入 > EXPORT 读出
```

### 一次 SEARCH 的数据流

```
UDP:8001 SEARCH 命令
  → cmd_dispatcher 解析 → 提取 query_vector, dim, topk, metric
  → ann_coarse_search 读 URAM → 1024 次距离计算 → 选 P 个簇 → 输出簇 ID 列表
  → ddr4_scanner 接手 → 逐个簇顺序读 DDR4 → 距离计算 → 喂 topk_heap
  → 扫描完成 → topk_heap 输出 TopK → cmd_dispatcher 打包响应 → UDP 回传
```

## UDP 命令协议

### 通用帧格式

| 偏移 | 长度 | 字段 |
|------|------|------|
| 0 | 1B | 命令码 (请求 0x01-0x7F, 响应 0x81-0xFF) |
| 1 | 1B | 标志位 (bit0=ACK, bit1=ERR, bit2=MORE) |
| 2 | 2B | 序号 (请求-响应匹配, big-endian) |
| 4 | 4B | Payload 长度 (big-endian) |
| 8 | N | Payload |

### 控制面命令 (UDP:8001)

| 命令码 | 名称 | Payload |
|--------|------|------|
| 0x01/0x81 | SEARCH | dim(2B) + metric(1B) + topk(1B) + data_type(1B) + query_vector |
| 0x02/0x82 | INSERT | vector_count(2B) + dim(2B) + data_type(1B) + vectors |
| 0x03/0x83 | BATCH_SEARCH | 同 SEARCH, 响应含 N 组结果 |
| 0x04/0x84 | REINDEX | A/B 切换指令 |
| 0x05/0x85 | DELETE | 向量 ID 列表 |
| 0x06/0x86 | GET_STATUS | 无 payload |
| 0x07/0x87 | EXPORT | 分批回传全量向量 (8002 配合大块传输) |

### 数据面 (UDP:8002)

纯向量流: float32/int8 数组 + 尾部 4B CRC32。控制在 8001 完成握手，数据在 8002 单向满带宽传输。

### 距离度量

| 值 | 度量 | 说明 |
|----|------|------|
| 0x00 | L2 | 欧几里得距离 |
| 0x01 | 余弦 | 归一化点积 |
| 0x02 | IP | 内积 (MIPS) |

### 数据类型

| 值 | 类型 | 字节/维度 |
|----|------|------|
| 0x00 | float32 | 4 |
| 0x01 | float16 | 2 |
| 0x02 | int8 | 1 |

## A/B 双缓冲在线索引重建

### DDR4 布局

```
0x0000_0000  区域 A (~1GB) — 搜索区，1024 个簇连续存放
0x4000_0000  区域 B (~1GB) — 重建区，结构对称
             INSERT 的新向量写入重建区尾部（重建区未使用时为空闲空间）
```

- 两个区域大小对称，各 ~1GB（实际按向量规模配置）
- 正常服务时：A 是活跃区（搜索读），B 为空闲区 + INSERT 新向量从 B 区尾部追加
- REINDEX 时：A 区全量 + B 区尾部新向量 → 导出 → PC 重新聚类 → 灌入 B 区从头开始写 → 切换后 B 变活跃区，A 变空闲区
- 硬件只维护两个基址寄存器 + 活跃区标志位，切换是改寄存器值

### REINDEX 流程

```
1. PC → FPGA: REINDEX 命令
2. FPGA: 标记"重建中"，搜索继续在活跃区服务
3. FPGA → PC: 导出 (活跃区全量 + 待聚类缓冲区新向量) via UDP:8002
4. PC: k-means 重新聚类 (1-5 秒)
5. PC → FPGA: 灌入新索引到待命区 via UDP:8002
6. PC → FPGA: COMMIT_SWITCH
7. FPGA: 原子切换，<100μs
8. FPGA → PC: SWITCH_DONE
```

### 搜索保证

- REINDEX 期间搜索正常服务（只读活跃区）
- 待聚类缓冲区的向量不可搜索（未聚类）
- INSERT 和 REINDEX 之间有时间窗口，新数据需等 REINDEX 完成才可见
- 有意的设计取舍：牺牲少量实时性，换搜索延迟确定性
- INSERT 速度限制：写满重建区尾部时返回错误，PC 侧需及时触发 REINDEX

## CDC 策略

| 通道 | 方向 | 信号类型 | CDC 原语 |
|------|------|------|------|
| 命令接收 | 322→333 | AXI-Stream (多比特) | xpm_fifo_async |
| 响应发送 | 333→322 | AXI-Stream (多比特) | xpm_fifo_async |
| 软复位/参数更新 | 322→333 | 单比特脉冲 | xpm_cdc_pulse |
| 状态回读 | 333→322 | 多比特寄存器 | xpm_cdc_array_single |

## 功能清单

### FPGA 硬件侧

| 分类 | 功能 | 说明 |
|------|------|------|
| 数据面 | ANN 向量搜索 | 单次 <1ms, IVF 两阶段 |
| | 暴力精确搜索 | 降级模式，100% recall |
| | 批量搜索 | 一次请求 N 个查询，共享粗筛 |
| 索引面 | 向量插入 | 实时写入待聚类区 |
| | 在线索引重建 | A/B 双缓冲，不停机 |
| | 索引状态查询 | 向量数、簇分布、水位 |
| | 索引导出 | 全量回传 PC |
| 管理面 | 系统监控 | DDR4 带宽、QPS、延迟 |
| | 参数在线调整 | P/nprobe、TopK、度量 |
| | 固件升级 | 预留远程 bitstream 加载 |

### PC 端软件

| 分类 | 功能 | 说明 |
|------|------|------|
| 通信层 | UDP 协议栈 | 100G 收发，超时重传 |
| | 连接管理 | 设备发现、心跳、断线重连 |
| 业务层 | 向量库管理 | 批量导入/导出 (numpy/hdf5/csv) |
| | k-means 引擎 | 离线聚类、索引灌入 |
| | 性能测试框架 | 自动化压测，延迟分布采集 |
| Web 面板 | 仪表盘 | 实时 QPS、延迟曲线、DDR4 水位 |
| | 向量浏览器 | 搜索/插入/结果可视化 |
| | 索引管理 | 簇分布可视化、触发重建 |
| | 一键演示 | 预设数据 + 预设查询 |

## 测试策略

### Phase 1 — 模块级仿真 (cocotb)

| 测试目标 | 测试文件 | 重点覆盖 |
|------|------|------|
| distance_compute_unit | test_distance_compute.py | L2/余弦/IP, dim=1~1024, 浮点精度 |
| topk_heap | test_topk_heap.py | 插入溢出, 全相同值, K=1~256 |
| ann_coarse_search | test_ann_coarse_search.py | P 个最近簇验证, P=1~1024 |
| ddr4_scanner | test_ddr4_scanner.py | AXI 地址序列, TopK 排序 |
| index_manager | test_index_manager.py | A/B 切换, INSERT 追加, 满缓冲区 |
| cmd_dispatcher | test_cmd_dispatcher.py | 全命令码回归, 畸变包处理 |

### Phase 2 — 集成仿真

| 测试目标 | 测试文件 | 重点覆盖 |
|------|------|------|
| 全链路搜索 | test_search_engine_full.py | 1000条向量, recall@10 vs numpy |
| 在线重建 | test_reindex_flow.py | A/B 切换完整性, 搜索不中断 |
| 数据面 | test_dataplane.py | 100MB 批量传输, CRC, 背压 |

### Phase 3 — 上板验证

| 测试项 | 通过标准 |
|------|------|
| 100G 链路 | ARP 应答正常 |
| UDP 命令 | SEARCH/INSERT/STATUS 回合正常 |
| 延迟基准 | 1万条 256 维, P50 <5ms |
| 召回率 | recall@10 ≥ 90% (P=2) |
| 稳定性 | 1 小时 100 QPS 无超时 |
| A/B 切换 | 搜索不中断 |
| 功耗 | <15W |

### Phase 4 — 实验数据

1. 延迟 vs 数据量 (1万/5万/10万/50万/100万条)
2. 召回率 vs 探测数 (P=1/2/4/8)
3. QPS vs 批量度 (batch=1/4/16)
4. FPGA vs CPU (Faiss-IVF 同等参数, 同数据集)
5. FPGA vs CPU 功耗
6. FPGA vs CPU 延迟分布 (P50/P99/标准差)

### CPU 对比方法

- 使用 Faiss (faiss-cpu), IndexIVFFlat, 相同参数 (nlist=1024, nprobe=2)
- 相同数据集和查询集
- CPU 选用云服务器 (Xeon Platinum / EPYC), 论文注明型号
- FPGA 端通过内部 cycle 计数器测延迟, 写入 STATUS_RESP 回传 PC
- 延迟分布采集 1000 次, 重点对比 P50/P99/标准差

## 文件清单

```
cmac_usplus_0_ex/
├── src/
│   ├── search_engine/
│   │   ├── search_engine_top.sv
│   │   ├── search_cmd_dispatcher.sv
│   │   ├── ann_coarse_search.sv
│   │   ├── ddr4_scanner.sv
│   │   ├── index_manager.sv
│   │   ├── distance_compute_unit.sv
│   │   ├── topk_heap.sv
│   │   └── ddr4_arbiter.sv
│   └── (现有 RTL, 仅 rx_demux 新增 Ch4)
├── sim/
│   ├── test_distance_compute.py
│   ├── test_topk_heap.py
│   ├── test_ann_coarse_search.py
│   ├── test_ddr4_scanner.py
│   ├── test_index_manager.py
│   ├── test_cmd_dispatcher.py
│   ├── test_search_engine_full.py
│   ├── test_reindex_flow.py
│   └── test_dataplane.py
├── pc/
│   ├── backend/              ← FastAPI + UDP 通信层
│   ├── frontend/             ← Vue 管理面板
│   └── experiments/          ← 实验脚本
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-05-28-vector-search-appliance-design.md
```

## 设计参数汇总

| 参数 | 默认值 | 说明 |
|------|------|------|
| 聚类数 (nlist) | 1024 | k-means 簇数量 |
| 探测簇数 (nprobe/P) | 2 | 每次搜索扫描的簇数 |
| TopK (K) | 10 | 返回最近邻数量 |
| 默认维度 | 256 | 向量维度, 可参数化至 1536 |
| 默认数据类型 | float32 | 可切换 float16/int8 |
| 距离度量 | L2 | 可切换余弦/IP |
| 距离计算并行度 | 64 | 每周期并行计算 64 维 |
| DDR4 A 区 | ~1 GB | 活跃搜索区 |
| DDR4 B 区 | ~1 GB | 重建区 + INSERT 暂存 (复用空闲空间) |
| A/B 切换时间 | <100 μs | 原子切换 |
| 目标搜索延迟 | <1 ms | 百万级向量, P=2 |
| 目标功耗 | <15 W | 整板 |
