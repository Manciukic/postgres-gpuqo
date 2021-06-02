/*-------------------------------------------------------------------------
 *
 * gpuqo_planner_info.cu
 *	  structure for conversion from C to C++ optimized structure.
 *
 * src/include/optimizer/gpuqo_planner_info.cu
 *
 *-------------------------------------------------------------------------
 */

#include <iostream>

#include <optimizer/gpuqo_common.h>
#include "gpuqo_planner_info.cuh"
#include "gpuqo_cost.cuh"

extern "C" void *palloc0(size_t size);
extern "C" void *palloc(size_t size);

static size_t bitmapset_size(int nwords){
	return (offsetof(gpuqo_c::Bitmapset, words) + (nwords) * sizeof(gpuqo_c::bitmapword));
}

template<typename BitmapsetN>
BitmapsetN convertBitmapset(gpuqo_c::Bitmapset* set);

template<>
Bitmapset32 convertBitmapset<Bitmapset32>(gpuqo_c::Bitmapset* set){
	if (set == NULL)
		return Bitmapset32(0);


    if (set->nwords > 1){
        printf("WARNING: only relids of 32 bits are supported!\n");
    }
    if (set->words[0] & 0xFFFFFFFF00000000ULL){
        printf("WARNING: only relids of 32 bits are supported!\n");
    }
    return Bitmapset32(set->words[0] & 0xFFFFFFFFULL);
}
template<>
Bitmapset64 convertBitmapset<Bitmapset64>(gpuqo_c::Bitmapset* set){
	if (set == NULL)
		return Bitmapset64(0);

    if (set->nwords > 1){
        printf("WARNING: only relids of 64 bits are supported!\n");
    }
	
    return Bitmapset64(set->words[0]);
}

template<typename BitmapsetN>
gpuqo_c::Bitmapset* convertBitmapset(BitmapsetN set){
	gpuqo_c::Bitmapset *result;

	int nwords = (sizeof(set)*8 + BITS_PER_BITMAPWORD - 1) / BITS_PER_BITMAPWORD;

	result = (gpuqo_c::Bitmapset *) palloc0(bitmapset_size(nwords));
	result->nwords = nwords;

	while (!set.empty()){
		int x = set.lowestPos(); 
		int wordnum = x / BITS_PER_BITMAPWORD;
		int bitnum = x % BITS_PER_BITMAPWORD;

		result->words[wordnum] |= ((gpuqo_c::bitmapword) 1 << bitnum);
		set.unset(x);
	}

	return result;
}


extern "C" double	seq_page_cost;
extern "C" double	random_page_cost;
extern "C" double	cpu_tuple_cost;
extern "C" double	cpu_index_tuple_cost;
extern "C" double	cpu_operator_cost;
extern "C" double	parallel_tuple_cost;
extern "C" double	parallel_setup_cost;
extern "C" int		effective_cache_size;
extern "C" double	disable_cost;
extern "C" int		max_parallel_workers_per_gather;
extern "C" bool		enable_seqscan;
extern "C" bool		enable_indexscan;
extern "C" bool		enable_indexonlyscan;
extern "C" bool		enable_bitmapscan;
extern "C" bool		enable_tidscan;
extern "C" bool		enable_sort;
extern "C" bool		enable_hashagg;
extern "C" bool		enable_nestloop;
extern "C" bool		enable_material;
extern "C" bool		enable_mergejoin;
extern "C" bool		enable_hashjoin;
extern "C" bool		enable_gathermerge;
extern "C" bool		enable_partitionwise_join;
extern "C" bool		enable_partitionwise_aggregate;
extern "C" bool		enable_parallel_append;
extern "C" bool		enable_parallel_hash;
extern "C" bool		enable_partition_pruning;
extern "C" int		work_mem;

template<typename BitmapsetN>
static void setParams(GpuqoPlannerInfo<BitmapsetN>* info) {
		info->params.effective_cache_size = effective_cache_size;
		info->params.random_page_cost = random_page_cost;
		info->params.cpu_tuple_cost = cpu_tuple_cost;
		info->params.cpu_index_tuple_cost = cpu_index_tuple_cost;
		info->params.cpu_operator_cost = cpu_operator_cost;
		info->params.disable_cost = disable_cost;
		info->params.enable_seqscan = enable_seqscan;
		info->params.enable_indexscan = enable_indexscan;
		info->params.enable_tidscan = enable_tidscan;
		info->params.enable_sort = enable_sort;
		info->params.enable_hashagg = enable_hashagg;
		info->params.enable_nestloop = enable_nestloop;
		info->params.enable_mergejoin = enable_mergejoin;
		info->params.enable_hashjoin = enable_hashjoin;
		info->params.work_mem = work_mem;
}

template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN>* convertGpuqoPlannerInfo(gpuqo_c::GpuqoPlannerInfoC *info_c){
	size_t size = plannerInfoSize<BitmapsetN>(info_c->n_eq_classes, 
							info_c->n_eq_class_sels, info_c->n_eq_class_fks,
							info_c->n_eq_class_stats);

	char* p = new char[size];

	GpuqoPlannerInfo<BitmapsetN> *info = (GpuqoPlannerInfo<BitmapsetN>*) p;
	p += plannerInfoBaseSize<BitmapsetN>();

	info->size = size;
	info->n_rels = info_c->n_rels;
	info->n_iters = info_c->n_rels; // will be overwritten by IDP

	setParams(info);

	for (int i=0; i < info->n_rels; i++){
		info->edge_table[i] = convertBitmapset<BitmapsetN>(info_c->edge_table[i]);
		info->indexed_edge_table[i] = convertBitmapset<BitmapsetN>(info_c->indexed_edge_table[i]);
	}

	for (int i=0; i < info->n_rels; i++){
		info->base_rels[i].id = convertBitmapset<BitmapsetN>(info_c->base_rels[i].id);
		info->base_rels[i].rows = info_c->base_rels[i].rows;
		info->base_rels[i].tuples = info_c->base_rels[i].tuples;
		info->base_rels[i].width = info_c->base_rels[i].width;
		info->base_rels[i].pages = info_c->base_rels[i].pages;
		info->base_rels[i].cost.startup = info_c->base_rels[i].cost.startup;
		info->base_rels[i].cost.total = info_c->base_rels[i].cost.total;
		info->base_rels[i].composite = false;
	}

	info->eq_classes.n = info_c->n_eq_classes;
	info->eq_classes.n_sels = info_c->n_eq_class_sels;
	info->eq_classes.n_fks = info_c->n_eq_class_fks;
	info->eq_classes.n_stats = info_c->n_eq_class_stats;

	BitmapsetN* eq_classes = (BitmapsetN*) p;
	p += plannerInfoEqClassesSize<BitmapsetN>(info->eq_classes.n);
	float* eq_class_sels = (float*) p;
	p += plannerInfoEqClassSelsSize<BitmapsetN>(info->eq_classes.n_sels);
	BitmapsetN* eq_class_fk = (BitmapsetN*) p;
	p += plannerInfoEqClassFksSize<BitmapsetN>(info->eq_classes.n_fks);
	VarStat* eq_class_stats = (VarStat*) p;
	p += plannerInfoEqClassStatsSize<BitmapsetN>(info->eq_classes.n_stats);

	gpuqo_c::EqClassInfo *ec = info_c->eq_classes;
	int i = 0;
	int offset_sels = 0;
	int offset_fks = 0;
	while (ec != NULL){
		eq_classes[i] = convertBitmapset<BitmapsetN>(ec->relids);

		int s = eq_classes[i].size();
		int n = eqClassNSels(s);
		for (int j = 0; j < n; j++)
			eq_class_sels[offset_sels+j] = ec->sels[j];

		for (int j = 0; j < s; j++){
			eq_class_fk[offset_fks+j] = convertBitmapset<BitmapsetN>(ec->fk[j]);
			eq_class_stats[offset_fks+j].mcvfreq = ec->stats[j].mcvfreq;
			eq_class_stats[offset_fks+j].stadistinct = ec->stats[j].stadistinct;
			eq_class_stats[offset_fks+j].stanullfrac = ec->stats[j].stanullfrac;
		}
		
		offset_sels += n;
		offset_fks += s;
		i++;
		ec = ec->next;
	}
	info->eq_classes.relids = eq_classes;
	info->eq_classes.sels = eq_class_sels;
	info->eq_classes.fks = eq_class_fk;
	info->eq_classes.stats = eq_class_stats;

	return info;
}

template GpuqoPlannerInfo<Bitmapset32>* convertGpuqoPlannerInfo<Bitmapset32>(gpuqo_c::GpuqoPlannerInfoC *info_c);
template GpuqoPlannerInfo<Bitmapset64>* convertGpuqoPlannerInfo<Bitmapset64>(gpuqo_c::GpuqoPlannerInfoC *info_c);
 
template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN>* copyToDeviceGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN> *info){
	GpuqoPlannerInfo<BitmapsetN> tmp_info = *info;

	char* p;
	
	cudaMalloc(&p, info->size);
	
	GpuqoPlannerInfo<BitmapsetN> *info_gpu = (GpuqoPlannerInfo<BitmapsetN>*) p;
	p += plannerInfoBaseSize<BitmapsetN>();
	
	tmp_info.eq_classes.relids = (BitmapsetN*) p;
	p += plannerInfoEqClassesSize<BitmapsetN>(info->eq_classes.n);
	cudaMemcpy((void*)tmp_info.eq_classes.relids, info->eq_classes.relids, 
		sizeof(BitmapsetN) * info->eq_classes.n, cudaMemcpyHostToDevice);
	
	tmp_info.eq_classes.sels = (float*) p;
	p += plannerInfoEqClassSelsSize<BitmapsetN>(info->eq_classes.n_sels);
	cudaMemcpy((void*)tmp_info.eq_classes.sels, info->eq_classes.sels, 
		sizeof(float) * info->eq_classes.n_sels, cudaMemcpyHostToDevice);
	
	tmp_info.eq_classes.fks = (BitmapsetN*) p;
	p += plannerInfoEqClassFksSize<BitmapsetN>(info->eq_classes.n_fks);
	cudaMemcpy((void*)tmp_info.eq_classes.fks, info->eq_classes.fks, 
		sizeof(BitmapsetN) * info->eq_classes.n_fks, cudaMemcpyHostToDevice);
	
	tmp_info.eq_classes.stats = (VarStat*) p;
	p += plannerInfoEqClassStatsSize<BitmapsetN>(info->eq_classes.n_stats);
	cudaMemcpy((void*)tmp_info.eq_classes.stats, info->eq_classes.stats, 
		sizeof(VarStat) * info->eq_classes.n_stats, cudaMemcpyHostToDevice);
	
	cudaMemcpy(info_gpu, &tmp_info, sizeof(GpuqoPlannerInfo<BitmapsetN>), cudaMemcpyHostToDevice);

	return info_gpu;
}

template GpuqoPlannerInfo<Bitmapset32>* copyToDeviceGpuqoPlannerInfo<Bitmapset32>(GpuqoPlannerInfo<Bitmapset32> *info);
template GpuqoPlannerInfo<Bitmapset64>* copyToDeviceGpuqoPlannerInfo<Bitmapset64>(GpuqoPlannerInfo<Bitmapset64> *info);

template<typename BitmapsetN>
gpuqo_c::QueryTreeC* convertQueryTree(QueryTree<BitmapsetN>* qt){
	if (qt == NULL)
		return NULL;
	
	gpuqo_c::QueryTreeC *result = (gpuqo_c::QueryTreeC *) palloc(sizeof(gpuqo_c::QueryTreeC));
	result->id = convertBitmapset<BitmapsetN>(qt->id);
	result->left = convertQueryTree(qt->left);
	result->right = convertQueryTree(qt->right);
	result->width = qt->width;
	result->cost.total = qt->cost.total;
	result->cost.startup = qt->cost.startup;
	result->rows = qt->rows;

	free(qt);

	return result;
}

template gpuqo_c::QueryTreeC* convertQueryTree<Bitmapset32>(QueryTree<Bitmapset32>* qt);
template gpuqo_c::QueryTreeC* convertQueryTree<Bitmapset64>(QueryTree<Bitmapset64>* qt);
  