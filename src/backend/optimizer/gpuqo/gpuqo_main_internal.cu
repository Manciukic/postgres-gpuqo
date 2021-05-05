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

template<typename BitmapsetN>
QueryTree<BitmapsetN> *gpuqo_run_switch(int gpuqo_algorithm, 
									GpuqoPlannerInfo<BitmapsetN>* info)
{
	switch (gpuqo_algorithm)
	{
	case GPUQO_DPSIZE:
		return gpuqo_dpsize(info);
		break;
	case GPUQO_DPSUB:
		return gpuqo_dpsub(info);
		break;
	case GPUQO_CPU_DPSIZE:
		return gpuqo_cpu_dpsize(info);
		break;
	case GPUQO_CPU_DPSUB:
		return gpuqo_cpu_dpsub(info);
		break;
	case GPUQO_CPU_DPSUB_PARALLEL:
		return gpuqo_cpu_dpsub_parallel(info);
		break;
	case GPUQO_CPU_DPSUB_BICC:
		return gpuqo_cpu_dpsub_bicc(info);
		break;
	case GPUQO_CPU_DPSUB_BICC_PARALLEL:
		return gpuqo_cpu_dpsub_bicc_parallel(info);
		break;
	case GPUQO_CPU_DPCCP:
		return gpuqo_cpu_dpccp(info);
		break;
	case GPUQO_DPE_DPSIZE:
		return gpuqo_dpe_dpsize(info);
		break;
	case GPUQO_DPE_DPSUB:
		return gpuqo_dpe_dpsub(info);
		break;
	case GPUQO_DPE_DPCCP:
		return gpuqo_dpe_dpccp(info);
		break;
	 default: 
		// impossible branch but without it the compiler complains
		return NULL;
		break;
	}
}

template<typename BitmapsetN>
static gpuqo_c::QueryTree *__gpuqo_run(int gpuqo_algorithm, gpuqo_c::GpuqoPlannerInfo* info_c)
{
	GpuqoPlannerInfo<BitmapsetN> *info = convertGpuqoPlannerInfo<BitmapsetN>(info_c);

	if (gpuqo_spanning_tree_enable){
		minimumSpanningTree(info);
		buildSubTrees(info->subtrees, info);
	}

	Remapper<BitmapsetN> remapper = makeBFSIndexRemapper(info);
	GpuqoPlannerInfo<BitmapsetN> *remap_info = remapper.remapPlannerInfo(info);

	QueryTree<BitmapsetN> *query_tree = gpuqo_run_switch(gpuqo_algorithm, 
														remap_info);

	remapper.remapQueryTree(query_tree);

	delete remap_info;
	delete info;

	return convertQueryTree(query_tree);
}

extern "C" gpuqo_c::QueryTree *gpuqo_run(int gpuqo_algorithm, gpuqo_c::GpuqoPlannerInfo* info_c){
	if (info_c->n_rels < 32){
		return __gpuqo_run<Bitmapset32>(gpuqo_algorithm, info_c);
	} else if (info_c->n_rels < 64){
		return __gpuqo_run<Bitmapset64>(gpuqo_algorithm, info_c);
	} else {
		printf("ERROR: too many relations\n");
		return NULL;	
	}
}
