/*------------------------------------------------------------------------
 *
 * gpuqo_dpsub_filtered_kernels.cuh
 *      kernels for dpsub filtered iteration
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsub_filtered_kernels.cuh
 *
 *-------------------------------------------------------------------------
 */

#include <iostream>
#include <cmath>
#include <cstdint>

#include "optimizer/gpuqo_common.h"

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_dpsub.cuh"

#ifndef GPUQO_DPSUB_FILTERED_KERNELS
#define GPUQO_DPSUB_FILTERED_KERNELS

/**
    Faster dpsub enumeration using bit magic to compute next set.
 */
template<typename BitmapsetN>
__global__
void unrankFilteredDPSubKernel(int sq, int qss, 
                               uint_t<BitmapsetN> offset, uint32_t n_tab_sets,
                               uint_t<BitmapsetN>* binoms,
                               GpuqoPlannerInfo<BitmapsetN>* info,
                               BitmapsetN* out_relids)
{
    uint32_t threadid = blockIdx.x*blockDim.x + threadIdx.x;
    uint32_t n_threads = blockDim.x * gridDim.x;

    int n_active = __popc(__activemask_sync());
    __shared__ BitmapsetN edge_table[BitmapsetN::SIZE];
    for (int i = threadIdx.x; i < sq; i+=n_active){
        edge_table[i] = info->edge_table[i];
    }
    __syncthreads();
    
    if (threadid < n_tab_sets){
        uint_t<BitmapsetN> sets_per_thread = n_tab_sets / n_threads;
        uint_t<BitmapsetN> n_excess = n_tab_sets % n_threads;
        uint_t<BitmapsetN> idx = threadid * sets_per_thread 
                                + (threadid < n_excess ? threadid : n_excess)
                                + offset;
        
        
        BitmapsetN s = dpsub_unrank_sid<BitmapsetN>(idx, qss, sq, binoms);

        for (uint32_t tid = threadid; tid < n_tab_sets; tid += n_threads){
            BitmapsetN relid = s << 1;
            
            if (!is_connected(relid, edge_table))
                relid = BitmapsetN(0);
            
            LOG_DEBUG("[%u,%u] tid=%u idx=%lu s=%u relid=%u\n", 
                        blockIdx.x, threadIdx.x, 
                        tid, (uint64_t)idx++, s.toUint(), relid.toUint());
            out_relids[tid] = relid;

            s = dpsub_unrank_next(s);
        }
    }
}

template<typename BitmapsetN>
static void launchUnrankFilteredDPSubKernel(int sq, int qss, 
                                     uint64_t offset, 
                                     uint32_t n_tab_sets,
                                     uint_t<BitmapsetN>* binoms,
                                     GpuqoPlannerInfo<BitmapsetN>* info,
                                     BitmapsetN* out_relids)
{
    int blocksize = 512;
    
    int mingridsize;
    int threadblocksize;
    cudaOccupancyMaxPotentialBlockSize(&mingridsize, &threadblocksize, 
        unrankFilteredDPSubKernel<BitmapsetN>, 0, blocksize);

    int gridsize = min(mingridsize, ceil_div(n_tab_sets, blocksize));

    unrankFilteredDPSubKernel<<<gridsize, blocksize>>>(
        sq, qss, 
        offset, n_tab_sets,
        binoms,
        info,
        out_relids
    );

    cudaDeviceSynchronize();

    cudaError_t err = cudaGetLastError();
    if (err){
        printf("CUDA ERROR! %s: %s\n", 
            cudaGetErrorName(err),
            cudaGetErrorString(err)
        );
        throw "CUDA ERROR";
    }
}

template<int STEP>
__device__ void blockReduceMinStep(volatile int* s_indexes, 
                                volatile float* s_costs)
{
    int tid = threadIdx.x;

    if (tid % (2*STEP) == 0){
        if (s_costs[tid+STEP] < s_costs[tid]){
            s_costs[tid] = s_costs[tid+STEP];
            s_indexes[tid] = s_indexes[tid+STEP];
        }
        LOG_DEBUG("red<%3d> idx[%3d]=%3d, cost[%3d]=%.2f\n",
                    STEP, tid, s_indexes[tid], tid, s_costs[tid]);
    }
    if (STEP >= WARP_SIZE)
        __syncthreads();
    else
        __syncwarp();

}

template<int DIM>
__device__ void blockReduceMin(volatile int* s_indexes, 
                                volatile float* s_costs)
{
    if (DIM >   1) blockReduceMinStep<  1>(s_indexes, s_costs);
    if (DIM >   2) blockReduceMinStep<  2>(s_indexes, s_costs);
    if (DIM >   4) blockReduceMinStep<  4>(s_indexes, s_costs);
    if (DIM >   8) blockReduceMinStep<  8>(s_indexes, s_costs);
    if (DIM >  16) blockReduceMinStep< 16>(s_indexes, s_costs);
    if (DIM >  32) blockReduceMinStep< 32>(s_indexes, s_costs);
    if (DIM >  64) blockReduceMinStep< 64>(s_indexes, s_costs);
    if (DIM > 128) blockReduceMinStep<128>(s_indexes, s_costs);
    if (DIM > 256) blockReduceMinStep<256>(s_indexes, s_costs);
    if (DIM > 512) blockReduceMinStep<512>(s_indexes, s_costs);
}

 /* evaluateDPSub
  *
  *	 evaluation algorithm for DPsub GPU variant with partial pruning
  */
template<typename BitmapsetN, int n_splits, typename Function, bool full_shmem>
__global__
void evaluateFilteredDPSubKernel(BitmapsetN* pending_keys, BitmapsetN* scratchpad_keys, JoinRelation<BitmapsetN>* scratchpad_vals, uint32_t sq, uint32_t qss, uint32_t n_pending_sets, uint32_t n_sets, HashTableDpsub<BitmapsetN> memo, GpuqoPlannerInfo<BitmapsetN> *info){
    uint32_t n_threads_cuda = blockDim.x * gridDim.x;

    __shared__ volatile float shared_costs[BLOCK_DIM];
    __shared__ volatile int shared_idxs[BLOCK_DIM];

    extern __shared__ uint64_t dynshmem[];
    int size = full_shmem ? info->size : sizeof(GpuqoPlannerInfo<BitmapsetN>);
    for (int i = threadIdx.x; i < size/8; i+=blockDim.x){
        dynshmem[i] = *((uint64_t*)info + i);
    }
    __syncthreads();
    
    GpuqoPlannerInfo<BitmapsetN> *info_sh = (GpuqoPlannerInfo<BitmapsetN> *)dynshmem;
	
    if (threadIdx.x == 0){
        char *p = (char*) dynshmem;
        p += plannerInfoBaseSize<BitmapsetN>();

        if (full_shmem){
            info_sh->eq_classes.relids = (BitmapsetN*) p;
            p += plannerInfoEqClassesSize<BitmapsetN>(info->eq_classes.n);
            
            info_sh->eq_classes.sels = (float*) p;
            p += plannerInfoEqClassSelsSize<BitmapsetN>(info->eq_classes.n_sels);
            
            info_sh->eq_classes.fks = (BitmapsetN*) p;
            p += plannerInfoEqClassFksSize<BitmapsetN>(info->eq_classes.n_fks);
            
            info_sh->eq_classes.vars = (VarInfo*) p;
            p += plannerInfoEqClassVarsSize<BitmapsetN>(info->eq_classes.n_vars);
        } else {
            info_sh->eq_classes.relids = info->eq_classes.relids;
            info_sh->eq_classes.sels = info->eq_classes.sels;
            info_sh->eq_classes.fks = info->eq_classes.fks;
        }
    }
    __syncthreads();
    
    for (uint32_t tid = blockIdx.x*blockDim.x + threadIdx.x; 
        tid < n_splits*n_sets; 
        tid += n_threads_cuda) 
    {
        uint32_t rid = n_pending_sets - 1 - (tid / n_splits);
        uint32_t cid = tid % n_splits;

        Assert(n_pending_sets-1 <= 0xFFFFFFFF - tid / n_splits);

        BitmapsetN relid = pending_keys[rid];
        Assert(is_connected(relid, info->edge_table));

        LOG_DEBUG("[%u] n_splits=%d, rid=%u, cid=%u, relid=%u\n", 
                tid, n_splits, rid, cid, relid.toUint());
        
        JoinRelation<BitmapsetN> jr_out = Function{}(relid, cid, n_splits, 
                                        memo, info_sh);
        shared_idxs[threadIdx.x] = threadIdx.x;
        shared_costs[threadIdx.x] = jr_out.cost.total;

        if (n_splits > WARP_SIZE)
            __syncthreads();
        else
            __syncwarp();

        LOG_DEBUG("red<%3d> before: idx[%3d]=%3d, cost[%3d]=%.2f\n",
                n_splits, threadIdx.x, shared_idxs[threadIdx.x], 
                        threadIdx.x, shared_costs[threadIdx.x]);

#ifndef DISABLE_WARP_REDUCTION
        blockReduceMin<n_splits>(&shared_idxs[0], &shared_costs[0]);

        int leader = threadIdx.x & (~(n_splits-1));
#else
        int leader = threadIdx.x;
#endif

        if (threadIdx.x == leader){
            LOG_DEBUG("red<%3d> after: idx[%3d]=%3d, cost[%3d]=%.2f\n",
                n_splits, threadIdx.x, shared_idxs[threadIdx.x], 
                        threadIdx.x, shared_costs[threadIdx.x]);
        }

        if (threadIdx.x == shared_idxs[leader]){
            LOG_DEBUG("[%3d] write scratch[%d] = %u (l=%u, r=%u, cost=%.2f)\n",
                threadIdx.x, tid/n_splits, relid.toUint(), 
                jr_out.left_rel_id.toUint(), jr_out.right_rel_id.toUint(), jr_out.cost.total);
#ifndef DISABLE_WARP_REDUCTION
            int position = tid/n_splits;
#else
            int position = tid;
#endif
            scratchpad_keys[position] = relid;
            scratchpad_vals[position] = jr_out;
        }
    }
}

template<typename BitmapsetN, int n_splits, typename Function, bool full_shmem>
static void __launchEvaluateFilteredDPSubKernel(BitmapsetN* pending_keys, BitmapsetN* scratchpad_keys, JoinRelation<BitmapsetN>* scratchpad_vals, uint32_t sq, uint32_t qss, uint32_t n_pending_sets, uint32_t n_sets, uint32_t shmem_size, HashTableDpsub<BitmapsetN> &memo, GpuqoPlannerInfo<BitmapsetN> *info)
{
    int blocksize = BLOCK_DIM;
    
    int mingridsize;
    int threadblocksize;
    cudaOccupancyMaxPotentialBlockSize(&mingridsize, &threadblocksize, 
        evaluateFilteredDPSubKernel<BitmapsetN, n_splits, Function, full_shmem>, 0, blocksize);

    int gridsize = min(mingridsize, ceil_div(n_sets*n_splits, blocksize));
        
    // cudaFuncSetCacheConfig(evaluateFilteredDPSubKernel<n_splits, Function>, cudaFuncCachePreferL1);

    // n_splits is a power of 2 and is lower than or equal to BLOCK_DIM
    Assert(popc(n_splits) == 1 && n_splits <= BLOCK_DIM);

    evaluateFilteredDPSubKernel<BitmapsetN, n_splits, Function, full_shmem><<<gridsize, blocksize, shmem_size>>>(
        pending_keys, scratchpad_keys, scratchpad_vals,
        sq, qss, 
        n_pending_sets, n_sets,
        memo, info
    );

    cudaDeviceSynchronize();

    cudaError_t err = cudaGetLastError();
    if (err){
        printf("CUDA ERROR! %s: %s\n", 
            cudaGetErrorName(err),
            cudaGetErrorString(err)
        );
        throw "CUDA ERROR";
    }
}

template<typename BitmapsetN, int n_splits, typename Function>
static void _launchEvaluateFilteredDPSubKernel(BitmapsetN* pending_keys, BitmapsetN* scratchpad_keys, JoinRelation<BitmapsetN>* scratchpad_vals, uint32_t sq, uint32_t qss, uint32_t n_pending_sets, uint32_t n_sets, HashTableDpsub<BitmapsetN> &memo, GpuqoPlannerInfo<BitmapsetN> *info, GpuqoPlannerInfo<BitmapsetN> *gpu_info)
{
    //TODO it would be cool to obtain this threshold from CUDA API
    if (info->size > 6000){ 
        int shmem_size = sizeof(GpuqoPlannerInfo<BitmapsetN>);
        __launchEvaluateFilteredDPSubKernel<BitmapsetN, n_splits, Function, false>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, shmem_size, memo, gpu_info);
    } else {
        int shmem_size = info->size;
        __launchEvaluateFilteredDPSubKernel<BitmapsetN, n_splits, Function, true>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, shmem_size, memo, gpu_info);

    }
}


template<typename BitmapsetN, typename Function>
static void launchEvaluateFilteredDPSubKernel(BitmapsetN* pending_keys, BitmapsetN* scratchpad_keys, JoinRelation<BitmapsetN>* scratchpad_vals, uint32_t sq, uint32_t qss, uint32_t n_pending_sets, uint32_t n_splits, uint32_t n_sets, HashTableDpsub<BitmapsetN> &memo, GpuqoPlannerInfo<BitmapsetN> *info, GpuqoPlannerInfo<BitmapsetN> *gpu_info){
    switch(n_splits){
    case    1:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,   1, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case    2:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,   2, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case    4:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,   4, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case    8:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,   8, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case   16:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,  16, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case   32:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,  32, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case   64:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,  64, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case  128:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN, 128, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case  256:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN, 256, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case  512:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN, 512, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    case 1024:
        _launchEvaluateFilteredDPSubKernel<BitmapsetN,1024, Function>(pending_keys, scratchpad_keys, scratchpad_vals, sq, qss, n_pending_sets, n_sets, memo, info, gpu_info);
        break;
    default:
        printf("FATAL ERROR: Trying to call launchEvaluateFilteredDPSubKernel with n_splits=%d\n", n_splits);
        exit(1);
    }
}

#endif							/* GPUQO_DPSUB_FILTERED_KERNELS */
