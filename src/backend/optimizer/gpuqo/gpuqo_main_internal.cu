/*------------------------------------------------------------------------
 *
 * gpuqo_main_internal.cu
 *      implementation of run function
 *
 * src/backend/optimizer/gpuqo/gpuqo_main_internal.cu
 *
 *-------------------------------------------------------------------------
 */

#include "gpuqo.cuh"
#include "gpuqo_query_tree.cuh"
#include "gpuqo_timing.cuh"

#ifdef GPUQO_PRINT_N_JOINS
__device__ unsigned long long join_counter;
#endif

template<typename BitmapsetN>
QueryTree<BitmapsetN> *gpuqo_run_switch(int gpuqo_algorithm, 
										GpuqoPlannerInfo<BitmapsetN>* info)
{
	switch (gpuqo_algorithm)
	{
	case GPUQO_DPSIZE:
		return gpuqo_dpsize(info);
	case GPUQO_DPSUB:
		return gpuqo_dpsub(info);
	case GPUQO_CPU_DPSIZE:
		return gpuqo_cpu_dpsize(info);
	case GPUQO_CPU_DPSUB:
		return gpuqo_cpu_dpsub(info);
	case GPUQO_CPU_DPSUB_PARALLEL:
		return gpuqo_cpu_dpsub_parallel(info);
	case GPUQO_CPU_DPSUB_BICC:
		return gpuqo_cpu_dpsub_bicc(info);
	case GPUQO_CPU_DPSUB_BICC_PARALLEL:
		return gpuqo_cpu_dpsub_bicc_parallel(info);
	case GPUQO_CPU_DPCCP:
		return gpuqo_cpu_dpccp(info);
	case GPUQO_DPE_DPSIZE:
		return gpuqo_dpe_dpsize(info);
	case GPUQO_DPE_DPSUB:
		return gpuqo_dpe_dpsub(info);
	case GPUQO_DPE_DPCCP:
		return gpuqo_dpe_dpccp(info);
	case GPUQO_CPU_GOO:
		return gpuqo_cpu_goo(info);
	case GPUQO_CPU_IKKBZ:
		return gpuqo_cpu_ikkbz(info);
	case GPUQO_CPU_LINEARIZED_DP:
		return gpuqo_cpu_linearized_dp(info);
	case GPUQO_CPU_DPLIN:
		return gpuqo_cpu_dplin(info);
	 default: 
		// impossible branch but without it the compiler complains
		return NULL;
	}
}

template<>
QueryTree<BitmapsetDynamic> *gpuqo_run_switch(int gpuqo_algorithm, 
										GpuqoPlannerInfo<BitmapsetDynamic>* info)
{
	switch (gpuqo_algorithm)
	{
	case GPUQO_CPU_GOO:
		return gpuqo_cpu_goo(info);
	case GPUQO_CPU_IKKBZ:
		return gpuqo_cpu_ikkbz(info);
	case GPUQO_CPU_LINEARIZED_DP:
		return gpuqo_cpu_linearized_dp(info);
	case GPUQO_CPU_DPLIN:
		return gpuqo_cpu_dplin(info);
	 default: 
		printf("ERROR: This algorithm is not supported with > 64 relations\n");
		return NULL;
	}
}

template<typename BitmapsetN>
static QueryTreeC *__gpuqo_run(int gpuqo_algorithm, GpuqoPlannerInfoC* info_c)
{

    DECLARE_TIMING(gpuqo_run);
    DECLARE_TIMING(gpuqo_run_setup);
    DECLARE_TIMING(gpuqo_run_execute);
    DECLARE_TIMING(gpuqo_run_fini);

    START_TIMING(gpuqo_run);
    START_TIMING(gpuqo_run_setup);
	GpuqoPlannerInfo<BitmapsetN> *info = convertGpuqoPlannerInfo<BitmapsetN>(info_c);

	if (gpuqo_spanning_tree_enable){
		GpuqoPlannerInfo<BitmapsetN> *new_info = minimumSpanningTree(info);
		freeGpuqoPlannerInfo(info);
		info = new_info;

		buildSubTrees(info->subtrees, info);
	}

	Remapper<BitmapsetN,BitmapsetN> remapper = makeBFSIndexRemapper(info);
	GpuqoPlannerInfo<BitmapsetN> *remap_info = remapper.remapPlannerInfo(info);

	STOP_TIMING(gpuqo_run_setup);
	START_TIMING(gpuqo_run_execute);

	QueryTree<BitmapsetN> *query_tree;
	if (gpuqo_idp_n_iters <= 1 || gpuqo_idp_n_iters >= info->n_rels)
		query_tree = gpuqo_run_switch(gpuqo_algorithm, remap_info);
	else{
		switch(gpuqo_idp_type) {
			case GPUQO_IDP1:
				query_tree = gpuqo_run_idp1(gpuqo_algorithm, remap_info);
				break;
			case GPUQO_IDP2:
				query_tree = gpuqo_run_idp2(gpuqo_algorithm, remap_info);
				break;
			case GPUQO_UNION:
				printf("\ncase GPUQO_UNION\n");
				query_tree = gpuqo_run_dpdp_union(gpuqo_algorithm, remap_info);
				break;
			default:
				printf("Unkonwn IDP type\n");
		}
	}

	STOP_TIMING(gpuqo_run_execute);
	START_TIMING(gpuqo_run_fini);

	QueryTree<BitmapsetN> *new_qt = remapper.remapQueryTree(query_tree);
	freeQueryTree(query_tree);

	freeGpuqoPlannerInfo(remap_info);
	freeGpuqoPlannerInfo(info);

	auto res = convertQueryTree(new_qt);

	STOP_TIMING(gpuqo_run_fini);
    STOP_TIMING(gpuqo_run);
    PRINT_TIMING(gpuqo_run_setup);
    PRINT_TIMING(gpuqo_run_execute);
    PRINT_TIMING(gpuqo_run_fini);
    PRINT_TIMING(gpuqo_run);

	return res;
}

template<typename BitmapsetN>
static QueryTreeC *__gpuqo_run_idp2(int gpuqo_algorithm, GpuqoPlannerInfoC* info_c)
{
	GpuqoPlannerInfo<BitmapsetN> *info = convertGpuqoPlannerInfo<BitmapsetN>(info_c);

	if (gpuqo_spanning_tree_enable){
		GpuqoPlannerInfo<BitmapsetN> *new_info = minimumSpanningTree(info);
		freeGpuqoPlannerInfo(info);
		info = new_info;

		buildSubTrees(info->subtrees, info);
	}

	Remapper<BitmapsetN,BitmapsetN> remapper = makeBFSIndexRemapper(info);
	GpuqoPlannerInfo<BitmapsetN> *remap_info = remapper.remapPlannerInfo(info);

	QueryTree<BitmapsetN> *query_tree = gpuqo_run_idp2(gpuqo_algorithm, remap_info);


	QueryTree<BitmapsetN> *new_qt = remapper.remapQueryTree(query_tree);
	freeQueryTree(query_tree);

	freeGpuqoPlannerInfo(remap_info);
	freeGpuqoPlannerInfo(info);

	return convertQueryTree(new_qt);
}

extern "C" QueryTreeC *gpuqo_run(int gpuqo_algorithm, GpuqoPlannerInfoC* info_c){
	if (info_c->n_rels < 32){
		return __gpuqo_run<Bitmapset32>(gpuqo_algorithm, info_c);
	} else if (info_c->n_rels < 64){
		return __gpuqo_run<Bitmapset64>(gpuqo_algorithm, info_c);
	} else {
		return __gpuqo_run<BitmapsetDynamic>(gpuqo_algorithm, info_c);
	}
}
