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
