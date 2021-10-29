/*------------------------------------------------------------------------
 *
 * gpuqo_cpu_sequential.cu
 *      Generic implementation of a sequential CPU algorithm.
 *
 * src/backend/optimizer/gpuqo/gpuqo_cpu_sequential.cu
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

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_cpu_sequential.cuh"

template<typename BitmapsetN, typename memo_t>
class SequentialJoinFunction : public CPUJoinFunction<BitmapsetN, memo_t> {
public:
    SequentialJoinFunction(GpuqoPlannerInfo<BitmapsetN>* _info, 
        memo_t* _memo, CPUAlgorithm<BitmapsetN, memo_t>* _alg) 
        : CPUJoinFunction<BitmapsetN,memo_t>(_info, _memo, _alg) {}

    virtual JoinRelationCPU<BitmapsetN> *operator()(int level, bool try_swap,
                JoinRelationCPU<BitmapsetN> &left_rel, 
                JoinRelationCPU<BitmapsetN> &right_rel)
    {
        if (CPUJoinFunction<BitmapsetN,memo_t>::alg->check_join(level, left_rel, right_rel)){
            JoinRelationCPU<BitmapsetN> *join_rel1, *join_rel2;
            bool new_joinrel;
            new_joinrel = do_join(level, join_rel1, 
                                left_rel, right_rel, CPUJoinFunction<BitmapsetN,memo_t>::info, *CPUJoinFunction<BitmapsetN,memo_t>::memo);
            CPUJoinFunction<BitmapsetN,memo_t>::alg->post_join(level, new_joinrel, *join_rel1, left_rel,  right_rel);
            if (try_swap){
                new_joinrel = do_join(level, join_rel2, right_rel, 
                                    left_rel, CPUJoinFunction<BitmapsetN,memo_t>::info, *CPUJoinFunction<BitmapsetN,memo_t>::memo);
                CPUJoinFunction<BitmapsetN,memo_t>::alg->post_join(level, new_joinrel, *join_rel2, left_rel, right_rel);

                if (join_rel1->cost.total < join_rel2->cost.total)
                    return join_rel1;
                else
                    return join_rel2;
            } else {
                return join_rel1;
            }
        } else {
            return NULL;
        }
    }
};

template<typename BitmapsetN, typename memo_t>
QueryTree<BitmapsetN>* gpuqo_cpu_sequential(GpuqoPlannerInfo<BitmapsetN>* info, 
                                CPUAlgorithm<BitmapsetN, memo_t> *algorithm)
{
    
    DECLARE_TIMING(gpuqo_cpu_sequential);
    START_TIMING(gpuqo_cpu_sequential);

    memo_t memo;
    QueryTree<BitmapsetN>* out = NULL;

    for(int i=0; i<info->n_rels; i++){
        JoinRelationCPU<BitmapsetN> *jr = new JoinRelationCPU<BitmapsetN>;
        jr->id = info->base_rels[i].id; 
        jr->left_rel_id = 0; 
        jr->left_rel_ptr = NULL; 
        jr->right_rel_id = 0; 
        jr->right_rel_ptr = NULL; 
        jr->cost = cost_baserel(info->base_rels[i]); 
        jr->width = info->base_rels[i].width; 
        jr->rows = info->base_rels[i].rows; 
        jr->edges = info->edge_table[i];
        memo.insert(std::make_pair(info->base_rels[i].id, jr));
    }

    SequentialJoinFunction<BitmapsetN, memo_t> join_func(info, &memo, algorithm);

    algorithm->init(info, &memo, &join_func);
    
    algorithm->enumerate();

#ifdef GPUQO_PRINT_N_JOINS
    printf("The algorithm did %u joins over %u checks (1:%.2f)\n", 
            algorithm->get_n_joins(), algorithm->get_n_checks(),
           (double) algorithm->get_n_checks() / algorithm->get_n_joins());
#endif 

    BitmapsetN final_joinrel_id = BitmapsetN(0);

    if (info->n_rels == info->n_iters){ // normal DP
        for (int i = 0; i < info->n_rels; i++)
            final_joinrel_id |= info->base_rels[i].id;
    } else { // IDP
        float min_cost = INFF;
        for (auto iter=memo.begin(); iter != memo.end(); ++iter){
            if (iter->first.size() == info->n_iters 
                && iter->second->cost.total < min_cost
            ){
                min_cost = iter->second->cost.total;
                final_joinrel_id = iter->first;
            }
        }
    }
    
    auto final_joinrel_pair = memo.find(final_joinrel_id);
    if (final_joinrel_pair != memo.end())
        build_query_tree(final_joinrel_pair->second, &out);

    // delete all dynamically allocated memory
    for (auto iter=memo.begin(); iter != memo.end(); ++iter){
        LOG_DEBUG("%u: %u %u (%f)\n", 
            iter->first.toUint(),
            iter->second->left_rel_id.toUint(),
            iter->second->right_rel_id.toUint(),
            iter->second->cost.total
        );
        delete iter->second;
    }

    STOP_TIMING(gpuqo_cpu_sequential);
    PRINT_TIMING(gpuqo_cpu_sequential);

    return out;
}

template QueryTree<Bitmapset32>* gpuqo_cpu_sequential<Bitmapset32>
        (GpuqoPlannerInfo<Bitmapset32>*, CPUAlgorithm<Bitmapset32, hashtable_memo_t<Bitmapset32> >*);
template QueryTree<Bitmapset64>* gpuqo_cpu_sequential<Bitmapset64>
        (GpuqoPlannerInfo<Bitmapset64>*, CPUAlgorithm<Bitmapset64, hashtable_memo_t<Bitmapset64>>*);
