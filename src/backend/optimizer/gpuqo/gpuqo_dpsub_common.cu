/*------------------------------------------------------------------------
 *
 * gpuqo_dpsub.cu
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsub.cu
 *
 *-------------------------------------------------------------------------
 */

#include <iostream>
#include <cmath>
#include <cstdint>

#include <thrust/host_vector.h>
#include <thrust/device_vector.h>
#include <thrust/generate.h>
#include <thrust/sort.h>
#include <thrust/copy.h>
#include <thrust/tabulate.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/tuple.h>
#include <thrust/system/system_error.h>
#include <thrust/distance.h>

#include "optimizer/gpuqo_common.h"

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_binomial.cuh"
#include "gpuqo_query_tree.cuh"
#include "gpuqo_dpsub.cuh"

PROTOTYPE_TIMING(unrank);
PROTOTYPE_TIMING(filter);
PROTOTYPE_TIMING(compute);
PROTOTYPE_TIMING(prune);
PROTOTYPE_TIMING(scatter);
PROTOTYPE_TIMING(iteration);

// User-configured option
int gpuqo_n_parallel;


template<typename BitmapsetN>
struct CompJoinRelOfSize : public thrust::binary_function<
            HashTableKVDpsub<BitmapsetN>, HashTableKVDpsub<BitmapsetN>, bool>{
    int size;
public:
    CompJoinRelOfSize(int _size) : size(_size) {}

    __host__ __device__
    bool operator()(const HashTableKVDpsub<BitmapsetN> &a, 
                   const HashTableKVDpsub<BitmapsetN> &b) const
    {
        const BitmapsetN &a_id = thrust::get<0>(a);
        const BitmapsetN &b_id = thrust::get<0>(b);

        const JoinRelation<BitmapsetN> &a_jr = thrust::get<1>(a);
        const JoinRelation<BitmapsetN> &b_jr = thrust::get<1>(b);

        float a_cost = a_jr.cost.total;
        float b_cost = b_jr.cost.total;

        if (a_id.size() != size)
            a_cost = INFF;

        if (b_id.size() != size)
            b_cost = INFF;
        
        return a_cost < b_cost;        
    }
};

template<typename BitmapsetN>
void dpsub_prune_scatter(int threads_per_set, int n_threads, dpsub_iter_param_t<BitmapsetN> &params){
    // give possibility to user to interrupt
    CHECK_FOR_INTERRUPTS();

    scatter_iter_t<BitmapsetN> scatter_from_iters;
    scatter_iter_t<BitmapsetN> scatter_to_iters;

    if (threads_per_set != 1){
        START_TIMING(prune);
        scatter_from_iters = thrust::make_pair(
            params.gpu_reduced_keys.begin(),
            params.gpu_reduced_vals.begin()
        );
        // prune to intermediate memory
        scatter_to_iters = thrust::reduce_by_key(
            params.gpu_scratchpad_keys.begin(),
            params.gpu_scratchpad_keys.begin() + n_threads,
            params.gpu_scratchpad_vals.begin(),
            params.gpu_reduced_keys.begin(),
            params.gpu_reduced_vals.begin(),
            thrust::equal_to<BitmapsetN>(),
            thrust::minimum<JoinRelation<BitmapsetN> >()
        );
        STOP_TIMING(prune);
    } else{
        scatter_from_iters = thrust::make_pair(
            params.gpu_scratchpad_keys.begin(),
            params.gpu_scratchpad_vals.begin()
        );
        scatter_to_iters = thrust::make_pair(
            (params.gpu_scratchpad_keys.begin()+n_threads),
            (params.gpu_scratchpad_vals.begin()+n_threads)
        );
    }

    LOG_DEBUG("After reduce_by_key\n");
    DUMP_VECTOR(scatter_from_iters.first, scatter_to_iters.first);
    DUMP_VECTOR(scatter_from_iters.second, scatter_to_iters.second);

    dpsub_scatter(scatter_from_iters, scatter_to_iters, params);
}

template void dpsub_prune_scatter<Bitmapset32>(int, int, dpsub_iter_param_t<Bitmapset32>&);
template void dpsub_prune_scatter<Bitmapset64>(int, int, dpsub_iter_param_t<Bitmapset64>&);

template<typename BitmapsetN>
void dpsub_scatter(int n_sets, dpsub_iter_param_t<BitmapsetN> &params){
    // give possibility to user to interrupt
    CHECK_FOR_INTERRUPTS();

    scatter_iter_t<BitmapsetN> scatter_from_iters;
    scatter_iter_t<BitmapsetN> scatter_to_iters;


    scatter_from_iters = thrust::make_pair(
        params.gpu_scratchpad_keys.begin(),
        params.gpu_scratchpad_vals.begin()
    );
    scatter_to_iters = thrust::make_pair(
        (params.gpu_scratchpad_keys.begin()+n_sets),
        (params.gpu_scratchpad_vals.begin()+n_sets)
    );

    DUMP_VECTOR(scatter_from_iters.first, scatter_to_iters.first);
    DUMP_VECTOR(scatter_from_iters.second, scatter_to_iters.second);

    dpsub_scatter(scatter_from_iters, scatter_to_iters, params);
}

template void dpsub_scatter<Bitmapset32>(int, dpsub_iter_param_t<Bitmapset32>&);
template void dpsub_scatter<Bitmapset64>(int, dpsub_iter_param_t<Bitmapset64>&);

template<typename BitmapsetN>
void dpsub_scatter(scatter_iter_t<BitmapsetN> scatter_from_iters, 
                   scatter_iter_t<BitmapsetN> scatter_to_iters, 
                   dpsub_iter_param_t<BitmapsetN> &params){
    // give possibility to user to interrupt
    CHECK_FOR_INTERRUPTS();

    START_TIMING(scatter);
    params.memo->insert(
        scatter_from_iters.first.base().get(),
        scatter_from_iters.second.base().get(),
        thrust::distance(
            scatter_from_iters.first,
            scatter_to_iters.first
        )
    );
    STOP_TIMING(scatter);
}

template void dpsub_scatter<Bitmapset32>(scatter_iter_t<Bitmapset32>,scatter_iter_t<Bitmapset32>, dpsub_iter_param_t<Bitmapset32>&);
template void dpsub_scatter<Bitmapset64>(scatter_iter_t<Bitmapset64>,scatter_iter_t<Bitmapset64>, dpsub_iter_param_t<Bitmapset64>&);

/* gpuqo_dpsub
 *
 *	 GPU query optimization using the DP size variant.
 */
template<typename BitmapsetN>
QueryTree<BitmapsetN>*
gpuqo_dpsub(GpuqoPlannerInfo<BitmapsetN>* info)
{
    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 1 ------" << std::endl;
    DECLARE_TIMING(gpuqo_dpsub);
    DECLARE_NV_TIMING(init);
    DECLARE_NV_TIMING(execute);
    
    START_TIMING(gpuqo_dpsub);
    START_TIMING(init);

    size_t entry_size = sizeof(JoinRelation<BitmapsetN>)+sizeof(BitmapsetN);
    size_t min_memo_cap = (size_t) gpuqo_min_memo_size_mb * MB / entry_size;
    size_t max_memo_cap = (size_t) gpuqo_max_memo_size_mb * MB / entry_size;
    size_t req_memo_size = 1ULL<<(info->n_rels);

    size_t memo_cap = std::min(req_memo_size*2, min_memo_cap);
    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 2 ------" << std::endl;

    dpsub_iter_param_t<BitmapsetN> params;
    params.info = info;
    params.gpu_info = copyToDeviceGpuqoPlannerInfo<BitmapsetN>(info);
    params.memo = new HashTableDpsub<BitmapsetN>(memo_cap, max_memo_cap);
    thrust::host_vector<BitmapsetN> ini_memo_keys(info->n_rels+1);
    thrust::host_vector<JoinRelation<BitmapsetN>> ini_memo_vals(info->n_rels+1);
    thrust::device_vector<BitmapsetN> ini_memo_keys_gpu(info->n_rels+1);
    thrust::device_vector<JoinRelation<BitmapsetN>> ini_memo_vals_gpu(info->n_rels+1);
    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 3 ------" << std::endl;

    QueryTree<BitmapsetN>* out = NULL;
    params.out_relid = BitmapsetN(0);

    for(int i=0; i<info->n_rels; i++){
        // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 4 ------" << std::endl;
        JoinRelation<BitmapsetN> t;
        t.left_rel_id = BitmapsetN(0); 
        t.left_rel_id = BitmapsetN(0); 
        t.cost = cost_baserel(info->base_rels[i]); 
        t.width = info->base_rels[i].width; 
        t.rows = info->base_rels[i].rows; 
        ini_memo_keys[i] = info->base_rels[i].id;
        ini_memo_vals[i] = t;

        params.out_relid = params.out_relid | info->base_rels[i].id;
    }
    
    // add dummy relation
    JoinRelation<BitmapsetN> dummy_jr;
	dummy_jr.left_rel_id = BitmapsetN(0);
	dummy_jr.right_rel_id = BitmapsetN(0);
    dummy_jr.rows = 0.0;
	dummy_jr.cost.total = 0.0;
	dummy_jr.cost.startup = 0.0;
    
    ini_memo_keys[info->n_rels] = 0;
    ini_memo_vals[info->n_rels] = dummy_jr;

    // transfer base relations to GPU
    ini_memo_keys_gpu = ini_memo_keys;
    ini_memo_vals_gpu = ini_memo_vals;
    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 5 ------" << std::endl;

    params.memo->insert(
        thrust::raw_pointer_cast(ini_memo_keys_gpu.data()), 
        thrust::raw_pointer_cast(ini_memo_vals_gpu.data()),
        info->n_rels+1
    );
    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 6 ------" << std::endl;

    int binoms_size = (info->n_rels+1)*(info->n_rels+1);
    params.binoms = thrust::host_vector<uint_t<BitmapsetN> >(binoms_size);
    precompute_binoms<uint_t<BitmapsetN> >(params.binoms, info->n_rels);
    params.gpu_binoms = params.binoms;

    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 7 ------" << std::endl;
    params.scratchpad_size = (
        (
            gpuqo_scratchpad_size_mb * MB
        ) / (
            sizeof(BitmapsetN)*gpuqo_dpsub_filter_keys_overprovisioning + 
            (sizeof(BitmapsetN) + sizeof(JoinRelation<BitmapsetN>))
        )
    );  

    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 8 ------" << std::endl;
    if (params.scratchpad_size < gpuqo_n_parallel)
        params.scratchpad_size = gpuqo_n_parallel;

    LOG_PROFILE("Using a scratchpad of size %u\n", params.scratchpad_size);

    params.gpu_pending_keys = uninit_device_vector<BitmapsetN>(PENDING_KEYS_SIZE(params));
    params.gpu_scratchpad_keys = uninit_device_vector<BitmapsetN>(params.scratchpad_size);
    params.gpu_scratchpad_vals = uninit_device_vector<JoinRelation<BitmapsetN>>(params.scratchpad_size);
    params.gpu_reduced_keys = uninit_device_vector<BitmapsetN>(params.scratchpad_size);
    params.gpu_reduced_vals = uninit_device_vector<JoinRelation<BitmapsetN>>(params.scratchpad_size);

    // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 9 ------" << std::endl;
#ifdef GPUQO_PRINT_N_JOINS
    unsigned long long join_counter_h = 0;
    cudaMemcpyToSymbol(join_counter, &join_counter_h, sizeof(join_counter_h));
#endif

    STOP_TIMING(init);

    DUMP_VECTOR(params.gpu_binoms.begin(), params.gpu_binoms.end());    

    START_TIMING(execute);
    try{ // catch any exception in thrust
        INIT_NV_TIMING(unrank);
        INIT_NV_TIMING(filter);
        INIT_NV_TIMING(compute);
        INIT_NV_TIMING(prune);
        INIT_NV_TIMING(scatter);
        INIT_NV_TIMING(iteration);
        DECLARE_NV_TIMING(build_qt);

        // iterate over the size of the resulting joinrel
        for(int i=2; i<=info->n_iters; i++){
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10 ------" << std::endl;
            // std::cout << "i: " << i << " info->n-iters" << info->n_iters << std::endl;

            // give possibility to user to interrupt
            CHECK_FOR_INTERRUPTS();
            
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-1 ------" << std::endl;
            // calculate number of combinations of relations that make up 
            // a joinrel of size i
            params.n_sets = BINOM(params.binoms, info->n_rels, info->n_rels, i);
            params.n_joins_per_set = ((1ULL)<<i);
            params.tot = ((uint64_t)params.n_sets) * params.n_joins_per_set;
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-2 ------" << std::endl;

            // used only if profiling is enabled
            uint32_t n_iters __attribute__((unused));
            uint64_t filter_threshold = ((uint64_t)gpuqo_n_parallel) * gpuqo_dpsub_filter_threshold;
            uint64_t csg_threshold = ((uint64_t)gpuqo_n_parallel) * gpuqo_dpsub_csg_threshold;
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-3 ------" << std::endl;

            START_TIMING(iteration);
            if ((gpuqo_dpsub_filter_enable && params.tot > filter_threshold) 
                    || (gpuqo_dpsub_csg_enable && params.tot > csg_threshold)){
                // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-4 ------" << std::endl;
                LOG_PROFILE("\nStarting filtered iteration %d: %lu combinations\n", i, params.tot);

                n_iters = dpsub_filtered_iteration(i, params);
            } else {
                // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-5 ------" << std::endl;
                LOG_PROFILE("\nStarting unfiltered iteration %d: %lu combinations\n", i, params.tot);

                n_iters = dpsub_unfiltered_iteration(i, params);
            }
            STOP_TIMING(iteration);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-6 ------" << std::endl;

            LOG_DEBUG("It took %d iterations\n", n_iters);
            PRINT_CHECKPOINT_TIMING(unrank);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-unrank ------" << std::endl;
            PRINT_CHECKPOINT_TIMING(filter);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-filter ------" << std::endl;
            PRINT_CHECKPOINT_TIMING(compute);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-compute ------" << std::endl;
            PRINT_CHECKPOINT_TIMING(prune);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-prune ------" << std::endl;
            PRINT_CHECKPOINT_TIMING(scatter);
            // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 10-scatter ------" << std::endl;
            PRINT_TIMING(iteration);
        } // dpsub loop: for i = 2..n_rels

        START_TIMING(build_qt);
            
        BitmapsetN final_relid;
        // std::cout << "INSIDE gpuqo_dpsub_common.cuh ----- 11 ------" << std::endl;
        if (info->n_rels == info->n_iters){ // normal DP
            final_relid = params.out_relid;
        } else { // IDP
            auto best = thrust::min_element(
                params.memo->begin(), 
                params.memo->end(),
                CompJoinRelOfSize<BitmapsetN>(info->n_iters)
            );
            final_relid = *thrust::get<0>(best.get_iterator_tuple());
        }         

        dpsub_buildQueryTree<BitmapsetN,HashTableDpsub<BitmapsetN> >(final_relid, *params.memo, &out);
    
        STOP_TIMING(build_qt);
    
        PRINT_TOTAL_TIMING(unrank);
        PRINT_TOTAL_TIMING(filter);
        PRINT_TOTAL_TIMING(compute);
        PRINT_TOTAL_TIMING(prune);
        PRINT_TOTAL_TIMING(scatter);
    } catch(thrust::system_error err){
        printf("Thrust %d: %s\n", err.code().value(), err.what());
    }

    STOP_TIMING(execute);
    STOP_TIMING(gpuqo_dpsub);

    PRINT_TIMING(gpuqo_dpsub);
    PRINT_TIMING(init);
    PRINT_TIMING(execute);

#ifdef GPUQO_PRINT_N_JOINS
    cudaMemcpyFromSymbol(&join_counter_h, join_counter, sizeof(join_counter_h));
    printf("The algorithm did %llu joins\n", join_counter_h);
#endif

    params.memo->free();
    delete params.memo;

    cudaFree(params.gpu_info);

    return out;
}

template QueryTree<Bitmapset32>* gpuqo_dpsub<Bitmapset32>(GpuqoPlannerInfo<Bitmapset32>* info);
template QueryTree<Bitmapset64>* gpuqo_dpsub<Bitmapset64>(GpuqoPlannerInfo<Bitmapset64>* info);