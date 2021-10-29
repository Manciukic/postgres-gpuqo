/*------------------------------------------------------------------------
 *
 * gpuqo_dpsub_unfiltered.cu
 *      declarations necessary for dpsub_unfiltered_iteration
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
#include "gpuqo_dpsub_enum_all_subs.cuh"

template<typename BitmapsetN>
struct dpsubEnumerateAllSubsFunctor : public pairs_enum_func_t<BitmapsetN>
{
    HashTableDpsub<BitmapsetN> memo;
    GpuqoPlannerInfo<BitmapsetN>* info;
    int n_splits;
public:
    dpsubEnumerateAllSubsFunctor(
        HashTableDpsub<BitmapsetN> _memo,
        GpuqoPlannerInfo<BitmapsetN>* _info,
        int _n_splits
    ) : memo(_memo), info(_info), n_splits(_n_splits)
    {}

    __device__
    JoinRelation<BitmapsetN> operator()(BitmapsetN relid, uint32_t cid)
    {
        return dpsubEnumerateAllSubs<BitmapsetN,CCC_DISABLED>{}(
                                            relid, cid, n_splits, memo, info);
    }
};
/* unrankEvaluateDPSub
 *
 *	 unrank algorithm for DPsub GPU variant with embedded evaluation and 
 *   partial pruning.
 */
template<typename BitmapsetN, typename BinaryFunction>
struct unrankEvaluateDPSub : public thrust::unary_function< uint_t<BitmapsetN>,thrust::tuple<BitmapsetN, JoinRelation<BitmapsetN> > >
{
    thrust::device_ptr<uint_t<BitmapsetN> > binoms;
    int sq;
    int qss;
    uint_t<BitmapsetN> offset;
    int n_splits;
    BinaryFunction enum_functor;
    GpuqoPlannerInfo<BitmapsetN>* info;
public:
    unrankEvaluateDPSub(
        BinaryFunction _enum_functor,
        int _sq,
        thrust::device_ptr<uint_t<BitmapsetN> > _binoms,
        int _qss,
        uint_t<BitmapsetN> _offset,
        int _n_splits,
        GpuqoPlannerInfo<BitmapsetN>* _info
    ) : enum_functor(_enum_functor), sq(_sq), binoms(_binoms), 
        qss(_qss), offset(_offset), n_splits(_n_splits), info(_info)
    {}
 
    __device__
    thrust::tuple<BitmapsetN, JoinRelation<BitmapsetN> > operator()(uint_t<BitmapsetN> tid)
    {
        uint_t<BitmapsetN> real_id = tid + offset;
        uint_t<BitmapsetN> sid = real_id / n_splits;
        uint_t<BitmapsetN> cid = real_id % n_splits;

        LOG_DEBUG("[%lu] n_splits=%d, sid=%lu, cid=[%lu,%lu)\n", 
                (uint64_t)tid, n_splits, (uint64_t)sid, 
                (uint64_t)cid, 
                (uint64_t)(cid+ceil_div(((uint_t<BitmapsetN>)1)<<qss, 
                n_splits))
        );

        BitmapsetN s = dpsub_unrank_sid<BitmapsetN>(sid, qss, sq, binoms.get());
        BitmapsetN relid = s<<1;

        LOG_DEBUG("[%lu] s=%u\n", (uint64_t)tid, s.toUint());

        JoinRelation<BitmapsetN> jr_out;
        
        if (is_connected(relid, info->edge_table))
            jr_out = enum_functor(relid, cid);
        else
            relid = BitmapsetN(0);

        return thrust::tuple<BitmapsetN, JoinRelation<BitmapsetN> >(relid, jr_out);
    }
};

template<typename BitmapsetN>
int dpsub_unfiltered_iteration(int iter, dpsub_iter_param_t<BitmapsetN> &params){
    uint64_t n_joins_per_thread;
    uint32_t n_sets_per_iteration;
    uint32_t threads_per_set;
    uint32_t factor = gpuqo_n_parallel / params.n_sets;

    if (factor < WARP_SIZE || params.n_joins_per_set <= WARP_SIZE){
        threads_per_set = WARP_SIZE;
    } else{
        threads_per_set = floorPow2(min((uint64_t)factor, 
                                        params.n_joins_per_set));
    }
    
    n_joins_per_thread = ceil_div(params.n_joins_per_set, threads_per_set);
    n_sets_per_iteration = min(
                        (uint64_t) params.scratchpad_size / threads_per_set, 
                        params.n_sets);

    LOG_PROFILE("n_joins_per_thread=%lu, n_sets_per_iteration=%u, threads_per_set=%u, factor=%u\n",
            n_joins_per_thread,
            n_sets_per_iteration,
            threads_per_set,
            factor
        );

    uint64_t id_offset = 0;
    uint64_t offset = 0;
    int n_iters = 0;
    while (offset < params.tot){
        uint32_t n_threads;
        uint64_t n_remaining_sets = (params.tot-offset)/params.n_joins_per_set;
        if (n_remaining_sets >= n_sets_per_iteration){
            n_threads = n_sets_per_iteration*threads_per_set;
        } else {
            n_threads = n_remaining_sets*threads_per_set;
        }   

        START_TIMING(unrank);
        // fill scratchpad
        thrust::tabulate(
            thrust::make_zip_iterator(thrust::make_tuple(
                params.gpu_scratchpad_keys.begin(),
                params.gpu_scratchpad_vals.begin()
            )),
            thrust::make_zip_iterator(thrust::make_tuple(
                params.gpu_scratchpad_keys.begin()+n_threads,
                params.gpu_scratchpad_vals.begin()+n_threads
            )),
            unrankEvaluateDPSub<BitmapsetN, dpsubEnumerateAllSubsFunctor<BitmapsetN> >(
                dpsubEnumerateAllSubsFunctor<BitmapsetN>(
                    *params.memo,
                    params.gpu_info,
                    threads_per_set
                ),
                params.info->n_rels,
                params.gpu_binoms.data(),
                iter,
                id_offset,
                threads_per_set,
                params.gpu_info
            ) 
        );
        STOP_TIMING(unrank);

        LOG_DEBUG("After tabulate\n");
        DUMP_VECTOR(params.gpu_scratchpad_keys.begin(), params.gpu_scratchpad_keys.begin()+n_threads);
        DUMP_VECTOR(params.gpu_scratchpad_vals.begin(), params.gpu_scratchpad_vals.begin()+n_threads);

        dpsub_prune_scatter(threads_per_set, n_threads, params);

        n_iters++;
        id_offset += n_threads;
        offset += ((uint64_t)n_sets_per_iteration)*params.n_joins_per_set;
    } // loop: while(offset<tot)

    return n_iters;
}

template int dpsub_unfiltered_iteration<Bitmapset32>(int, dpsub_iter_param_t<Bitmapset32>&);
template int dpsub_unfiltered_iteration<Bitmapset64>(int, dpsub_iter_param_t<Bitmapset64>&);