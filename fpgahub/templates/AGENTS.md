# AGENTS.md — AI 编码助手指南

> 本文件告诉 AI 如何在本工程中正确工作。
> 来源: impakt73/ai-rust-hw-dev (AGENTS.md 概念), OpenHW CVA6 (AI政策)

## 项目元信息

| 项 | 值 |
|----|-----|
| 器件 | `<YOUR_PART>` (如 xcku5p-ffvb676-2-i) |
| 工具 | `<YOUR_TOOL>` (如 Vivado 2025.2 / Quartus / Yosys) |
| 语言 | `<YOUR_LANG>` (如 SystemVerilog / Verilog / VHDL) |
| 仿真 | cocotb (默认) / `<YOUR_SIM>` (备选) |

## 时钟域

| 时钟名 | 频率 | 来源 | 用途 |
|--------|------|------|------|
| `<YOUR_CLK_A>` | `<频率>` | `<来源>` | `<用途>` |
| `<YOUR_CLK_B>` | `<频率>` | `<来源>` | `<用途>` |
<!-- 每行一个时钟域，按实际情况填写 -->

## RTL 编码规范

> 编码风格参照: lowRISC/style-guides (被 OpenHW CVA6 采用)

### 复位风格
- 使用同步复位: `always @(posedge clk) if (rst) ...`
- 异步复位仅限外部输入边界，用 `xpm_cdc_sync_rst` 转同步
- 所有控制寄存器必须有复位初值
- 纯数据路径（有 valid 控制时）可以不复位

### 跨时钟域 (CDC)
- 单比特控制: `xpm_cdc_single` (2+级同步)
- 多比特数据: `xpm_cdc_handshake` 或 `xpm_fifo_async`
- 计数器/指针: `xpm_cdc_gray`
- 单周期脉冲: `xpm_cdc_pulse`
- **禁止**: 跨域信号无 CDC 直连
- **约束**: 所有异步时钟组在 `.xdc` 中声明 `set_clock_groups -asynchronous`

### 命名约定 (lowRISC 风格)
- 低有效: `_n` (如 `rst_n`)
- 时钟: `_clk`
- 复位: `_rst` / `_rst_n`
- AXI: `s_axi_*` / `m_axi_*`
- AXI-Stream: `s_axis_*` / `m_axis_*`

### 参数化 (CVA6 规范)
- 用 `parameter`，不用 `` `ifdef``
- 新功能默认 parameter=0 (关闭)

### Vivado 加速设置
- 综合/实现前始终添加: `set_param general.maxThreads 8`
- 来源: AMD 官方推荐 (UG835)

## 验证规范 (默认使用 cocotb)

> 来源: cocotb/cocotb (Python 验证框架)
> 规则: 默认使用 cocotb 写 testbench。仅当用户明确要求时才使用传统 Verilog testbench。

### cocotb testbench 模板
```python
# sim/test_<module>.py
import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_basic(dut):
    # 启动时钟
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    # 复位
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # 测试逻辑
    assert dut.output.value == expected, f"Expected {expected}, got {dut.output.value}"
```

### 传统 Verilog testbench (仅在用户明确要求时使用)
```verilog
// sim/my_module_tb.v
module my_module_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  // ...
endmodule
```

### 仿真层次
- **单元测试**: 每个模块有独立 testbench (`sim/test_<module>.py`)
- **集成测试**: 顶层 testbench 覆盖完整数据流 (`sim/test_top.py`)
- testbench **必须打印** `PASS` 或 `FAIL`
- testbench 必须**全自动**，不需要人工看波形判断

### 验证检查清单（声称"完成"前的硬性要求）
- [ ] 综合通过 (`synth_design` 无 CRITICAL WARNING)
- [ ] 仿真通过 (cocotb testbench 打印 PASS)
- [ ] 时序收敛 (WNS ≥ 0, WHS ≥ 0)
- [ ] 新增信号有复位初值
- [ ] 跨域信号全部经过 CDC
- [ ] 新增异步时钟组已约束
- [ ] Vivado 加速参数已设置: `set_param general.maxThreads 8`
- [ ] 代码 lint 通过

## AI 使用规则

> 来源: OpenHW CVA6 (CONTRIBUTING.md)

### ✅ 允许
- AI 辅助写代码、写 testbench、写约束
- AI 审查代码、分析报告
- AI 参与设计讨论

### ❌ 禁止
- AI 生成的代码不经人类审查直接提交
- 自动化 AI PR
- 让 AI 代替你和 reviewer 讨论
- 提交你自己不理解的代码

## 调试哲学

> 来源: impakt73/ai-rust-hw-dev (AGENTS.md)

- ❌ 永远不要靠抽象推理
- ✅ 永远用仿真数据说话
- ✅ 先缩小范围，再二分法定位

## 目录结构

> 来源: darklife/darkriscv

```
├── src/            ← RTL 源码
├── sim/            ← cocotb testbench (.py)
├── constraints/    ← 时序/引脚约束
├── scripts/        ← Tcl/Makefile
├── fpgahub/        ← AI 辅助开发工具
└── docs/           ← 设计文档
```
