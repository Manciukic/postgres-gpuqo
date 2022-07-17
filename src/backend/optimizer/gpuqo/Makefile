#-------------------------------------------------------------------------
#
# Makefile--
#    Makefile for the GPU query optimizer module
#
# src/backend/optimizer/gpuqo/Makefile
#
#-------------------------------------------------------------------------

subdir = src/backend/optimizer/gpuqo
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global

OBJS   = gpuqo_main.o 
NVOBJS = gpuqo_dpsize.o gpuqo_dpsub_common.o gpuqo_dpsub_unfiltered.o gpuqo_dpsub_filtered.o gpuqo_dpsub_csg.o gpuqo_dpsub_tree.o gpuqo_dpsub_bicc.o gpuqo_debug.o gpuqo_binomial.o gpuqo_cpu_sequential.o gpuqo_cpu_dpe.o gpuqo_dependency_buffer.o gpuqo_cpu_dpsize.o gpuqo_cpu_dpsub.o gpuqo_cpu_dpsub_bicc.o gpuqo_cpu_dpsub_parallel.o gpuqo_cpu_dpccp.o gpuqo_hashtable.o gpuqo_spanning_tree.o gpuqo_planner_info.o gpuqo_main_internal.o gpuqo_bfs_indexing.o gpuqo_remapper.o gpuqo_idp.o gpuqo_dpdp_union.o gpuqo_cpu_goo.o gpuqo_cpu_ikkbz.o gpuqo_cpu_linearized_dp.o gpuqo_cpu_dplin.o

# NVIDIA-specific code (do not edit)

NVLINK = dlink.o
OBJS += $(NVLINK)
OBJS += $(NVOBJS)

NVCC := $(cuda_path)/bin/nvcc
NVCCFLAGS ?= $(CPPFLAGS) 

NVCCFLAGS += -Wno-deprecated-gpu-targets  --forward-unknown-to-host-compiler
NVCCFLAGS += -I/scratch2/mageirak/KaHIP/interface
# from email
# NVCCFLAGS += -Wconversion  #???????

ifeq ($(enable_debug),yes)
NVCCFLAGS += -g -lineinfo
endif

ifneq (,$(findstring -O0,$(CFLAGS)))
    NVCCFLAGS += -O0
else ifneq (,$(findstring -O1,$(CFLAGS)))
    NVCCFLAGS += -O1
else ifneq (,$(findstring -O2,$(CFLAGS)))
    NVCCFLAGS += -O2
else ifneq (,$(findstring -O3,$(CFLAGS)))
    NVCCFLAGS += -O3
else
	NVCCFLAGS += -O2
endif

ifeq ($(enable_gpuqo_profiling),yes)
NVCCFLAGS += -DGPUQO_PROFILE
endif

ifeq ($(enable_gpuqo_kernel_profiling),yes)
NVCCFLAGS += -DGPUQO_KERNEL_PROFILE
endif

ifeq ($(enable_gpuqo_debug),yes)
NVCCFLAGS += -DGPUQO_DEBUG
endif

ifeq ($(disable_ccc),yes)
NVCCFLAGS += -DDISABLE_CCC
endif

ifeq ($(simulate_complex_cost_function),yes)
NVCCFLAGS += -DSIMULATE_COMPLEX_COST_FUNCTION
endif


ifeq ($(cost_function),postgres)
    NVCCFLAGS += -DGPUQO_COST_FUNCTION=0
else ifeq ($(cost_function),simple)
    NVCCFLAGS += -DGPUQO_COST_FUNCTION=1
else ifeq ($(cost_function),cout)
    NVCCFLAGS += -DGPUQO_COST_FUNCTION=2
endif

GENCODE_FLAGS = $(foreach sm, $(with_cudasm), -gencode arch=compute_$(sm),code=sm_$(sm))
BUILDDIR = $(top_builddir)/$(subdir)

$(NVLINK): $(NVOBJS)
	$(NVCC) $(NVCCFLAGS) $^ -o $@ $(GENCODE_FLAGS) -dlink

$(NVOBJS): %.o: %.cu
	$(NVCC) $(NVCCFLAGS) -dc $< -o $@ $(GENCODE_FLAGS) 


include $(top_srcdir)/src/backend/common.mk
