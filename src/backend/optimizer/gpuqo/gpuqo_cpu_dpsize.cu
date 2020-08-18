/*------------------------------------------------------------------------
 *
 * gpuqo_cpu_dpsize.cu
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsize.cu
 *
 *-------------------------------------------------------------------------
 */

#include <list>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <cmath>
#include <cstdint>

#include "optimizer/gpuqo_common.h"

#include "optimizer/gpuqo.cuh"
#include "optimizer/gpuqo_timing.cuh"
#include "optimizer/gpuqo_debug.cuh"
#include "optimizer/gpuqo_cost.cuh"
#include "optimizer/gpuqo_filter.cuh"
#include "optimizer/gpuqo_cpu_sequential.cuh"
#include "optimizer/gpuqo_cpu_dpe.cuh"

struct GpuqoCPUDPSizeExtra{
    vector_list_t rels_per_level;

    GpuqoCPUDPSizeExtra(int n_rels) : rels_per_level(n_rels+1) {}
};

void gpuqo_cpu_dpsize_init(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[], memo_t &memo, extra_t &extra){
    extra.alg = (void*) new GpuqoCPUDPSizeExtra(n_rels);
    struct GpuqoCPUDPSizeExtra* mExtra = (struct GpuqoCPUDPSizeExtra*) extra.alg;

    for(auto iter = memo.begin(); iter != memo.end(); ++iter){
        mExtra->rels_per_level[1].push_back(iter->second);
    }
}

void gpuqo_cpu_dpsize_enumerate(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[], join_f join_function, memo_t &memo, extra_t extra, struct DPCPUAlgorithm algorithm){
    struct GpuqoCPUDPSizeExtra* mExtra = (struct GpuqoCPUDPSizeExtra*) extra.alg;

    for (int join_s=2; join_s<=n_rels; join_s++){
        for (int big_s = join_s-1; big_s >= (join_s+1)/2; big_s--){
            int small_s = join_s-big_s;
            for (auto big_i = mExtra->rels_per_level[big_s].begin(); 
                    big_i != mExtra->rels_per_level[big_s].end(); ++big_i){
                for (auto small_i = mExtra->rels_per_level[small_s].begin(); 
                        small_i != mExtra->rels_per_level[small_s].end(); ++small_i){
                    join_function(join_s, true, **big_i, **small_i, 
                        base_rels, n_rels, edge_table, memo, extra, algorithm
                    );
                }
            } 
        }
    }

}

bool gpuqo_cpu_dpsize_check_join(int level, JoinRelation &left_rel,             
                            JoinRelation &right_rel, BaseRelation* base_rels, int n_rels,  EdgeInfo* edge_table, memo_t &memo,
                            extra_t extra){

    return (is_disjoint(left_rel, right_rel) 
        && are_connected(left_rel, right_rel, base_rels, n_rels, edge_table));
}

void gpuqo_cpu_dpsize_post_join(int level, bool newrel, JoinRelation &join_rel, 
                            JoinRelation &left_rel, JoinRelation &right_rel,
                            BaseRelation* base_rels, int n_rels, 
                            EdgeInfo* edge_table, memo_t &memo, extra_t extra){
    struct GpuqoCPUDPSizeExtra* mExtra = (struct GpuqoCPUDPSizeExtra*) extra.alg;
    if (newrel)
        mExtra->rels_per_level[level].push_back(&join_rel);
}

void gpuqo_cpu_dpsize_teardown(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[], memo_t &memo, extra_t extra){
    delete ((struct GpuqoCPUDPSizeExtra*) extra.alg);
}

DPCPUAlgorithm gpuqo_cpu_dpsize_alg = {
    .init_function = gpuqo_cpu_dpsize_init,
    .enumerate_function = gpuqo_cpu_dpsize_enumerate,
    .check_join_function = gpuqo_cpu_dpsize_check_join,
    .post_join_function = gpuqo_cpu_dpsize_post_join,
    .teardown_function = gpuqo_cpu_dpsize_teardown
};

/* gpuqo_cpu_dpsize
 *
 *	 Sequential CPU baseline for GPU query optimization using the DP size
 *   algorithm.
 */
extern "C"
QueryTree*
gpuqo_cpu_dpsize(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[])
{
    return gpuqo_cpu_sequential(base_rels, n_rels, edge_table, gpuqo_cpu_dpsize_alg);
}

/* gpuqo_cpu_dpsize
 *
 *	 Parallel CPU baseline for GPU query optimization using the DP size
 *   algorithm.
 */
extern "C"
QueryTree*
gpuqo_dpe_dpsize(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[])
{
    return gpuqo_cpu_dpe(base_rels, n_rels, edge_table, gpuqo_cpu_dpsize_alg);
}

