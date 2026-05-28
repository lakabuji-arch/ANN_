# FPGA 开发自动化 Makefile

> 来源: darklife/darkriscv (顶层Makefile) + analogdevicesinc/hdl (Vivado自动化)

# ============================================================
# 工程名称 (每个新工程修改这里)
# ============================================================
PROJECT  ?= <your_project_name>
TOP      ?= <top_module_name>
PART     ?= <part_number>
JOBS     := 8

# ============================================================
# 路径
# ============================================================
SRC_DIR  := src
SIM_DIR  := sim
OUT_DIR  := output
RPT_DIR  := reports

# 工具路径 (根据本机安装修改)
PYTHON   := $(LOCALAPPDATA)\Programs\Python\Python313\python.exe
VERIBLE  := C:\verible\verible-v0.0-4053-g89d4d98a-win64

# ============================================================
# 仿真 (cocotb — 默认)
# ============================================================
.PHONY: sim
sim:
	@echo "Running cocotb simulation..."
	cd $(SIM_DIR) && $(PYTHON) -m cocotb $(TOP)

# 传统 Verilog testbench (仅在明确要求时)
.PHONY: sim-verilog
sim-verilog:
	vivado -mode batch -source scripts/run_sim.tcl

# ============================================================
# 代码检查
# ============================================================
.PHONY: lint
lint:
	@echo "Running Verible lint..."
	$(VERIBLE)\verible-verilog-lint.exe $(SRC_DIR)/*.v

.PHONY: format
format:
	@echo "Formatting with Verible..."
	$(VERIBLE)\verible-verilog-format.exe --inplace $(SRC_DIR)/*.v

# ============================================================
# Vivado 综合 (non-project mode)
# ============================================================
.PHONY: synth
synth:
	@echo "Running synthesis ($(PART))..."
	@mkdir -p $(RPT_DIR)
	vivado -mode batch -nojournal -nolog -source scripts/run_synth.tcl \
	  -tclargs $(TOP) $(PART) $(RPT_DIR)

# ============================================================
# Vivado 全流程 (综合 + 实现 + bitstream)
# ============================================================
.PHONY: build
build:
	@echo "Building $(TOP) for $(PART)..."
	@mkdir -p $(OUT_DIR) $(RPT_DIR)
	vivado -mode batch -nojournal -nolog -source scripts/run_build.tcl \
	  -tclargs $(TOP) $(PART) $(OUT_DIR) $(RPT_DIR)

# ============================================================
# 时序报告
# ============================================================
.PHONY: timing
timing:
	@echo "Loading timing check..."
	vivado -mode batch -nojournal -nolog -source scripts/check_timing.tcl

# ============================================================
# 清理
# ============================================================
.PHONY: clean
clean:
	rm -rf *.jou *.log *.str .Xil
	rm -rf $(OUT_DIR) $(RPT_DIR)
	rm -rf vivado_*.str vivado_*.log
	rm -rf *.backup.jou *.backup.log
