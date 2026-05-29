# cocotb Makefile for FPGA ANN Vector Search Engine
# 用法（在 Vivado 命令行环境下运行）:
#   make SIM=xsim TOPLEVEL=distance_compute_unit MODULE=test_distance_compute
#   make SIM=xsim TOPLEVEL=topk_heap           MODULE=test_topk_heap
#   make SIM=xsim TOPLEVEL=ann_coarse_search    MODULE=test_ann_coarse_search
#   make SIM=xsim TOPLEVEL=ddr4_scanner         MODULE=test_ddr4_scanner
#   make SIM=xsim TOPLEVEL=index_manager        MODULE=test_index_manager
#   make SIM=xsim TOPLEVEL=search_cmd_dispatcher MODULE=test_cmd_dispatcher
#   make SIM=xsim TOPLEVEL=search_engine_top    MODULE=test_search_engine_full
#   make SIM=xsim TOPLEVEL=search_engine_top    MODULE=test_reindex_flow
#
# 前提条件:
#   1. 在 Vivado 命令行环境 (运行 settings64.bat 后)
#   2. pip install cocotb
#   3. 当前目录为 cmac_usplus_0_ex/cmac_usplus_0_ex.sim/

TOPLEVEL_LANG = verilog

# RTL 源文件 (相对于 sim 目录)
RTL_DIR   = ../cmac_usplus_0_ex.srcs/sources_1/new
SIM_DIR   = ../cmac_usplus_0_ex.srcs/sim_1/new

# 公共依赖
VERILOG_SOURCES  = $(RTL_DIR)/search_engine_pkg.sv

# 各模块的额外依赖 — 通过 TOPLEVEL 自动选择
ifeq ($(TOPLEVEL),distance_compute_unit)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/distance_compute_unit.sv
endif

ifeq ($(TOPLEVEL),topk_heap)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/topk_heap.sv
endif

ifeq ($(TOPLEVEL),ann_coarse_search)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/distance_compute_unit.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/ann_coarse_search.sv
endif

ifeq ($(TOPLEVEL),ddr4_scanner)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/ddr4_scanner.sv
endif

ifeq ($(TOPLEVEL),index_manager)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/index_manager.sv
endif

ifeq ($(TOPLEVEL),search_cmd_dispatcher)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/search_cmd_dispatcher.sv
endif

ifeq ($(TOPLEVEL),search_engine_top)
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/distance_compute_unit.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/topk_heap.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/ddr4_arbiter.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/index_manager.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/ann_coarse_search.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/ddr4_scanner.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/search_cmd_dispatcher.sv
  VERILOG_SOURCES += $(RTL_DIR)/search_engine/search_engine_top.sv
endif

# cocotb 标准 include
include $(shell cocotb-config --makefiles)/Makefile.sim

# 快捷目标: 跑全部模块级测试
.PHONY: test-all test-dcu test-heap test-coarse test-scanner test-index test-cmd

test-dcu:
	$(MAKE) SIM=xsim TOPLEVEL=distance_compute_unit MODULE=test_distance_compute

test-heap:
	$(MAKE) SIM=xsim TOPLEVEL=topk_heap MODULE=test_topk_heap

test-coarse:
	$(MAKE) SIM=xsim TOPLEVEL=ann_coarse_search MODULE=test_ann_coarse_search

test-scanner:
	$(MAKE) SIM=xsim TOPLEVEL=ddr4_scanner MODULE=test_ddr4_scanner

test-index:
	$(MAKE) SIM=xsim TOPLEVEL=index_manager MODULE=test_index_manager

test-cmd:
	$(MAKE) SIM=xsim TOPLEVEL=search_cmd_dispatcher MODULE=test_cmd_dispatcher

test-full:
	$(MAKE) SIM=xsim TOPLEVEL=search_engine_top MODULE=test_search_engine_full

test-all: test-dcu test-heap test-coarse test-scanner test-index test-cmd
	@echo "===== ALL MODULE TESTS COMPLETE ====="
