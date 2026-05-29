TOPLEVEL_LANG = verilog
RTL_DIR   = ../cmac_usplus_0_ex.srcs/sources_1/new
PKG       = $(RTL_DIR)/search_engine_pkg.sv
ENGINE    = $(RTL_DIR)/search_engine

VERILOG_SOURCES = $(PKG)

# Auto-include based on TOPLEVEL
ifeq ($(TOPLEVEL),distance_compute_unit)
  VERILOG_SOURCES += $(ENGINE)/distance_compute_unit.sv
endif
ifeq ($(TOPLEVEL),topk_heap)
  VERILOG_SOURCES += $(ENGINE)/topk_heap.sv
endif
ifeq ($(TOPLEVEL),ann_coarse_search)
  VERILOG_SOURCES += $(ENGINE)/distance_compute_unit.sv $(ENGINE)/ann_coarse_search.sv
endif
ifeq ($(TOPLEVEL),ddr4_scanner)
  VERILOG_SOURCES += $(ENGINE)/ddr4_scanner.sv
endif
ifeq ($(TOPLEVEL),index_manager)
  VERILOG_SOURCES += $(ENGINE)/index_manager.sv
endif
ifeq ($(TOPLEVEL),search_cmd_dispatcher)
  VERILOG_SOURCES += $(ENGINE)/search_cmd_dispatcher.sv
endif
ifeq ($(TOPLEVEL),search_engine_top)
  VERILOG_SOURCES += $(ENGINE)/distance_compute_unit.sv $(ENGINE)/topk_heap.sv \
                     $(ENGINE)/ddr4_arbiter.sv $(ENGINE)/index_manager.sv \
                     $(ENGINE)/ann_coarse_search.sv $(ENGINE)/ddr4_scanner.sv \
                     $(ENGINE)/search_cmd_dispatcher.sv $(ENGINE)/search_engine_top.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

test-dcu:    ; $(MAKE) SIM=xsim TOPLEVEL=distance_compute_unit  MODULE=test_distance_compute
test-heap:   ; $(MAKE) SIM=xsim TOPLEVEL=topk_heap             MODULE=test_topk_heap
test-coarse: ; $(MAKE) SIM=xsim TOPLEVEL=ann_coarse_search      MODULE=test_ann_coarse_search
test-scanner:; $(MAKE) SIM=xsim TOPLEVEL=ddr4_scanner           MODULE=test_ddr4_scanner
test-index:  ; $(MAKE) SIM=xsim TOPLEVEL=index_manager          MODULE=test_index_manager
test-cmd:    ; $(MAKE) SIM=xsim TOPLEVEL=search_cmd_dispatcher  MODULE=test_cmd_dispatcher

# Add test directory to Python path
export PYTHONPATH := $(PWD)/../cmac_usplus_0_ex.srcs/sim_1/new:$(PYTHONPATH)
