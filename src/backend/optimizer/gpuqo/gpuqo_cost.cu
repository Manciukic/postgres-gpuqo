/*------------------------------------------------------------------------
 *
 * gpuqo_cost.cu
 *      definition of the common cost-computing function
 *
 * src/backend/optimizer/gpuqo/gpuqo_cost.cu
 *
 *-------------------------------------------------------------------------
 */

#include <cmath>
#include <cstdint>

#include "optimizer/gpuqo_common.h"

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"


__host__ __device__
bool has_useful_index(JoinRelation &left_rel, JoinRelation &right_rel,
                    GpuqoPlannerInfo* info){
    if (BMS64_SIZE(right_rel.id) != 1)  // inner must be base rel
        return false;
    // -1 since it's 1-indexed, 
    // another -1 since relation with id 0b10 is at index 0 and so on
    int baserel_right_idx = BMS64_LOWEST_POS(right_rel.id) - 2;
    
    return BMS64_INTERSECTS(
        left_rel.id, 
        info->indexed_edge_table[baserel_right_idx]
    );
}

__host__ __device__
double baserel_cost(BaseRelation &base_rel){
    return BASEREL_COEFF * base_rel.tuples;
}

__host__ __device__
double 
compute_join_cost(JoinRelation &join_rel, JoinRelation &left_rel,
                    JoinRelation &right_rel, GpuqoPlannerInfo* info)
{
    double hash_cost = HASHJOIN_COEFF * join_rel.rows + left_rel.cost + right_rel.cost;
    double nl_cost = left_rel.cost + left_rel.rows * right_rel.cost;
    double inl_cost;

    if (has_useful_index(left_rel, right_rel, info)){
        inl_cost = left_rel.cost + INDEXSCAN_COEFF * left_rel.rows * max(join_rel.rows/left_rel.rows, 1.0);
    } else{
        inl_cost = INFD;
    }

    // explicit sort merge
    double sm_cost = (left_rel.cost + right_rel.cost
                        + SORT_COEFF * left_rel.rows * log(left_rel.rows)
                        + SORT_COEFF * right_rel.rows * log(right_rel.rows)
    );

    return min(min(hash_cost, nl_cost), min(inl_cost, sm_cost));
}

__host__ __device__
double 
estimate_join_rows(JoinRelation &join_rel, JoinRelation &left_rel,
                    JoinRelation &right_rel, GpuqoPlannerInfo* info) 
{
    double sel = 1.0;
    
    // for each ec that involves any baserel on the left and on the right,
    // get its selectivity.
    // NB: one equivalence class may only apply a selectivity once so the lowest
    // matching id on both sides is kept
    EqClassInfo* ec = info->eq_classes;
    while (ec != NULL){
        RelationID match_l = BMS64_INTERSECTION(ec->relids, left_rel.id);
        RelationID match_r = BMS64_INTERSECTION(ec->relids, right_rel.id);

        if (match_l != BMS64_EMPTY && match_r != BMS64_EMPTY){
            // more than one on the same equivalence class may match
            // just take the lowest one (already done in BMS64_SET_ALL_LOWER)

            int idx_l = BMS64_SIZE(
                BMS64_INTERSECTION(
                    BMS64_SET_ALL_LOWER(match_l),
                    ec->relids
                )
            );
            int idx_r = BMS64_SIZE(
                BMS64_INTERSECTION(
                    BMS64_SET_ALL_LOWER(match_r),
                    ec->relids
                )
            );
            int size = BMS64_SIZE(ec->relids);

            sel *= ec->sels[idx_l*size+idx_r];
        }
        ec = ec->next;
    }
    
    double rows = sel * left_rel.rows * right_rel.rows;

    // clamp the number of rows
    return rows > 1 ? round(rows) : 1;
}
