# VCD MCP 安装与配置指南

> 来源: impakt73/ai-rust-hw-dev/vcd-mcp/

## 概述

VCD MCP 是一个 MCP (Model Context Protocol) 服务器，让 AI 直接读取和分析 VCD (Value Change Dump) 仿真波形文件。

## 安装

### 前置条件
```bash
# 需要 Rust 工具链 + MinGW (Windows)
# 1. 安装 Rust: https://rustup.rs/
# 2. 安装 MinGW: winget install MSYS2.MSYS2
#    MSYS2终端运行: pacman -S mingw-w64-x86_64-gcc
# 3. 切换到GNU工具链: rustup default stable-x86_64-pc-windows-gnu
```

### 编译
```bash
git clone https://github.com/impakt73/ai-rust-hw-dev.git
cd ai-rust-hw-dev/vcd-mcp
cargo build --release
# 二进制在: ./target/release/vcd-mcp.exe (Windows)
```

> 本机已安装路径: `C:\vcd-mcp\target\release\vcd-mcp.exe`

## 配置到 VS Code Copilot

在 `.vscode/settings.json` 中添加:

```json
{
  "mcp.servers": {
    "vcd-mcp": {
      "command": "C:/vcd-mcp/target/release/vcd-mcp.exe"
    }
  }
}
```

## 6 个工具

| 工具 | 功能 | 示例用法 |
|------|------|----------|
| `inspect_vcd_header` | 读 VCD 元数据 | "这个仿真有多长时间？" |
| `list_signals` | 列出所有信号 | "cpu 模块里有哪些信号？" |
| `get_signal_values` | 获取信号值 | "top.pc 在时刻 1000 的值？" |
| `get_file_info` | 文件大小/时间范围 | "波形文件有多大？" |
| `get_signal_summary` | 变化次数统计 | "instr_complete 翻转了多少次？" |
| `count_signal_edges` | 边沿计数 | "clk 有多少个上升沿？" |

## 使用示例

```
你: "为什么仿真 FAIL 了？"
AI: 
  → count_signal_edges("top.clk") → 5002 个周期
  → get_signal_summary("top.state") → 最后状态=0x8 (非法)
  → get_signal_values("top.pc", 4990..5002)
  → "PC=0xDEAD时进入非法状态"

你: "top.valid 信号总共拉高了多久？"
AI:
  → get_signal_summary("top.valid") 
  → "共 847 次变化"
  → count_signal_edges("top.valid", "rising") 
  → "423 次上升沿 (valid 拉高了 423 次)"
```
