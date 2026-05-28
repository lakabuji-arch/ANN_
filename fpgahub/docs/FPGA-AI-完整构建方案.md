# FPGA AI 辅助开发 — 完整构建方案

> 最后更新: 2026-05-26
> **状态: 5个Skills✅ / 模板✅ / 工具脚本✅ / Makefile✅**

每个方案标注来源，让你知道"这个做法是谁先用的"。

---

## 总览：三层工具体系（全部已交付）

```
┌─────────────────────────────────────────────────────────────┐
│                      你的 FPGA 项目                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 第1层: AGENTS.md (每工程一份)                  ✅已交付│   │
│  │   来源: impakt73/ai-rust-hw-dev + OpenHW CVA6         │   │
│  │   位置: templates/AGENTS.md + 工程根目录 AGENTS.md    │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 第2层: Skills (全局，跨工程复用)               ✅已交付│   │
│  │   来源: Superpowers + Google Gemini Skills            │   │
│  │   已完成5个: xpm-selector / vivado-tcl / timing-      │   │
│  │              closure / fpga-debug / axi-checklist     │   │
│  │   待构建: gt-config (GT收发器配置)              ⏳    │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 第3层: 外部工具链 (脚本 + Makefile)            ✅已交付│   │
│  │   来源: impakt73 (vcd-mcp) + CVA6 (Verible)           │   │
│  │        + DarkRISCV (Makefile) + ADI HDL (Tcl)         │   │
│  │   已交付: Makefile / run_synth.tcl / run_build.tcl    │   │
│  │          / vcd-mcp README                             │   │
│  │   待搭建: vcd-mcp 实际编译部署                  ⏳    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

# 第一部分: AGENTS.md 编写指南

## 1.1 来源

| 做法 | 来源项目 | 说明 |
|------|----------|------|
| AGENTS.md 文件本身 | `impakt73/ai-rust-hw-dev` | 首个公开的 FPGA 项目 AGENTS.md |
| 4 Agent 分工模式 | 同上 | FPGA Architect / Rust Verification / HW-SW Integration / AI Instruction |
| AI 使用政策 | `openhwgroup/cva6` (`CONTRIBUTING.md`) | "AI生成的代码必须人类审查"、"禁止自动化PR" |
| 编码风格指南 | `openhwgroup/cva6` → `lowRISC/style-guides` | SystemVerilog 编码规范 |
| 调试哲学 | `impakt73/ai-rust-hw-dev` | "不要抽象推理，用仿真数据说话" |
| PR 检查清单 | `impakt73/ai-rust-hw-dev` | cargo test + lint + 综合 全过 |
| Vivado Tcl 自动化 | `analogdevicesinc/hdl` | Makefile + Tcl 脚本驱动 Vivado |
| 项目目录结构 | `darklife/darkriscv` | src/ rtl/ sim/ boards/ 分层 |

## 1.2 完整模板

> ✅ 已写入: `fpgahub/templates/AGENTS.md`
> 用法: 每个新工程复制到根目录，改 3 行即可

```markdown
# AGENTS.md — AI 编码助手指南

> 本文件告诉 AI 如何在本工程中正确工作。
> 来源: impakt73/ai-rust-hw-dev (AGENTS.md 概念), OpenHW CVA6 (AI政策)

## 项目元信息

| 项 | 值 |
|----|-----|
| 器件 | [XCKU5P-FFVB676-2-I] |
| 工具 | [Vivado 2025.2] |
| 语言 | [Verilog / SystemVerilog] |
| 仿真 | [Vivado Simulator] |

## 时钟域

| 时钟名 | 频率 | 来源 | 用途 |
|--------|------|------|------|
| [clk_100m] | [100 MHz] | [外部晶振] | [系统主时钟] |

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

## 验证检查清单

> 来源: impakt73/ai-rust-hw-dev

声称"完成"前，以下必须全部通过:

- [ ] 综合通过 (`synth_design` 无 CRITICAL WARNING)
- [ ] 仿真通过 (testbench 打印 PASS)
- [ ] 时序收敛 (WNS ≥ 0, WHS ≥ 0)
- [ ] 新增信号有复位初值
- [ ] 跨域信号全部经过 CDC
- [ ] 新增异步时钟组已约束
- [ ] 代码 lint 通过

## 调试哲学

> 来源: impakt73/ai-rust-hw-dev (AGENTS.md)

- ❌ 永远不要靠抽象推理
- ✅ 永远用仿真数据说话 ($display)
- ✅ 先缩小范围，再二分法定位

## 目录结构

> 来源: darklife/darkriscv

```
├── src/            ← RTL 源码
├── sim/            ← Testbench
├── constraints/    ← 时序/引脚约束
├── scripts/        ← Tcl/Makefile
└── docs/           ← 设计文档
```

## 项目间复用模块

> 来源: pConst/basic_verilog

- `clk_rst_mgr.v` — 时钟缓冲 + 复位同步释放
- `sync_block.v` — CDC 单比特同步器
```

---

# 第二部分: Skills 分类与构建方案

## 2.1 Skills 生态来源

| 来源 | 学到什么 | 对你的意义 |
|------|----------|-----------|
| **Superpowers** (`obra/superpowers`) | 13 个通用开发 Skills (brainstorming, writing-plans, TDD, debugging, verification...) | **直接可用** — 覆盖所有非 FPGA 特定的开发流程 |
| **Google Gemini Skills** (`google-gemini/gemini-skills`) | Skills 发布/安装生态 (`npx skills add`, agentskills.io) | 你的 Skills 可以发布到同一个注册表 |
| **Vercel Skills CLI** | `npx skills add <repo>` 一键安装 | FPGA Skills 的分发方式 |
| **Context7 Skills CLI** | `npx ctx7 skills install <repo>` | 另一种安装方式 |

## 2.2 Skills 分类: 通用 vs FPGA 专用

```
全部 Skills
├── 通用开发流程 (Superpowers 提供，已有)
│   ├── brainstorming           ← 设计讨论
│   ├── writing-plans           ← 实现计划
│   ├── executing-plans         ← 执行计划
│   ├── subagent-driven-dev     ← 子Agent并行
│   ├── dispatching-parallel    ← 并行任务分发
│   ├── test-driven-development ← 先写测试
│   ├── systematic-debugging    ← 结构化调试
│   ├── verification-before-    ← 验证后再说"完成"
│   │   completion
│   ├── requesting-code-review  ← 请求审查
│   ├── receiving-code-review   ← 处理审查意见
│   ├── finishing-a-dev-branch  ← 合并/PR
│   ├── using-git-worktrees     ← 隔离工作区
│   ├── writing-skills          ← 创建新 Skill（元技能）
│   └── using-superpowers       ← AI 入口规则
│
└── FPGA 专用 Skills (5个已构建 ✅，1个待构建 ⏳)
    ├── xpm-selector            ← ✅ fpgahub/skills/xpm-selector/SKILL.md
    ├── vivado-tcl-scripting    ← ✅ fpgahub/skills/vivado-tcl-scripting/SKILL.md
    ├── timing-closure          ← ✅ fpgahub/skills/timing-closure/SKILL.md
    ├── fpga-debug              ← ✅ fpgahub/skills/fpga-debug/SKILL.md
    ├── axi-bus-checklist       ← ✅ fpgahub/skills/axi-bus-checklist/SKILL.md
    └── gt-config               ← ⏳ 待构建 (GT收发器配置)
```

## 2.3 每个 FPGA Skill 的构建方案

### Skill 1: `xpm-selector` — CDC/FIFO 原语选择器

**来源灵感**: Superpowers 的设计理念 + ADI HDL 和 JESD204B 工程中的实际 XPM 使用

**触发条件**: "跨时钟域" / "CDC" / "FIFO" / "跨域"

**Skill 内容**:

```markdown
---
name: xpm-selector
description: Use when choosing Xilinx XPM primitives for CDC or FIFO. 
             Helps select the correct xpm_cdc_* or xpm_fifo_* based on 
             signal type, clock relationship, and data width.
---

# XPM Primitives Selector

## Decision Tree

Ask the user ONE question at a time:

1. "What are you transferring across clock domains?"
   A) Single-bit control signal → xpm_cdc_single
   B) Multiple independent single-bit signals → xpm_cdc_array_single
   C) Multi-bit data bus → (next question)
   D) Multi-bit counter/pointer → xpm_cdc_gray
   E) Single-cycle pulse → xpm_cdc_pulse

2. (If multi-bit data bus) "How much latency can you tolerate?"
   A) Low latency (2-3 cycles) → xpm_cdc_handshake
   B) High throughput, latency-tolerant → xpm_fifo_async

3. "Is the signal a reset?"
   → xpm_cdc_sync_rst

## Parameter Guidelines

After selecting the primitive, recommend parameters:
- DEST_SYNC_FF: 4 (default), 2 for low-latency, 5+ for safety-critical
- RELATED_CLOCKS: 0 for async, 1 for same PLL/MMCM
- FIFO depth: calculate from burst + CDC inflight
```

**构建步骤**:
1. 用 `writing-skills` 技能创建 SKILL.md
2. 先写测试场景（没有这个 Skill 时 AI 的错误选择）
3. 写 Skill 内容堵住错误
4. 验证 AI 加载 Skill 后选型正确

---

### Skill 2: `vivado-tcl-scripting` — Vivado Tcl 自动化

**来源灵感**: `analogdevicesinc/hdl` 的 Makefile + Tcl 自动化

**触发条件**: "建 Vivado 工程" / "跑综合" / "生成 bitstream"

**Skill 内容**:

```markdown
---
name: vivado-tcl-scripting
description: Use when generating Vivado Tcl scripts for project creation,
             synthesis, implementation, or bitstream generation.
---

# Vivado Tcl Automation

## Command Templates

### Create Project
\`\`\`tcl
create_project <name> <dir> -part <part>
add_files -norecurse ./src/*.v
add_files -fileset constrs_1 ./constraints/*.xdc
set_property top <top_module> [current_fileset]
\`\`\`

### Run Synthesis (non-project mode)
\`\`\`tcl
read_verilog ./src/*.v
read_xdc ./constraints/*.xdc
synth_design -top <top> -part <part>
write_checkpoint -force post_synth.dcp
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
\`\`\`

## Checklist
- [ ] Part number matches target device
- [ ] All .v files added
- [ ] All .xdc files added
- [ ] Top module correctly set
- [ ] Non-project mode for CI (recommended)
```

---

### Skill 3: `timing-closure` — 时序收敛

**来源灵感**: `openhwgroup/cva6` (工业级时序要求) + `impakt73` (Fmax 优先)

**触发条件**: "时序违例" / "WNS" / "timing" / "setup violation"

**Skill 内容**:

```markdown
---
name: timing-closure
description: Use when analyzing timing reports and fixing setup/hold violations.
             Structured diagnosis → fix recommendations.
---

# Timing Closure

## Diagnosis Flow

1. "How many failing endpoints?" → If >100, check clock constraints first
2. "What's the WNS value?" → -0.050 = minor, -0.500 = serious, -3.000 = architecture problem
3. "What % is logic vs routing delay?" → >60% logic = add pipeline, >60% routing = check placement

## Fix Strategies (ordered by impact)

1. Add pipeline registers (most effective)
2. set_multicycle_path (only if same PLL/MMCM!)
3. Reduce fanout
4. Floorplanning constraints
5. Physical optimization (opt_design -retarget)

## Anti-Patterns
- ❌ set_false_path to hide real violations
- ❌ set_multicycle_path on async clocks
```

---

### Skill 4: `fpga-debug` — 硬件调试

**来源灵感**: `impakt73/ai-rust-hw-dev` 的调试哲学 (AGENTS.md line: "Never rely on abstract reasoning")

**触发条件**: "bug" / "不对" / "FAIL" / "违例"

**Skill 内容**:

```markdown
---
name: fpga-debug
description: Structured hardware debugging methodology. 
             Data-first, hypothesis-second. Never guess.
---

# FPGA Hardware Debugging

## The Iron Law
NO FIXES WITHOUT OBSERVED DATA FIRST.

## Process

Phase 1: Narrow Scope
  - Which module? → Comment out half, test again
  - Which signal? → Add $display() at boundaries

Phase 2: ILA Probe Strategy
  - Clock, reset, valid, data, state — minimum 5 signals
  - Trigger on error condition, not on every clock

Phase 3: Minimal Repro
  - Simplest test that still fails
  - Remove all unrelated modules

Phase 4: Fix + Verify
  - Change ONE thing
  - Re-run exact same test
  - Confirm fix didn't break other tests
```

---

### Skill 5: `axi-bus-checklist` — AXI 总线检查

**来源灵感**: CVA6 的 `CONTRIBUTING.md` 中严格的 CI 要求 + JESD204B 工程的 AXI 接口

**触发条件**: "AXI" / "s_axi" / "AXI4" / "总线"

**Skill 内容**:

```markdown
---
name: axi-bus-checklist
description: AXI4/AXI4-Lite/AXI4-Stream protocol compliance checklist
---

# AXI Protocol Checklist

## Write Channel
- [ ] AWVALID won't de-assert until AWREADY=1
- [ ] WVALID won't de-assert until WREADY=1
- [ ] BREADY asserted (or properly back-pressured)
- [ ] WSTRB matches data width

## Read Channel
- [ ] ARVALID won't de-assert until ARREADY=1
- [ ] RVALID only when data is ready
- [ ] RREADY properly handled

## AXI4-Stream
- [ ] TVALID won't de-assert until TREADY=1
- [ ] TLAST only on last beat of packet
- [ ] TKEEP valid on TLAST beat

## Common Bugs
- Driving input port with assign
- Forgetting to check BRESP/RRESP
- Not handling back-pressure (READY=0)
```

---

## 2.4 Skills 构建流程 (用 writing-skills)

> 来源: Superpowers `writing-skills` Skill (TDD 方法论应用于文档)

```
Step 1: 写"压力测试"（没有 Skill 时 AI 会怎么搞砸）
  例: 问 AI "跨时钟域传 16-bit 数据怎么选原语"
  观察: AI 可能建议 xpm_cdc_array_single（错误！）
  记录: AI 的合理化借口（"都是单比特所以用 array_single"）

Step 2: 写 Skill 文档（堵住这个错误）
  在 SKILL.md 中明确写:
    "多比特编码数据绝对不能用 array_single！
     array_single 的每个 bit 到达时间可能差 1 周期。
     多比特数据必须用 handshake 或 gray 或 async_fifo。"

Step 3: 重新测试（加载 Skill 后 AI 是否正确）
  再问同样的问题 → AI 应该正确推荐 xpm_cdc_handshake

Step 4: 迭代（找到新的漏洞 → 修补 → 再测）
```

## 2.5 Skills 文件存放位置

```
Windows:
  %USERPROFILE%\.claude\skills\
  %USERPROFILE%\.agents\skills\
  或 VS Code Copilot 内置位置

Linux/Mac:
  ~/.claude/skills/
  ~/.agents/skills/

项目级 (仅供该工程):
  <project>/.claude/skills/
```

## 2.6 Skills 分发方式

```
发布到 GitHub:
  1. 创建 repo: my-fpga-skills
  2. 推入 skills/*/SKILL.md 文件
  3. 其他人安装: npx skills add <user>/my-fpga-skills

或通过 agentskills.io 注册表发布
```

---

# 第三部分: 外部工具链

## 3.1 工具总览

| 工具 | 类型 | 来源项目 | 状态 | 优先级 |
|------|------|----------|:---:|:---:|
| **vcd-mcp** | MCP Server | `impakt73/ai-rust-hw-dev` | ✅ `C:\vcd-mcp\target\release\vcd-mcp.exe` | ⭐⭐⭐ |
| **Verible** | CLI linter | `openhwgroup/cva6` (via lowRISC) | ✅ | ⭐⭐⭐ |
| **Python + cocotb** | 验证框架 | `cocotb/cocotb` | ✅ | ⭐⭐ |
| **Makefile** | 构建 | `darklife/darkriscv` + `ADI HDL` | ✅ fpgahub/tools/scripts/Makefile | ⭐⭐⭐ |
| **run_synth.tcl** | Vivado 综合 | `ADI HDL` + AMD UG835 | ✅ fpgahub/tools/scripts/run_synth.tcl | ⭐⭐⭐ |
| **run_build.tcl** | Vivado 全流程 | `ADI HDL` + AMD UG835 | ✅ fpgahub/tools/scripts/run_build.tcl | ⭐⭐⭐ |
| **Verilator** | 仿真器 | `verilator/verilator` | ⏳ 待安装 (非必需) | ⭐ |

## 3.2 vcd-mcp — AI 分析波形

**来源**: `impakt73/ai-rust-hw-dev/vcd-mcp/`

**安装步骤**:

```bash
# 1. 编译 vcd-mcp (需要 Rust 工具链)
git clone https://github.com/impakt73/ai-rust-hw-dev
cd ai-rust-hw-dev/vcd-mcp
cargo build --release
# 二进制在: target/release/vcd-mcp

# 2. 配置到 VS Code Copilot 的 MCP settings
# .vscode/settings.json:
{
  "mcp.servers": {
    "vcd-mcp": {
      "command": "/path/to/target/release/vcd-mcp"
    }
  }
}
```

**使用效果**:

```
你: "为什么仿真 FAIL 了？"
AI 自动:
  → count_signal_edges("top.clk") → 5002 个周期
  → get_signal_summary("top.cpu.state") → 最后状态=0x8 (非法)
  → get_signal_values("top.cpu.pc", time=4990..5002)
  → "PC在4995跳到0xDEAD，状态机进非法状态0x8"
  → "根因: 跳转指令地址计算错了"
```

**vcd-mcp 的 6 个工具**:

| 工具 | 功能 |
|------|------|
| `inspect_vcd_header` | 读 VCD 文件元数据 (时间范围、模块列表) |
| `list_signals` | 列出所有信号名 |
| `get_signal_values` | 获取指定时刻/范围的信号值 |
| `get_file_info` | 文件大小、信号数量等 |
| `get_signal_summary` | 信号变化次数、首次/末次变化时间 |
| `count_signal_edges` | 计数信号边沿 (时钟周期计数等) |

## 3.3 Verible — SystemVerilog 格式化 + Lint

**来源**: lowRISC 开发，被 `openhwgroup/cva6` 采用为官方格式化工具

**安装**:

```bash
# 从源码编译或下载预编译二进制
# https://github.com/chipsalliance/verible/releases

# 使用
verible-verilog-format --inplace src/*.v    # 格式化
verible-verilog-lint src/*.v                # Lint 检查
```

**在 CI 中集成** (CVA6 的做法):

```bash
# 检查所有 RTL 文件是否格式化正确
verible-verilog-format --inplace $(git ls-tree -r HEAD --name-only | grep '\.sv$')
git diff --exit-code  # 如果有 diff 就报错
```

## 3.4 Verilator — 开源仿真 + Lint

**来源**: `verilator/verilator`，被 `impakt73/ai-rust-hw-dev` 和 `darklife/darkriscv` 使用

```bash
# 安装
sudo apt-get install verilator

# Lint (仅检查语法)
verilator --lint-only -Wall src/*.v

# 仿真 (生成 C++ 模型后编译运行)
verilator --cc top.v
make -C obj_dir -f Vtop.mk
./obj_dir/Vtop
```

## 3.5 cocotb — Python 写 Testbench

**来源**: `cocotb/cocotb` (GitHub 上最热门的 Python 验证框架)

```python
# 用 Python 代替 Verilog 写 testbench
import cocotb
from cocotb.triggers import RisingEdge

@cocotb.test()
async def test_spi_transfer(dut):
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # ... 发 SPI 数据、检查结果
    assert dut.miso.value == expected
```

> 优势: Python 的灵活性 + Verilog 仿真器的速度。适合复杂测试场景。

## 3.6 Makefile — 一键命令

**来源**: `darklife/darkriscv` (顶层 Makefile) + `analogdevicesinc/hdl` (Vivado Makefile)

```makefile
# 工程根目录 Makefile

# 仿真
sim:
	vivado -mode batch -source scripts/run_sim.tcl

# 综合
synth:
	vivado -mode batch -source scripts/run_synth.tcl

# 格式化
fmt:
	verible-verilog-format --inplace src/*.v

# Lint
lint:
	verible-verilog-lint src/*.v
	verilator --lint-only -Wall src/*.v

# 全流程
all: lint synth sim
	@echo "All checks passed"
```

---

# 第四部分: 完整工作流示例

## 4.1 开始一个新 FPGA 工程

```
第 0 步: 复制模板
  cp ~/templates/AGENTS.md ./AGENTS.md
  改 3 行: 器件、时钟、仿真工具

第 1 步: 需求分析
  用 brainstorming Skill
  产出: docs/superpowers/specs/YYYY-MM-DD-设计.md

第 2 步: 实现计划
  用 writing-plans Skill
  产出: docs/superpowers/plans/YYYY-MM-DD-计划.md

第 3 步: 编码实现
  用 subagent-driven-development 或 executing-plans
  AI 自动按 AGENTS.md 的规范编码
  每 Task 自动跑验证清单

第 4 步: 代码审查
  用 requesting-code-review Skill
  子 Agent 独立审查

第 5 步: 完成合并
  用 finishing-a-development-branch Skill
  最后确认: 编译+仿真+时序 全通过
```

## 4.2 遇到 Bug 时

```
用 systematic-debugging Skill:
  ① 缩小范围 → ② $display 定位 → ③ 二分法 → ④ 修复

如果有 VCD 波形:
  用 vcd-mcp 让 AI 直接分析
```

---

# 第五部分: 你的定制化 todo

## 你现在可以做的

| 优先级 | 行动 | 状态 |
|:---:|------|:---:|
| 1 | 给 JESD204B 工程写 AGENTS.md | ✅ |
| 2 | 创建 FPGA Skills (5个) | ✅ |
| 3 | 创建 AGENTS.md 模板 | ✅ |
| 4 | 创建 Makefile + Tcl 脚本 | ✅ |
| 5 | 创建构建方案文档 | ✅ |
| 6 | 搭建 vcd-mcp | ✅ |
| 7 | 安装 Verible | ✅ |
| 8 | 安装 Python + cocotb | ✅ |
| 9 | 创建 gt-config Skill | ⏳ |
| 10 | 搭建 GitHub CI | ⏳ |
| 11 | 安装 Verilator (非必需) | ⏳ |

