# FPGA AI 辅助开发工具集 (FPGAHub)

> 提炼自顶级 FPGA 开源项目：impakt73/ai-rust-hw-dev、OpenHW CVA6、darklife/darkriscv、analogdevicesinc/hdl、cocotb/cocotb

---

## 目录结构

```
fpgahub/
├── README.md                        ← 本文件
├── templates/
│   └── AGENTS.md                    ← 新工程模板 (AI行为宪法)
├── skills/                          ← FPGA 专用 Skills
│   ├── xpm-selector/SKILL.md        ← CDC/FIFO 原语选择器
│   ├── vivado-tcl-scripting/SKILL.md ← Vivado Tcl 自动化
│   ├── timing-closure/SKILL.md      ← 时序收敛诊断+修复
│   ├── fpga-debug/SKILL.md          ← 结构化硬件调试
│   └── axi-bus-checklist/SKILL.md   ← AXI 总线协议检查
└── tools/
    ├── vcd-mcp/README.md            ← AI 波形分析 (MCP)
    └── scripts/
        ├── Makefile                 ← 一键命令
        ├── run_synth.tcl            ← 综合脚本
        └── run_build.tcl            ← 全流程脚本
```

## 快速开始

### 1. 新工程初始化 (Windows)

```powershell
# 下载工具包到新工程
cd D:\my_new_project
git clone https://github.com/lakabuji-arch/fpga-ai-toolkit.git temp
Move-Item temp\fpgahub .\; Move-Item temp\AGENTS.md .\; Move-Item temp\.gitignore .\; Remove-Item -Recurse -Force temp
```

### 2. 填配置（改占位符）

> 所有需修改的位置都用 `<YOUR_...>` 或 `<your_...>` 标记，搜索即可找到。

| 文件 | 占位符 | 改成 |
|------|--------|------|
| `AGENTS.md` | `<YOUR_PART>` | 你的 FPGA 型号 |
| `AGENTS.md` | `<YOUR_TOOL>` | Vivado / Quartus 版本 |
| `AGENTS.md` | `<YOUR_CLK_A/B>` | 你的时钟列表 |
| `fpgahub\tools\scripts\Makefile` | `<your_project_name>` | 工程名 |
| `fpgahub\tools\scripts\Makefile` | `<top_module_name>` | 顶层模块名 |
| `fpgahub\tools\scripts\Makefile` | `<part_number>` | 器件编号 |

### 3. 安装 Skills（一次性，全局）

```powershell
Copy-Item -Recurse fpgahub\skills\* $env:USERPROFILE\.claude\skills\ -Force
```

### 3. 工具链配置

> ✅ 本机已安装以下工具，路径供参考：

| 工具 | 版本 | 路径 |
|------|------|------|
| Rust | 1.95.0 | `~/.cargo/bin` |
| MinGW GCC | 15.2.0 | `C:\msys64\mingw64\bin` |
| Python | 3.13.13 | `%LOCALAPPDATA%\Programs\Python\Python313` |
| cocotb | 2.0.1 | pip 全局 |
| Verible | v0.0-4053 | `C:\verible\verible-v0.0-4053-g89d4d98a-win64\` |
| vcd-mcp | — | `C:\vcd-mcp\target\release\vcd-mcp.exe` |

**新机安装**: 见 `docs/FPGA-AI-完整构建方案.md`

### 4. 日常命令

```bash
make format     # 格式化所有 RTL
make lint       # 代码检查
make sim        # 运行 cocotb 仿真
make synth      # 综合
make build      # 综合 + 实现 + bitstream
make timing     # 时序检查
```

## 来源标注

| 组件 | 灵感来源 |
|------|----------|
| AGENTS.md 模板 | impakt73/ai-rust-hw-dev + OpenHW CVA6 |
| 编码规范 | lowRISC/style-guides (CVA6 采用) |
| AI 使用政策 | OpenHW CVA6 (CONTRIBUTING.md) |
| 仿真验证 (cocotb) | cocotb/cocotb |
| 项目结构 | darklife/darkriscv |
| Vivado 自动化 | analogdevicesinc/hdl |
| Skills 设计方法 | Superpowers (obra/superpowers) |
| vcd-mcp | impakt73/ai-rust-hw-dev |
| Verible | chipsalliance/verible (lowRISC) |

## 核心原则

1. **AI 辅助，人类决策** — AI 写代码，人类审查和负责
2. **仿真优先，数据说话** — 不靠抽象推理，用 $display 和波形
3. **cocotb 默认** — Python testbench，除非明确要求才用 Verilog TB
4. **maxThreads 8** — 所有 Vivado 脚本默认多线程加速
5. **先设计，后实现** — brainstorming → writing-plans → TDD
6. **不验证，不完成** — 编译+仿真+时序 全过才算"完成"
