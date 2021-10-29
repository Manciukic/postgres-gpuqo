/*------------------------------------------------------------------------
 *
 * gpuqo_dpsub_bicc.cuh
 *      device functions for BiCC decomposition
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpsub_tree.cuh
 *
 *-------------------------------------------------------------------------
 */

#ifndef GPUQO_DPSUB_ENUM_BICC_CUH
#define GPUQO_DPSUB_ENUM_BICC_CUH

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_dpsub.cuh"

template<typename BitmapsetN>
uint32_t dpsub_bicc_evaluation(int iter, uint64_t n_remaining_sets,
                                uint64_t offset, uint32_t n_pending_sets, 
                                dpsub_iter_param_t<BitmapsetN> &params);

template<typename BitmapsetN>
struct bfs_bicc_bfs_lv_ret {
    uint32_t l;
    uint32_t vid_low;
    BitmapsetN V_u;
};

template<typename BitmapsetN>
__device__ 
static bfs_bicc_bfs_lv_ret<BitmapsetN> bfs_bicc_bfs_lv(const uint32_t* L, 
                                uint32_t v, uint32_t u,
                                BitmapsetN invalid,
                                BitmapsetN relid, const BitmapsetN* edges)
{
    BitmapsetN visited = invalid | (~relid);
    BitmapsetN Q = BitmapsetN::nth(u);
    BitmapsetN V_u = BitmapsetN::nth(u);

    visited.set(u);
    visited.set(v);

    uint32_t vid_low = u;

    while (!Q.empty()){
        int x = Q.lowestPos();

        BitmapsetN e = edges[x-1] - visited;

        while (!e.empty()){
            int w = e.lowestPos();

            if (L[w] < L[u]){
                return (bfs_bicc_bfs_lv_ret<BitmapsetN>){
                    .l = L[w],
                    .vid_low = 0,
                    .V_u = BitmapsetN(0)
                };
            } else {
                Q.set(w);
                V_u.set(w);
                visited.set(w);
                if (w < vid_low)
                    vid_low = w;
            }

            e.unset(w);
        }

        Q.unset(x);
    }


    return (bfs_bicc_bfs_lv_ret<BitmapsetN>){
        .l = L[u],
        .vid_low = vid_low,
        .V_u = V_u
    };
}

template<typename BitmapsetN>
__device__ 
static void bfs_bicc_bfs(BitmapsetN relid, const BitmapsetN* edges,
                            volatile uint32_t* P, volatile uint32_t* L, 
                            volatile BitmapsetN* LQ)
{
    __shared__ BitmapsetN shared_visited[BLOCK_DIM/WARP_SIZE];

    int t_off = threadIdx.x >> 5;

    volatile BitmapsetN* visited = shared_visited + t_off;
    
    if (LANE_ID == 0){
        uint32_t r = relid.lowestPos();
        P[r] = r;
        L[r] = 0;
        LQ[0] = BitmapsetN::nth(r);
        *visited = BitmapsetN::nth(r) | (~relid);
    }

    __syncwarp();

    for (int i=0; i<relid.size(); i++){
        BitmapsetN lq = LQ[i];
        for (int x=LANE_ID; x < BitmapsetN::SIZE; x += WARP_SIZE){
            int pos = lq.isSet(x) ? x-1 : 0;
            BitmapsetN e = edges[pos] - (BitmapsetN)*visited;
            __syncwarp(); // protect read on *visited

            if (lq.isSet(x)){
                atomicOr((BitmapsetN*)&LQ[i+1], e);
                atomicOr((BitmapsetN*)visited, e);

                LOG_DEBUG("bfs_bicc_bfs(%u): i=%d, x=%d, e=%u\n", 
                            relid.toUint(), i, x, e.toUint());

                while (!e.empty()){
                    int w = e.lowestPos();

                    L[w] = i+1; // same for all threads, concurrency not important
                    P[w] = x;   // different but not important which one wins

                    e.unset(w);
                }
            } else {
                __syncwarp(); //balance syncs
            }
            __syncwarp();
        }
    }
    
}

template<typename BitmapsetN>
__device__
static int bfs_bicc(BitmapsetN relid, const BitmapsetN* edges, BitmapsetN *blocks)
{
    __shared__ uint32_t shared_P[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
    __shared__ uint32_t shared_L[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
    __shared__ uint32_t shared_Low[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
    __shared__ uint32_t shared_Par[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
    __shared__ BitmapsetN shared_LQ[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
    __shared__ BitmapsetN shared_invalid[BLOCK_DIM/WARP_SIZE];

    int t_off = threadIdx.x >> 5;

    uint32_t *P = shared_P + t_off*BitmapsetN::SIZE;
    uint32_t *L = shared_L + t_off*BitmapsetN::SIZE;
    uint32_t *Low = shared_Low + t_off*BitmapsetN::SIZE;
    uint32_t *Par = shared_Par + t_off*BitmapsetN::SIZE;
    BitmapsetN *LQ = shared_LQ + t_off*BitmapsetN::SIZE;
    BitmapsetN *invalid = shared_invalid + t_off;

    for (uint32_t u=LANE_ID; u < BitmapsetN::SIZE; u += WARP_SIZE){
        P[u] = 0;
        L[u] = 0;
        LQ[u] = BitmapsetN(0);
        Low[u] = u;
        Par[u] = u;
    }

    if (LANE_ID == 0)
        *invalid = BitmapsetN(0);

    int n_blocks = 0;

    bfs_bicc_bfs(relid, edges, P, L, LQ);

    for (uint32_t u=LANE_ID; u < BitmapsetN::SIZE; u += WARP_SIZE){
        LOG_DEBUG("L[%d]=%u\tP[%d]=%u\n", u, L[u], u, P[u]);
    }

    for (int i = relid.size()-1; i>0; i--){
        bfs_bicc_bfs_lv_ret<BitmapsetN> s;
        for (uint32_t u=LANE_ID; u < BitmapsetN::SIZE; u += WARP_SIZE){
            uint32_t v = P[u];
            bool p1 = LQ[i].isSet(u) && Par[u] == u;
            bool p2 = false;

            if (p1){
                LOG_DEBUG("bfs_bicc(%u): iter %d, node %u (parent: %u)\n",
                                                                relid.toUint(), i, u, v);

                s = bfs_bicc_bfs_lv(L, v, u, *invalid, relid, edges);

                LOG_DEBUG("bfs_bicc_bfs_lv(%u, %u, %u): "
                            "l=%u, vid_low=%u, V_u=%u\n",
                            relid.toUint(), v, u, s.l, s.vid_low, s.V_u.toUint());

                p2 = (s.l >= L[u]) && ((s.V_u & LQ[i]).lowestPos() == u);    
            }
            
            unsigned pthBlt = __ballot_sync(WARP_MASK, p2);
            int wScan = __popc(pthBlt & LANE_MASK_LE);

            if (p2){
                int idx = n_blocks+wScan-1;
                blocks[idx] = s.V_u | BitmapsetN::nth(v);
                LOG_DEBUG("[%u] %u is articulation (block[%d]: %u)\n", 
                            relid.toUint(), v, idx, blocks[idx].toUint());
                while (!s.V_u.empty()){
                    int w = s.V_u.lowestPos();
                    Low[w] = s.vid_low;
                    Par[w] = v;
                    atomicOr(invalid, BitmapsetN::nth(w));

                    s.V_u.unset(w);
                }
            }
            int new_blocks = __popc(pthBlt); 
            n_blocks += new_blocks;
            __syncwarp();
        }
    }

    return n_blocks;
}

template<typename BitmapsetN>
struct dpsubEnumerateBiCC {
    __device__
    JoinRelation<BitmapsetN> operator()(BitmapsetN relid, 
                        uint32_t cid, 
                        int n_splits, HashTableDpsub<BitmapsetN> &memo, 
                        GpuqoPlannerInfo<BitmapsetN>* info)
    { 
        JoinRelation<BitmapsetN> jr_out;
        jr_out.cost.total = INFF;
        jr_out.cost.startup = INFF;

        Assert(n_splits == WARP_SIZE);

        int t_off = threadIdx.x >> 5;

        Assert(blockDim.x == BLOCK_DIM);
        volatile __shared__ BitmapsetN ctxStack[BLOCK_DIM];
        ccc_stack_t<BitmapsetN> stack;
        stack.ctxStack = ctxStack;
        stack.stackTop = 0;

        __shared__ BitmapsetN shared_blocks[BitmapsetN::SIZE*BLOCK_DIM/WARP_SIZE];
        BitmapsetN* blocks = shared_blocks + t_off*BitmapsetN::SIZE;

        int n_blocks = bfs_bicc(relid, info->edge_table, blocks);

        LOG_DEBUG("%u has %d blocks\n", relid.toUint(), n_blocks);

        uint_t<BitmapsetN> n_possible_joins = 0;
        for (int i=0; i<n_blocks; i++){
            n_possible_joins += (((uint_t<BitmapsetN>)1) << blocks[i].size()) - 2;
        }

        LOG_DEBUG("relid=%u: n_possible_joins=%lu\n", relid.toUint(), (uint64_t)n_possible_joins);

        uint_t<BitmapsetN> n_joins = ceil_div(n_possible_joins, n_splits);
        uint_t<BitmapsetN> from_i = cid*n_joins;
        uint_t<BitmapsetN> to_i   = (cid+1)*n_joins;
        uint32_t i_block = 0;
        uint_t<BitmapsetN> psum = (((uint_t<BitmapsetN>)1) << blocks[i_block].size()) - 2;
        uint_t<BitmapsetN> prev_psum = 0;

        for (uint_t<BitmapsetN> i = from_i; i < to_i; i++){
            BitmapsetN l, r;
            bool valid = false;

            if (i < n_possible_joins){
                while (i >= psum){
                    prev_psum = psum;
                    psum += (1 << blocks[++i_block].size()) - 2;
                }
                
                BitmapsetN id = BitmapsetN(i - prev_psum + 1);
                BitmapsetN block_left_id = expandToMask(id, blocks[i_block]);
                BitmapsetN block_right_id = blocks[i_block] - block_left_id;

                LOG_DEBUG("relid=%u, i=%lu: id=%u, block[%d]=%u, bl=%u, br=%u\n",
                            relid.toUint(), (uint64_t)i, id.toUint(), i_block, blocks[i_block].toUint(), 
                            block_left_id.toUint(), block_right_id.toUint());

                l = grow(block_left_id.lowest(), 
                            relid - block_right_id, 
                            info->edge_table);
                r = grow(block_right_id.lowest(), 
                            relid - block_left_id, 
                            info->edge_table);
                
                valid = (l|r) == relid;
            }
            
            try_join<BitmapsetN,false,false,CCC_DISABLED>(relid, jr_out, l, r,
                                                     valid, stack, memo, info);
        }

        if (LANE_ID < stack.stackTop){
            int pos = W_OFFSET + stack.stackTop - LANE_ID - 1;
            BitmapsetN l = stack.ctxStack[pos];
            BitmapsetN r = relid - l;

            LOG_DEBUG("[%d: %d] Emptying stack (%d): l=%u, r=%u\n", W_OFFSET, LANE_ID, pos, l.toUint(), r.toUint());

            JoinRelation<BitmapsetN> left_rel = *memo.lookup(l);
            JoinRelation<BitmapsetN> right_rel = *memo.lookup(r);
            do_join(jr_out, l, left_rel, r, right_rel, info);
        }


        return jr_out;
    }
};

#endif              // GPUQO_DPSUB_ENUM_BICC_CUH
