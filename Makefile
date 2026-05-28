# FPGA 开发自动化 Makefile — CMAC_DDR4 工程
# 来源: darklife/darkriscv + ADI HDL + fpga-ai-toolkit

PROJECT  := cmac_usplus_0_ex
TOP      := fpga_top_100g
PART     := xcku5p-ffvb676-2-i
JOBS     := 8

XPR      := cmac_usplus_0_ex.xpr
SRC_DIR  := cmac_usplus_0_ex.srcs/sources_1/new
SIM_DIR  := cmac_usplus_0_ex.srcs/sim_1/new
CONS_DIR := cmac_usplus_0_ex.srcs/constrs_1/new
OUT_DIR  := output
RPT_DIR  := reports

# 工具路径
VERIBLE  := C:/verible/verible-v0.0-4053-g89d4d98a-win64

# ============================================================
# 代码检查
# ============================================================
.PHONY: lint
lint:
	@echo "Running Verible lint..."
	$(VERIBLE)/verible-verilog-lint.exe $(SRC_DIR)/*.sv

.PHONY: format
format:
	@echo "Formatting with Verible..."
	$(VERIBLE)/verible-verilog-format.exe --inplace $(SRC_DIR)/*.sv

# ============================================================
# 仿真 (xsim, project mode)
# ============================================================
.PHONY: sim
sim:
	@echo "Running xsim simulation..."
	vivado -mode batch -source scripts/run_sim.tcl

# ============================================================
# 综合 (project mode, 利用现有工程)
# ============================================================
.PHONY: synth
synth:
	@echo "Running synthesis..."
	vivado -mode batch -source scripts/run_synth.tcl

# ============================================================
# 全流程 (综合 + 实现 + bitstream)
# ============================================================
.PHONY: build
build:
	vivado -mode batch -source scripts/run_build.tcl

# ============================================================
# 清理
# ============================================================
.PHONY: clean
clean:
	rm -rf *.jou *.log *.str .Xil
	rm -rf $(OUT_DIR) $(RPT_DIR)
	rm -rf vivado_*.str vivado_*.log
