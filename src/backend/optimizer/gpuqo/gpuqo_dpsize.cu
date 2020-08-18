/*------------------------------------------------------------------------
 *
 * gpuqo_dpsize.cu
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsize.cu
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

#include "optimizer/gpuqo.cuh"
#include "optimizer/gpuqo_timing.cuh"
#include "optimizer/gpuqo_debug.cuh"
#include "optimizer/gpuqo_cost.cuh"
#include "optimizer/gpuqo_filter.cuh"

#define KB 1024ULL
#define MB (KB*1024)
#define GB (MB*1024)
#define RELSIZE (sizeof(JoinRelation)+sizeof(RelationID))

int gpuqo_dpsize_min_scratchpad_size_mb;
int gpuqo_dpsize_max_scratchpad_size_mb;
int gpuqo_dpsize_max_memo_size_mb;

/* unrankDPSize
 *
 *	 unrank algorithm for DPsize GPU variant
 */
struct unrankDPSize : public thrust::unary_function< uint64_t,thrust::tuple<RelationID, JoinRelation> >
{
    thrust::device_ptr<RelationID> memo_keys;
    thrust::device_ptr<JoinRelation> memo_vals;
    thrust::device_ptr<uint64_t> partition_offsets;
    thrust::device_ptr<uint64_t> partition_sizes;
    int iid;
    uint64_t offset;
public:
    unrankDPSize(
        thrust::device_ptr<RelationID> _memo_keys,
        thrust::device_ptr<JoinRelation> _memo_vals,
        thrust::device_ptr<uint64_t> _partition_offsets,
        thrust::device_ptr<uint64_t> _partition_sizes,
        int _iid,
        uint64_t _offset
    ) : memo_keys(_memo_keys), memo_vals(_memo_vals), 
        partition_offsets(_partition_offsets), 
        partition_sizes(_partition_sizes), iid(_iid), offset(_offset)
    {}

    __device__
    thrust::tuple<RelationID, JoinRelation> operator()(uint64_t cid) 
    {
        uint64_t lp = 0;
        uint64_t rp = iid - 2;
        uint64_t o = partition_sizes[lp] * partition_sizes[rp];
        cid += offset;

        while (cid >= o){
            cid -= o;
            lp++;
            rp--;
            o = partition_sizes[lp] * partition_sizes[rp];
        }

        uint64_t l = cid / partition_sizes[rp];
        uint64_t r = cid % partition_sizes[rp];

        RelationID relid;
        JoinRelation jr;

        jr.left_relation_idx = partition_offsets[lp] + l;
        jr.right_relation_idx = partition_offsets[rp] + r;

#ifdef GPUQO_DEBUG
        printf("%llu: %llu %llu\n", 
            cid, 
            jr.left_relation_idx,
            jr.right_relation_idx
        );
#endif
        
        JoinRelation left_rel = memo_vals[jr.left_relation_idx];
        JoinRelation right_rel = memo_vals[jr.right_relation_idx];
        
        jr.edges = BMS64_UNION(left_rel.edges, right_rel.edges);
        jr.left_relation_id = left_rel.id;
        jr.right_relation_id = right_rel.id;

        relid = BMS64_UNION(left_rel.id, right_rel.id);
        jr.id = relid;

        return thrust::tuple<RelationID, JoinRelation>(relid, jr);
    }
};

void buildQueryTree(uint64_t idx, 
                    uninit_device_vector_relid &gpu_memo_keys,
                    uninit_device_vector_joinrel &gpu_memo_vals,
                    QueryTree **qt)
{
    JoinRelation jr = gpu_memo_vals[idx];

    (*qt) = (QueryTree*) malloc(sizeof(QueryTree));
    (*qt)->id = jr.id;
    (*qt)->left = NULL;
    (*qt)->right = NULL;
    (*qt)->rows = jr.rows;
    (*qt)->cost = jr.cost;

    if (jr.left_relation_idx == 0 && jr.right_relation_idx == 0)
        return;

    buildQueryTree(jr.left_relation_idx, gpu_memo_keys, gpu_memo_vals, &((*qt)->left));
    buildQueryTree(jr.right_relation_idx, gpu_memo_keys, gpu_memo_vals, &((*qt)->right));
}

/* gpuqo_dpsize
 *
 *	 GPU query optimization using the DP size variant.
 */
extern "C"
QueryTree*
gpuqo_dpsize(BaseRelation base_rels[], int n_rels, EdgeInfo edge_table[])
{
    DECLARE_TIMING(gpuqo_dpsize);
    DECLARE_NV_TIMING(init);
    DECLARE_NV_TIMING(execute);
    
    START_TIMING(gpuqo_dpsize);
    START_TIMING(init);

    uint64_t min_scratchpad_capacity = gpuqo_dpsize_min_scratchpad_size_mb * MB / RELSIZE;
    uint64_t max_scratchpad_capacity = gpuqo_dpsize_max_scratchpad_size_mb * MB / RELSIZE;
    uint64_t prune_threshold = max_scratchpad_capacity * 2 / 3;
    uint64_t max_memo_size = gpuqo_dpsize_max_memo_size_mb * MB / RELSIZE;

    uint64_t memo_size = std::min((uint64_t) 1ULL<<n_rels, max_memo_size);
    
    thrust::device_vector<BaseRelation> gpu_base_rels(base_rels, base_rels + n_rels);
    thrust::device_vector<EdgeInfo> gpu_edge_table(edge_table, edge_table + n_rels*n_rels);
    uninit_device_vector_relid gpu_memo_keys(memo_size);
    uninit_device_vector_joinrel gpu_memo_vals(memo_size);
    thrust::host_vector<uint64_t> partition_offsets(n_rels);
    thrust::host_vector<uint64_t> partition_sizes(n_rels);
    thrust::device_vector<uint64_t> gpu_partition_offsets(n_rels);
    thrust::device_vector<uint64_t> gpu_partition_sizes(n_rels);
    QueryTree* out = NULL;

    for(int i=0; i<n_rels; i++){
        gpu_memo_keys[i] = base_rels[i].id;

        JoinRelation t;
        t.id = base_rels[i].id;
        t.left_relation_idx = 0; 
        t.left_relation_id = 0; 
        t.right_relation_idx = 0; 
        t.right_relation_id = 0; 
        t.cost = 0.2*base_rels[i].rows; 
        t.rows = base_rels[i].rows; 
        t.edges = base_rels[i].edges;
        gpu_memo_vals[i] = t;

        partition_sizes[i] = i == 0 ? n_rels : 0;
        partition_offsets[i] = i == 1 ? n_rels : 0;
    }
    gpu_partition_offsets = partition_offsets;
    gpu_partition_sizes = partition_sizes;

    // scratchpad size is increased on demand, starting from a minimum capacity
    uninit_device_vector_relid gpu_scratchpad_keys;
    gpu_scratchpad_keys.reserve(min_scratchpad_capacity);
    uninit_device_vector_joinrel gpu_scratchpad_vals;
    gpu_scratchpad_vals.reserve(min_scratchpad_capacity);

    STOP_TIMING(init);

#ifdef GPUQO_DEBUG
    printVector(gpu_memo_keys.begin(), gpu_memo_keys.begin() + n_rels);
    printVector(gpu_memo_vals.begin(), gpu_memo_vals.begin() + n_rels);    
#endif

    START_TIMING(execute);
    try{ // catch any exception in thrust
        DECLARE_NV_TIMING(iter_init);
        DECLARE_NV_TIMING(copy_pruned);
        DECLARE_NV_TIMING(unrank);
        DECLARE_NV_TIMING(filter);
        DECLARE_NV_TIMING(sort);
        DECLARE_NV_TIMING(compute_prune);
        DECLARE_NV_TIMING(update_offsets);
        DECLARE_NV_TIMING(build_qt);

        // iterate over the size of the resulting joinrel
        for(int i=2; i<=n_rels; i++){
            START_TIMING(iter_init);
            
            // calculate number of combinations of relations that make up 
            // a joinrel of size i
            uint64_t n_combinations = 0;
            for (int j=1; j<i; j++){
                n_combinations += partition_sizes[j-1] * partition_sizes[i-j-1];
            }

#if defined(GPUQO_DEBUG) || defined(GPUQO_PROFILE)
            printf("\nStarting iteration %d: %d combinations\n", i, n_combinations);
#endif

            // If < max_scratchpad_capacity I may need to increase it
            if (n_combinations < max_scratchpad_capacity){
                // allocate temp scratchpad
                // prevent unneeded copy of old values in case new memory should be
                // allocated
                gpu_scratchpad_keys.resize(0); 
                gpu_scratchpad_keys.resize(n_combinations);
                // same as before
                gpu_scratchpad_vals.resize(0); 
                gpu_scratchpad_vals.resize(n_combinations);
            } else{
                // If >= max_scratchpad_capacity only need to increase up to
                // max_scratchpad_capacity, if not already done so
                if (gpu_scratchpad_keys.size() < max_scratchpad_capacity){
                    gpu_scratchpad_keys.resize(0); 
                    gpu_scratchpad_keys.resize(max_scratchpad_capacity);
                }
                if (gpu_scratchpad_vals.size() < max_scratchpad_capacity){
                    gpu_scratchpad_vals.resize(0); 
                    gpu_scratchpad_vals.resize(max_scratchpad_capacity);
                }
            }

            STOP_TIMING(iter_init);

            // offset of cid for the enumeration
            uint64_t offset = 0;

            // count how many times I had to sort+prune
            // NB: either a really high number of tables or a small scratchpad
            //     is required to make multiple sort+prune steps
            int pruning_iter = 0;

            // size of the already filtered joinrels at the beginning of the 
            // scratchpad
            uint64_t temp_size;

            // until I go through every possible iteration
            while (offset < n_combinations){
                if (pruning_iter != 0){
                    // if I already pruned at least once, I need to fetch those 
                    // partially pruned samples from the memo to the scratchpad
                    START_TIMING(copy_pruned);
                    thrust::copy(
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_memo_keys.begin()+partition_offsets[i-1],
                            gpu_memo_vals.begin()+partition_offsets[i-1]
                        )),
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_memo_keys.begin()+partition_offsets[i-1]+partition_sizes[i-1],
                            gpu_memo_vals.begin()+partition_offsets[i-1]+partition_sizes[i-1]
                        )),
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_scratchpad_keys.begin(),
                            gpu_scratchpad_vals.begin()
                        ))
                    );

                    // I now have already ps[i-1] joinrels in the sratchpad
                    temp_size = partition_sizes[i-1];
                    STOP_TIMING(copy_pruned);
                } else {
                    // scratchpad is initially empty
                    temp_size = 0;
                }

                // until there are no more combinations or the scratchpad is
                // too full (threshold of 0.5 max capacity is arbitrary)
                while (offset < n_combinations 
                            && temp_size < prune_threshold)
                {
                    // how many combinations I will try at this iteration
                    uint64_t chunk_size;

                    if (n_combinations - offset < max_scratchpad_capacity - temp_size){
                        // all remaining
                        chunk_size = n_combinations - offset;
                    } else{
                        // up to scratchpad capacity
                        chunk_size = max_scratchpad_capacity - temp_size;
                    }

                    // give possibility to user to interrupt
                    CHECK_FOR_INTERRUPTS();

                    START_TIMING(unrank);
                    // fill scratchpad
                    thrust::tabulate(
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_scratchpad_keys.begin()+temp_size,
                            gpu_scratchpad_vals.begin()+temp_size
                        )),
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_scratchpad_keys.begin()+(chunk_size+temp_size),
                            gpu_scratchpad_vals.begin()+(chunk_size+temp_size)
                        )),
                        unrankDPSize(
                            gpu_memo_keys.data(), 
                            gpu_memo_vals.data(), 
                            gpu_partition_offsets.data(), 
                            gpu_partition_sizes.data(), 
                            i,
                            offset
                        )
                    );
                    STOP_TIMING(unrank);

#ifdef GPUQO_DEBUG
                    printf("After tabulate\n");
                    printVector(
                        gpu_scratchpad_keys.begin()+temp_size, 
                        gpu_scratchpad_keys.begin()+(temp_size+chunk_size)
                    );
                    printVector(
                        gpu_scratchpad_vals.begin()+temp_size, 
                        gpu_scratchpad_vals.begin()+(temp_size+chunk_size)
                    );
#endif
                    // give possibility to user to interrupt
                    CHECK_FOR_INTERRUPTS();

                    START_TIMING(filter);
                    // filter out invalid pairs
                    auto newEnd = thrust::remove_if(
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_scratchpad_keys.begin()+temp_size,
                            gpu_scratchpad_vals.begin()+temp_size
                        )),
                        thrust::make_zip_iterator(thrust::make_tuple(
                            gpu_scratchpad_keys.begin()+(temp_size+chunk_size),
                            gpu_scratchpad_vals.begin()+(temp_size+chunk_size)
                        )),
                        filterJoinedDisconnected(
                            gpu_memo_keys.data(), 
                            gpu_memo_vals.data(),
                            gpu_base_rels.data(), 
                            n_rels,
                            gpu_edge_table.data()
                        )
                    );

                    STOP_TIMING(filter);

#ifdef GPUQO_DEBUG
                    printf("After remove_if\n");
                    printVector(
                        gpu_scratchpad_keys.begin()+temp_size, 
                        newEnd.get_iterator_tuple().get<0>()
                    );
                    printVector(
                        gpu_scratchpad_vals.begin()+temp_size, 
                        newEnd.get_iterator_tuple().get<1>()
                    );
#endif
                    // get how many rels remain after filter and add it to 
                    // temp_size
                    temp_size += thrust::distance(
                        gpu_scratchpad_keys.begin()+temp_size,
                        newEnd.get_iterator_tuple().get<0>()
                    );

                    // increase offset for next iteration and/or for exit check 
                    offset += chunk_size;
                } // filtering loop: while(off<n_comb && temp_s < cap)

                // I now have either all valid combinations or 0.5 scratchpad
                // capacity combinations. In the first case, I will prune once
                // and exit. In the second case, there are still some 
                // combinations to try so I will prune this partial result and
                // then reload it back in the scratchpad to finish execution

                // give possibility to user to interrupt
                CHECK_FOR_INTERRUPTS();

                START_TIMING(sort);

                // sort by key (prepare for pruning)
                thrust::sort_by_key(
                    gpu_scratchpad_keys.begin(),
                    gpu_scratchpad_keys.begin() + temp_size,
                    gpu_scratchpad_vals.begin()
                );
    
                STOP_TIMING(sort);
    
#ifdef GPUQO_DEBUG
                printf("After sort_by_key\n");
                printVector(gpu_scratchpad_keys.begin(), gpu_scratchpad_keys.begin() + temp_size);
                printVector(gpu_scratchpad_vals.begin(), gpu_scratchpad_vals.begin() + temp_size);
#endif
                // give possibility to user to interrupt
                CHECK_FOR_INTERRUPTS();
    
                START_TIMING(compute_prune);
    
                // calculate cost, prune and copy to table
                auto out_iters = thrust::reduce_by_key(
                    gpu_scratchpad_keys.begin(),
                    gpu_scratchpad_keys.begin() + temp_size,
                    thrust::make_transform_iterator(
                        gpu_scratchpad_vals.begin(),
                        joinCost(
                            gpu_memo_keys.data(), 
                            gpu_memo_vals.data(),
                            gpu_base_rels.data(),
                            n_rels,
                            gpu_edge_table.data()
                        )
                    ),
                    gpu_memo_keys.begin()+partition_offsets[i-1],
                    gpu_memo_vals.begin()+partition_offsets[i-1],
                    thrust::equal_to<uint64_t>(),
                    thrust::minimum<JoinRelation>()
                );
    
                STOP_TIMING(compute_prune);
    
#ifdef GPUQO_DEBUG
                printf("After reduce_by_key\n");
                printVector(gpu_memo_keys.begin(), out_iters.first);
                printVector(gpu_memo_vals.begin(), out_iters.second);
#endif
    
                START_TIMING(update_offsets);
    
                // update ps and po
                partition_sizes[i-1] = thrust::distance(
                    gpu_memo_keys.begin()+partition_offsets[i-1],
                    out_iters.first
                );
                gpu_partition_sizes[i-1] = partition_sizes[i-1];
                
                if (i < n_rels){
                    partition_offsets[i] = partition_sizes[i-1] + partition_offsets[i-1];
                    gpu_partition_offsets[i] = partition_offsets[i];
                }
    
                STOP_TIMING(update_offsets);
    
#ifdef GPUQO_DEBUG
                printf("After partition_*\n");
                printVector(partition_sizes.begin(), partition_sizes.end());
                printVector(partition_offsets.begin(), partition_offsets.end());
#endif
                pruning_iter++;
            } // pruning loop: while(offset<n_combinations)

#ifdef GPUQO_DEBUG
            printf("It took %d pruning iterations", pruning_iter);
#endif
            
            PRINT_CHECKPOINT_TIMING(iter_init);
            PRINT_CHECKPOINT_TIMING(copy_pruned);
            PRINT_CHECKPOINT_TIMING(unrank);
            PRINT_CHECKPOINT_TIMING(filter);
            PRINT_CHECKPOINT_TIMING(sort);
            PRINT_CHECKPOINT_TIMING(compute_prune);
            PRINT_CHECKPOINT_TIMING(update_offsets);
        } // dpsize loop: for i = 2..n_rels

        START_TIMING(build_qt);
            
        buildQueryTree(partition_offsets[n_rels-1], gpu_memo_keys, gpu_memo_vals, &out);
    
        STOP_TIMING(build_qt);
    
        PRINT_TOTAL_TIMING(iter_init);
        PRINT_TOTAL_TIMING(copy_pruned);
        PRINT_TOTAL_TIMING(unrank);
        PRINT_TOTAL_TIMING(filter);
        PRINT_TOTAL_TIMING(sort);
        PRINT_TOTAL_TIMING(compute_prune);
        PRINT_TOTAL_TIMING(update_offsets);
        PRINT_TOTAL_TIMING(build_qt);
    } catch(thrust::system_error err){
        printf("Thrust %d: %s", err.code().value(), err.what());
    }

    STOP_TIMING(execute);
    STOP_TIMING(gpuqo_dpsize);

    PRINT_TIMING(gpuqo_dpsize);
    PRINT_TIMING(init);
    PRINT_TIMING(execute);

    return out;
}