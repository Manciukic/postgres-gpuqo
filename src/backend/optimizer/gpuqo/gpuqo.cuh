/*-------------------------------------------------------------------------
 *
 * gpuqo.cuh
 *	  function prototypes and struct definitions for CUDA/Thrust code
 *
 * src/include/optimizer/gpuqo.cuh
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_CUH
#define GPUQO_CUH

#include <iostream>
#include "optimizer/gpuqo_common.h"
#include "gpuqo_uninitalloc.cuh"
#include "gpuqo_planner_info.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_remapper.cuh"

#include "signal.h"
extern "C" void ProcessInterrupts(void);
extern "C" volatile sig_atomic_t InterruptPending;

#define CHECK_FOR_INTERRUPTS() \
do { \
	if (InterruptPending) \
		ProcessInterrupts(); \
} while(0)

// floating-point infinity constants
#include <limits>
#ifdef __CUDA_ARCH__
#define INFD __longlong_as_double(0x7ff0000000000000ULL)
#define INFF __int_as_float(0x7f800000)
#define NAND __longlong_as_double(0xfff8000000000000ULL)
#define NANF __int_as_float(0x7fffffff)
#else
#define INFD std::numeric_limits<double>::infinity()
#define INFF std::numeric_limits<float>::infinity()
#define NAND std::numeric_limits<double>::quiet_NaN()
#define NANF std::numeric_limits<float>::quiet_NaN()
#endif

#ifdef GPUQO_PRINT_N_JOINS
extern __device__ unsigned long long join_counter; 
#endif

#define BLOCK_DIM 256
#define WARP_SIZE 32
#define WARP_MASK 0xFFFFFFFF
#define LANE_ID (threadIdx.x & (WARP_SIZE-1))
#define WARP_ID (threadIdx.x & (~(WARP_SIZE-1)))
#define W_OFFSET WARP_ID
#define LANE_MASK_LE (WARP_MASK >> (WARP_SIZE-1-LANE_ID))
#define __activemask_sync() __ballot_sync(WARP_MASK, 1)

template<typename T>
using uninit_device_vector = thrust::device_vector<T, uninitialized_allocator<T> >;

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_run_switch(int gpuqo_algorithm, 
											GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_run_idp1(int gpuqo_algorithm, 
											GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN> *gpuqo_run_idp2(int gpuqo_algo, 
										GpuqoPlannerInfo<BitmapsetN>* info,
										int n_iters = 0);
	
//TODO: Check if n_iters is useful for all 3 versions of the algorithm
template<typename BitmapsetN>
extern QueryTree<BitmapsetN> *gpuqo_run_dpdp_union(int gpuqo_algo, 
										GpuqoPlannerInfo<BitmapsetN>* info,
										int n_iters = 0);	

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_dpsize(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_dpsub(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpsize(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpsub(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpsub_bicc(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpsub_bicc_parallel(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpccp(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_dpe_dpsize(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_dpe_dpsub(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dpsub_parallel(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_dpe_dpccp(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_goo(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_ikkbz(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_linearized_dp(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern QueryTree<BitmapsetN>* gpuqo_cpu_dplin(GpuqoPlannerInfo<BitmapsetN>* info);


template<typename BitmapsetN>
extern Remapper<BitmapsetN,BitmapsetN> makeBFSIndexRemapper(GpuqoPlannerInfo<BitmapsetN>* info);

template<typename BitmapsetN>
extern GpuqoPlannerInfo<BitmapsetN> *minimumSpanningTree(GpuqoPlannerInfo<BitmapsetN> *info);

template<typename BitmapsetN>
extern void buildSubTrees(BitmapsetN* subtrees, GpuqoPlannerInfo<BitmapsetN> *info);

#endif							/* GPUQO_CUH */
