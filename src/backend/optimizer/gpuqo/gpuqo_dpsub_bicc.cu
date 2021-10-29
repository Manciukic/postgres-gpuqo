/*------------------------------------------------------------------------
 *
 * gpuqo_dpsub_bicc.cu
 *      definition for function to launch dpsub bicc iteration
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsub_bicc.cu
 *
 *-------------------------------------------------------------------------
 */

#include <iostream>
#include <cmath>
#include <cstdint>

#include <thrust/device_vector.h>

#include "optimizer/gpuqo_common.h"

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_dpsub.cuh"
#include "gpuqo_dpsub_bicc.cuh"
#include "gpuqo_dpsub_filtered_kernels.cuh"

template<typename BitmapsetN>
uint32_t dpsub_bicc_evaluation(int iter, uint64_t n_remaining_sets,
                                    uint64_t offset, uint32_t n_pending_sets, 
                                    dpsub_iter_param_t<BitmapsetN> &params)
{
    uint64_t n_joins_per_thread;
    uint32_t n_sets_per_iteration;
    uint32_t threads_per_set;
    uint32_t factor = gpuqo_n_parallel / n_pending_sets;

    threads_per_set = WARP_SIZE;
    
    n_joins_per_thread = ceil_div(params.n_joins_per_set, threads_per_set);
#ifndef DISABLE_WARP_REDUCTION
    n_sets_per_iteration = min(params.scratchpad_size, n_pending_sets);
#else
    n_sets_per_iteration = min(params.scratchpad_size/threads_per_set, n_pending_sets);
#endif

    LOG_PROFILE("n_joins_per_thread=%lu, n_sets_per_iteration=%u, threads_per_set=%u, factor=%u\n",
        n_joins_per_thread,
        n_sets_per_iteration,
        threads_per_set,
        factor
    );
    LOG_PROFILE("Using BiCC enumeration\n");

    // do not empty all pending sets if there are some sets still to 
    // evaluate, since I will do them in the next iteration
    // If no sets remain, then I will empty all pending
    while (n_pending_sets >= gpuqo_n_parallel 
        || (n_pending_sets > 0 && n_remaining_sets == 0)
    ){
        uint32_t n_eval_sets = min(n_sets_per_iteration, n_pending_sets);

        START_TIMING(compute);
        launchEvaluateFilteredDPSubKernel<BitmapsetN,dpsubEnumerateBiCC<BitmapsetN> >(
            thrust::raw_pointer_cast(params.gpu_pending_keys.data())+offset,
            thrust::raw_pointer_cast(params.gpu_scratchpad_keys.data()),
            thrust::raw_pointer_cast(params.gpu_scratchpad_vals.data()),
            params.info->n_rels,
            iter,
            n_pending_sets,
            threads_per_set,
            n_eval_sets,
            *params.memo,
            params.info,
            params.gpu_info
        );     
        STOP_TIMING(compute);

        LOG_DEBUG("After tabulate\n");
        DUMP_VECTOR(params.gpu_scratchpad_keys.begin(), params.gpu_scratchpad_keys.begin()+n_eval_sets);
        DUMP_VECTOR(params.gpu_scratchpad_vals.begin(), params.gpu_scratchpad_vals.begin()+n_eval_sets);

#ifndef DISABLE_WARP_REDUCTION
        dpsub_scatter<BitmapsetN>(n_eval_sets, params);
#else
        dpsub_prune_scatter(threads_per_set, threads_per_set*n_eval_sets, params);
#endif

        n_pending_sets -= n_eval_sets;
    }

    return n_pending_sets;
}

template uint32_t dpsub_bicc_evaluation(int, uint64_t, uint64_t, uint32_t, 
                                        dpsub_iter_param_t<Bitmapset32>&);
template uint32_t dpsub_bicc_evaluation(int, uint64_t, uint64_t, uint32_t, 
                                        dpsub_iter_param_t<Bitmapset64>&);