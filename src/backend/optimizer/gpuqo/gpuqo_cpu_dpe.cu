/*------------------------------------------------------------------------
 *
 * gpuqo_cpu_dpe.cu
 *      Generic implementation of the DPE CPU algorithm.
 *
 * src/backend/optimizer/gpuqo/gpuqo_cpu_dpe.cu
 *
 *-------------------------------------------------------------------------
 */

#include <list>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <cmath>
#include <cstdint>
#include "pthread.h"
#include <stdio.h>
#include <errno.h>

#include "optimizer/gpuqo_common.h"

#include "gpuqo.cuh"
#include "gpuqo_timing.cuh"
#include "gpuqo_debug.cuh"
#include "gpuqo_cost.cuh"
#include "gpuqo_filter.cuh"
#include "gpuqo_cpu_common.cuh"
#include "gpuqo_cpu_dpe.cuh"
#include "gpuqo_dependency_buffer.cuh"

// set by GUC
int gpuqo_dpe_n_threads;
int gpuqo_dpe_pairs_per_depbuf;

template<typename BitmapsetN>
struct DependencyBuffers{
    DependencyBuffer<BitmapsetN>* depbuf_curr;
    DependencyBuffer<BitmapsetN>* depbuf_next;
    pthread_cond_t avail_jobs;
    pthread_cond_t all_threads_waiting;
    pthread_mutex_t depbuf_mutex;
    bool finish;
    int n_waiting;
};

template<typename BitmapsetN>
struct ThreadArgs{
    int id;
    GpuqoPlannerInfo<BitmapsetN>* info;
    hashtable_memo_t<BitmapsetN> *memo;
    DependencyBuffers<BitmapsetN>* depbufs;
};

template<typename BitmapsetN>
static void process_depbuf(DependencyBuffer<BitmapsetN>* depbuf, 
    GpuqoPlannerInfo<BitmapsetN>* info)
{
    DepBufNode<BitmapsetN> *job;

    while ((job = depbuf->pop()) != NULL){
        JoinRelationDPE<BitmapsetN> *memo_join_rel = job->join_rel;

        LOG_DEBUG("Processing %u (%d)\n", 
                memo_join_rel->id.toUint(), memo_join_rel->num_entry.load());

        DepBufNode<BitmapsetN> *first_job = job;
        do {
            LOG_DEBUG("  %u -> %u (%d) %u (%d);\n", memo_join_rel->id.toUint(),
                job->left_rel->id.toUint(), job->left_rel->num_entry.load(), 
                job->right_rel->id.toUint(), job->right_rel->num_entry.load());

            while (job->left_rel->num_entry.load() != 0) 
                ; // busy wait for entries to be ready
            while (job->right_rel->num_entry.load() != 0)
                ; // busy wait for entries to be ready

            JoinRelationDPE<BitmapsetN>* join_rel = make_join_relation(
                *job->left_rel, *job->right_rel, info
            );
            
            if (join_rel->cost.total < memo_join_rel->cost.total){
                // copy only the JoinRelationCPU part, not num_entry
                memo_join_rel->JoinRelationCPU<BitmapsetN>::operator=(*join_rel);
            }

            delete join_rel;
        } while ((job = job->next_join) != first_job);

        memo_join_rel->num_entry--;
        Assert(memo_join_rel->num_entry.load() >= 0);
    }
}

template<typename BitmapsetN>
static void* thread_function(void* _args){
    ThreadArgs<BitmapsetN> *args = (ThreadArgs<BitmapsetN>*) _args;

    DECLARE_TIMING(wait);
    DECLARE_TIMING(execute);

    while(true){
        START_TIMING(wait);
        LOG_DEBUG("[%d] acquiring lock\n", args->id);
        pthread_mutex_lock(&args->depbufs->depbuf_mutex);

        while(args->depbufs->depbuf_curr->empty() && !args->depbufs->finish){
            args->depbufs->n_waiting++;
            LOG_DEBUG("[%d] increased n_waiting: %d\n", 
                        args->id, args->depbufs->n_waiting);

            if (args->depbufs->n_waiting == gpuqo_dpe_n_threads-1)
                pthread_cond_signal(&args->depbufs->all_threads_waiting);

            pthread_cond_wait(&args->depbufs->avail_jobs, 
                                &args->depbufs->depbuf_mutex);
        }

        pthread_mutex_unlock(&args->depbufs->depbuf_mutex);
        LOG_DEBUG("[%d] released lock\n", args->id);
        STOP_TIMING(wait);

        if (args->depbufs->finish)
            break;

        START_TIMING(execute);
        process_depbuf(args->depbufs->depbuf_curr, args->info);
        STOP_TIMING(execute);
    }

    LOG_DEBUG("[%d] acquiring lock\n", args->id);
    pthread_mutex_lock(&args->depbufs->depbuf_mutex);
    LOG_PROFILE("[%d] ", args->id);
    PRINT_TOTAL_TIMING(wait);
    LOG_PROFILE("[%d] ", args->id);
    PRINT_TOTAL_TIMING(execute);
    pthread_mutex_unlock(&args->depbufs->depbuf_mutex);

    return NULL;
}


template<typename BitmapsetN>
class DPEJoinFunction : public CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >{
public:
    pthread_t* threads;
    DependencyBuffers<BitmapsetN> depbufs;    
    ThreadArgs<BitmapsetN>* thread_args;
#ifdef GPUQO_PROFILE
    uint64_t total_job_count;
#endif
    PROTOTYPE_TIMING_CLASS(wait);
    PROTOTYPE_TIMING_CLASS(execute);

    DPEJoinFunction(GpuqoPlannerInfo<BitmapsetN>* _info, 
                hashtable_memo_t<BitmapsetN>* _memo, 
                CPUAlgorithm<BitmapsetN, hashtable_memo_t<BitmapsetN> >* _alg) 
        : CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >(_info, _memo, _alg) 
    {
        INIT_TIMING(wait);
        INIT_TIMING(execute);
    }

    bool submit_join(int level, JoinRelationDPE<BitmapsetN>* &join_rel, 
                JoinRelationDPE<BitmapsetN> &left_rel, 
                JoinRelationDPE<BitmapsetN> &right_rel)
    {
        bool out;
        BitmapsetN relid = left_rel.id | right_rel.id;

        auto &memo = *CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >::memo;

        auto find_iter = memo.find(relid);
        if (find_iter != memo.end()){
            join_rel = (JoinRelationDPE<BitmapsetN>*) find_iter->second;
            out = false;
        } else{
            join_rel = build_join_relation<JoinRelationDPE<BitmapsetN>>(left_rel, right_rel);
            join_rel->num_entry = 0;
            memo.insert(std::make_pair(join_rel->id, join_rel));
            out = true;
        }

    #ifdef USE_ASSERT_CHECKING
        left_rel.referenced = true;
        right_rel.referenced = true;
        Assert(!join_rel->referenced);
    #endif

    #ifdef GPUQO_PROFILE
        total_job_count++;
    #endif 

        depbufs.depbuf_next->push(join_rel, &left_rel, &right_rel);
        depbufs.depbuf_next->push(join_rel, &right_rel, &left_rel);

        LOG_DEBUG("Inserted %u (%d)\n", relid.toUint(), join_rel->num_entry.load());
        if (depbufs.depbuf_next->full()){
            wait_and_swap_depbuf();
        }
    
        return out;
    }

    void help_workers()
    {
        START_TIMING(execute);
        process_depbuf(depbufs.depbuf_curr, CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >::info);
        STOP_TIMING(execute);
    }

    void wait_and_swap_depbuf()
    {
        depbufs.depbuf_next->unify_queues();

        // lend an hand to worker threads
        help_workers();

        START_TIMING(wait);
        // swap depbufs
        LOG_DEBUG("[L] acquiring lock\n");
        pthread_mutex_lock(&depbufs.depbuf_mutex);

        LOG_DEBUG("[L] waiting %d threads\n", gpuqo_dpe_n_threads-1 - depbufs.n_waiting);

        // wait all threads to be done with their current work
        while (depbufs.n_waiting < gpuqo_dpe_n_threads-1){
            pthread_cond_wait(&depbufs.all_threads_waiting, 
                            &depbufs.depbuf_mutex);
        }

        LOG_DEBUG("[L] swapping depbufs\n");

        // swap depbufs
        DependencyBuffer<BitmapsetN>* depbuf_temp = depbufs.depbuf_curr;
        depbufs.depbuf_curr = depbufs.depbuf_next;
        depbufs.depbuf_next = depbuf_temp;
        
        depbufs.n_waiting = 0;
        LOG_DEBUG("[L] zeroed n_waiting: %d\n", depbufs.n_waiting);

        // signal threads that they can start executing
        pthread_cond_broadcast(&depbufs.avail_jobs);

        pthread_mutex_unlock(&depbufs.depbuf_mutex);
        STOP_TIMING(wait);

        // clear next depbuf
        Assert(depbufs.depbuf_next->empty());
        depbufs.depbuf_next->clear();

        LOG_DEBUG("[L] wait 'n' swap done\n");
    }

    void stop_workers()
    {
        START_TIMING(wait);
        pthread_mutex_lock(&depbufs.depbuf_mutex);
        depbufs.finish = true;

        // awake threads to let them realize it's over
        pthread_cond_broadcast(&depbufs.avail_jobs);

        STOP_TIMING(wait);
        LOG_PROFILE("[L] ");
        PRINT_TOTAL_TIMING(wait);
        LOG_PROFILE("[L] ");
        PRINT_TOTAL_TIMING(execute);

        pthread_mutex_unlock(&depbufs.depbuf_mutex);
    }

    // instead of join it is more of a distribution of jobs
    virtual JoinRelationCPU<BitmapsetN> *operator()(int level, bool try_swap,
                            JoinRelationCPU<BitmapsetN> &left_rel, 
                            JoinRelationCPU<BitmapsetN> &right_rel)
    {
        if (CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >::alg->check_join(level, left_rel, right_rel)){
            JoinRelationDPE<BitmapsetN> *join_rel1, *join_rel2;
            bool new_joinrel;
            new_joinrel = submit_join(level, join_rel1, 
                    (JoinRelationDPE<BitmapsetN>&) left_rel, (JoinRelationDPE<BitmapsetN>&) right_rel
            );
            CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >::alg->post_join(level, new_joinrel, *join_rel1, 
                                left_rel,  right_rel);
            if (try_swap){
                new_joinrel = submit_join(level, join_rel2, 
                    (JoinRelationDPE<BitmapsetN>&) left_rel, (JoinRelationDPE<BitmapsetN>&) right_rel
                );
                CPUJoinFunction<BitmapsetN, hashtable_memo_t<BitmapsetN> >::alg->post_join(level, new_joinrel, *join_rel2, 
                                    left_rel, right_rel);
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

template<typename BitmapsetN>
QueryTree<BitmapsetN>* 
gpuqo_cpu_dpe(GpuqoPlannerInfo<BitmapsetN>* info, CPUAlgorithm<BitmapsetN, hashtable_memo_t<BitmapsetN> > *algorithm)
{
    DECLARE_TIMING(gpuqo_cpu_dpe);
    START_TIMING(gpuqo_cpu_dpe);

    hashtable_memo_t<BitmapsetN> memo;
    QueryTree<BitmapsetN>* out = NULL;

    DPEJoinFunction<BitmapsetN> join_func(info, &memo, algorithm);

    join_func.threads = new pthread_t[gpuqo_dpe_n_threads-1];
    join_func.thread_args = new ThreadArgs<BitmapsetN>[gpuqo_dpe_n_threads-1];
#ifdef GPUQO_PROFILE
    join_func.total_job_count = 0;
#endif
    
    join_func.depbufs.finish = false;
    join_func.depbufs.depbuf_curr = new DependencyBuffer<BitmapsetN>(info->n_rels, gpuqo_dpe_pairs_per_depbuf);
    join_func.depbufs.depbuf_next = new DependencyBuffer<BitmapsetN>(info->n_rels, gpuqo_dpe_pairs_per_depbuf);
    join_func.depbufs.n_waiting = 0;
    pthread_cond_init(&join_func.depbufs.avail_jobs, NULL);
    pthread_cond_init(&join_func.depbufs.all_threads_waiting, NULL);
    pthread_mutex_init(&join_func.depbufs.depbuf_mutex, NULL);

    for (int i=0; i<gpuqo_dpe_n_threads-1; i++){
        join_func.thread_args[i].id = i;
        join_func.thread_args[i].info = info;
        join_func.thread_args[i].memo = &memo;
        join_func.thread_args[i].depbufs = &join_func.depbufs;
        
        int ret = pthread_create(&join_func.threads[i], NULL, 
                                thread_function<BitmapsetN>, 
                                (void*) &join_func.thread_args[i]);

        if (ret != 0){
            perror("pthread_create: ");
            return NULL;
        }
    }

    for(int i=0; i<info->n_rels; i++){
        JoinRelationDPE<BitmapsetN> *jr = new JoinRelationDPE<BitmapsetN>;
        jr->id = info->base_rels[i].id; 
        jr->left_rel_id = 0; 
        jr->left_rel_ptr = NULL; 
        jr->right_rel_id = 0; 
        jr->right_rel_ptr = NULL; 
        jr->cost = cost_baserel(info->base_rels[i]); 
        jr->width = info->base_rels[i].width; 
        jr->rows = info->base_rels[i].rows; 
        jr->edges = info->edge_table[i];
        jr->num_entry = 0;
        memo.insert(std::make_pair(info->base_rels[i].id, (JoinRelationCPU<BitmapsetN>*) jr));
    }

    algorithm->init(info, &memo, &join_func);
    
    algorithm->enumerate();

    // finish depbuf_curr and set depbuf_next
    join_func.wait_and_swap_depbuf();
    // help finishing depbuf_next (which is now in depbuf_curr)
    join_func.help_workers();

    // stop worker threads
    join_func.stop_workers();

    // wait threads to exit
    for (int i = 0; i < gpuqo_dpe_n_threads-1; i++){
        pthread_join(join_func.threads[i], NULL);
    }

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
        delete iter->second;
    }

    LOG_PROFILE("%lu pairs have been evaluated\n", join_func.total_job_count);
    
    // TODO move within class
    pthread_cond_destroy(&join_func.depbufs.avail_jobs);
    pthread_cond_destroy(&join_func.depbufs.all_threads_waiting);
    pthread_mutex_destroy(&join_func.depbufs.depbuf_mutex);
    delete[] join_func.threads;
    delete[] join_func.thread_args;

    Assert(join_func.depbufs.depbuf_curr->empty());
    delete join_func.depbufs.depbuf_curr;
    Assert(join_func.depbufs.depbuf_next->empty());
    delete join_func.depbufs.depbuf_next;

    STOP_TIMING(gpuqo_cpu_dpe);
    PRINT_TIMING(gpuqo_cpu_dpe);

    return out;
}

template QueryTree<Bitmapset32>* gpuqo_cpu_dpe<Bitmapset32>(GpuqoPlannerInfo<Bitmapset32>* info, 
    CPUAlgorithm<Bitmapset32, hashtable_memo_t<Bitmapset32>> *algorithm);
template QueryTree<Bitmapset64>* gpuqo_cpu_dpe<Bitmapset64>(GpuqoPlannerInfo<Bitmapset64>* info, 
    CPUAlgorithm<Bitmapset64, hashtable_memo_t<Bitmapset64>> *algorithm);