/*------------------------------------------------------------------------
 *
 * gpuqo_idp.cu
 *      iterative dynamic programming implementation
 *
 * src/backend/optimizer/gpuqo/gpuqo_idp.cu
 *
 *-------------------------------------------------------------------------
 */
// comment to show up as edited file
#include "gpuqo.cuh"
#include "gpuqo_query_tree.cuh"

int gpuqo_idp_n_iters;
int gpuqo_idp_type;

static int level_of_rec = 0;

template<typename BitmapsetOuter, typename BitmapsetInner>
QueryTree<BitmapsetOuter> *gpuqo_run_idp1_next(int gpuqo_algo, 
						GpuqoPlannerInfo<BitmapsetOuter>* info,
						list<remapper_transf_el_t<BitmapsetOuter> > &remap_list) 
{
	Remapper<BitmapsetOuter, BitmapsetInner> remapper(remap_list);

	GpuqoPlannerInfo<BitmapsetInner> *new_info =remapper.remapPlannerInfo(info);

	QueryTree<BitmapsetInner> *new_qt = gpuqo_run_idp1(gpuqo_algo,new_info);

	QueryTree<BitmapsetOuter> *new_qt_remap = remapper.remapQueryTree(new_qt);

	freeGpuqoPlannerInfo(new_info);
	freeQueryTree(new_qt);

	return new_qt_remap;
}

template<typename BitmapsetN>
QueryTree<BitmapsetN> *gpuqo_run_idp1(int gpuqo_algo, 
									GpuqoPlannerInfo<BitmapsetN>* info)
{
	info->n_iters = min(info->n_rels, gpuqo_idp_n_iters);

	LOG_PROFILE("IDP1 iteration with %d iterations: %d sets remaining (%d bits)\n", info->n_iters, info->n_rels, BitmapsetN::SIZE);

	QueryTree<BitmapsetN> *qt = gpuqo_run_switch(gpuqo_algo, info);

	if (info->n_iters == info->n_rels){
		return qt;
	}

	list<remapper_transf_el_t<BitmapsetN> > remap_list;

	remapper_transf_el_t<BitmapsetN> list_el;
	list_el.from_relid = qt->id;
	list_el.to_idx = 0;
	list_el.qt = qt;
	remap_list.push_back(list_el);
	
	int j = 1;
	for (int i=0; i<info->n_rels; i++){
		if (!info->base_rels[i].id.isSubset(qt->id)){
			list_el.from_relid = info->base_rels[i].id;
			list_el.to_idx = j++;
			list_el.qt = NULL;
			remap_list.push_back(list_el);
		}
	}

	if (BitmapsetN::SIZE == 32 || remap_list.size() < 32) {
		return gpuqo_run_idp1_next<BitmapsetN, Bitmapset32>(
										gpuqo_algo, info, remap_list);
	} else if (BitmapsetN::SIZE == 64 || remap_list.size() < 64) {
		return gpuqo_run_idp1_next<BitmapsetN, Bitmapset64>(
										gpuqo_algo, info, remap_list);
	} else {
		return gpuqo_run_idp1_next<BitmapsetN, BitmapsetDynamic>(
										gpuqo_algo, info, remap_list);
	}
}

template<>
QueryTree<BitmapsetDynamic> *gpuqo_run_idp1(int gpuqo_algo, 
									GpuqoPlannerInfo<BitmapsetDynamic>* info)
{
	printf("CANNOT RUN IDP1 with Dynamic Bitmapset!\n");
	return NULL;
}

template QueryTree<Bitmapset32> *gpuqo_run_idp1<Bitmapset32>(int,  GpuqoPlannerInfo<Bitmapset32>*);
template QueryTree<Bitmapset64> *gpuqo_run_idp1<Bitmapset64>(int,  GpuqoPlannerInfo<Bitmapset64>*);
template QueryTree<BitmapsetDynamic> *gpuqo_run_idp1<BitmapsetDynamic>(int,  GpuqoPlannerInfo<BitmapsetDynamic>*);


template<typename BitmapsetN>
QueryTree<BitmapsetN> *find_most_expensive_subtree(QueryTree<BitmapsetN> *qt, int max_size)
{
	Assert(qt != NULL && !qt->id.empty());
	Assert(max_size >= 1);

	if (qt->id.size() <= max_size) {
		return qt;
	} else {
		QueryTree<BitmapsetN> *lqt = find_most_expensive_subtree(qt->left, max_size);
		QueryTree<BitmapsetN> *rqt = find_most_expensive_subtree(qt->right, max_size);
		
		if (lqt->id.size() == 1)
			return rqt;
		else if (rqt->id.size() == 1)
			return lqt;
		else if (lqt->cost.total > rqt->cost.total)
			return lqt;
		else if (lqt->cost.total < rqt->cost.total)
			return rqt;
		else if (lqt->id.size() < rqt->id.size())
			return lqt;
		else
			return rqt;
	}
}

template<typename BitmapsetOuter, typename BitmapsetInner>
QueryTree<BitmapsetOuter> *gpuqo_run_idp2_dp(int gpuqo_algo, 
						GpuqoPlannerInfo<BitmapsetOuter>* info,
						list<remapper_transf_el_t<BitmapsetOuter> > &remap_list) 
{
	Remapper<BitmapsetOuter, BitmapsetInner> remapper(remap_list);

	GpuqoPlannerInfo<BitmapsetInner> *new_info =remapper.remapPlannerInfo(info);
	new_info->n_iters = new_info->n_rels;

	LOG_PROFILE("IDP2 iteration (dp) with %d rels (%d bits)\n", new_info->n_rels, BitmapsetInner::SIZE);
	QueryTree<BitmapsetInner> *new_qt = gpuqo_run_switch(gpuqo_algo,new_info);

	QueryTree<BitmapsetOuter> *new_qt_remap = remapper.remapQueryTree(new_qt);

	freeGpuqoPlannerInfo(new_info);
	freeQueryTree(new_qt);

	return new_qt_remap;
}

template<typename BitmapsetOuter, typename BitmapsetInner>
QueryTree<BitmapsetOuter> *gpuqo_run_idp2_rec(int gpuqo_algo, 
					QueryTree<BitmapsetOuter> *goo_qt,
					GpuqoPlannerInfo<BitmapsetOuter>* info,
					list<remapper_transf_el_t<BitmapsetOuter> > &remap_list,
					int n_iters) 
{
	
	level_of_rec++;
	std::cout << "\n\t LEVEL OF REC: " << level_of_rec << std::endl;
	

	Remapper<BitmapsetOuter, BitmapsetInner> remapper(remap_list);

	GpuqoPlannerInfo<BitmapsetInner> *new_info =remapper.remapPlannerInfo(info);
	QueryTree<BitmapsetInner> *new_goo_qt =remapper.remapQueryTreeFwd(goo_qt);


	LOG_DEBUG("--- optimizing query tree ---\n");
	printQueryTree(new_goo_qt);


	// TODO: Get postgres cost of the full Join Tree as recursion starts
	std::cout << "Full Join Tree Cost: " << new_goo_qt->cost.total << std::endl;
		

	new_info->n_iters = min(new_info->n_rels, n_iters);

	QueryTree<BitmapsetInner>* maximal_QT = find_most_expensive_subtree(new_goo_qt, new_info->n_iters);
	BitmapsetInner reopTables = maximal_QT->id;
	// TODO: Get postgrecost of most_expensive_subtree before optimization
	std::cout << "Maximal NOT OPTIMIZED Subtree Cost: " << maximal_QT->cost.total << std::endl;


	LOG_DEBUG("Reoptimizing subtree %u\n", reopTables.toUint());



	

	list<remapper_transf_el_t<BitmapsetInner> > reopt_remap_list;
	int i = 0;
	while (!reopTables.empty()) {
		remapper_transf_el_t<BitmapsetInner> list_el;
		list_el.from_relid = reopTables.lowest();
		list_el.to_idx = i++;
		list_el.qt = NULL;
		reopt_remap_list.push_back(list_el);

		reopTables -= list_el.from_relid;
	}

	QueryTree<BitmapsetInner> *reopt_qt;

	if (BitmapsetInner::SIZE == 32 || reopt_remap_list.size() < 32) {
		reopt_qt = gpuqo_run_idp2_dp<BitmapsetInner, Bitmapset32>(
								gpuqo_algo, new_info, reopt_remap_list);
	} else if (BitmapsetInner::SIZE == 64 || reopt_remap_list.size() < 64) {
		reopt_qt = gpuqo_run_idp2_dp<BitmapsetInner, Bitmapset64>(
								gpuqo_algo, new_info, reopt_remap_list);
	} else {
		reopt_qt = gpuqo_run_idp2_dp<BitmapsetInner, BitmapsetDynamic>(
								gpuqo_algo, new_info, reopt_remap_list);
	}


	LOG_DEBUG("--- reopt query tree ---\n");
	printQueryTree(reopt_qt);

	// TODO: Get it after optimization
	std::cout << "Maximal OPTIMIZED Subtree Cost: " << reopt_qt->cost.total << std::endl;


	QueryTree<BitmapsetInner> *res_qt;
	if (new_info->n_iters == new_info->n_rels){
		res_qt = reopt_qt;
	} else {
		list<remapper_transf_el_t<BitmapsetInner> > next_remap_list;

		remapper_transf_el_t<BitmapsetInner> list_el;
		list_el.from_relid = reopt_qt->id;
		list_el.to_idx = 0;
		list_el.qt = reopt_qt;
		next_remap_list.push_back(list_el);
		
		int j = 1;
		for (int i=0; i<new_info->n_rels; i++){
			if (!new_info->base_rels[i].id.isSubset(reopt_qt->id)){
				list_el.from_relid = new_info->base_rels[i].id;
				list_el.to_idx = j++;
				list_el.qt = NULL;
				next_remap_list.push_back(list_el);
			}
		}

		if (BitmapsetInner::SIZE == 32 || next_remap_list.size() < 32) {
			res_qt = gpuqo_run_idp2_rec<BitmapsetInner, Bitmapset32>(
				gpuqo_algo, new_goo_qt, new_info, next_remap_list, n_iters);
		} else if (BitmapsetInner::SIZE == 64 || next_remap_list.size() < 64) {
			res_qt = gpuqo_run_idp2_rec<BitmapsetInner, Bitmapset64>(
				gpuqo_algo, new_goo_qt, new_info, next_remap_list, n_iters);
		} else {
			res_qt = gpuqo_run_idp2_rec<BitmapsetInner, BitmapsetDynamic>(
				gpuqo_algo, new_goo_qt, new_info, next_remap_list, n_iters);
		}
	}

	QueryTree<BitmapsetOuter> *out_qt = remapper.remapQueryTree(res_qt);

	freeGpuqoPlannerInfo(new_info);
	freeQueryTree(new_goo_qt);
	freeQueryTree(res_qt);

	return out_qt;
}

template<typename BitmapsetN>
QueryTree<BitmapsetN> *gpuqo_run_idp2(int gpuqo_algo, 
									GpuqoPlannerInfo<BitmapsetN>* info,
									int n_iters)
{
	printf("\n\tSTART\n\n");
	QueryTree<BitmapsetN> *goo_qt = gpuqo_cpu_goo(info);
	list<remapper_transf_el_t<BitmapsetN> > remap_list;
	for (int i=0; i<info->n_rels; i++){
		remapper_transf_el_t<BitmapsetN> list_el;
		list_el.from_relid = info->base_rels[i].id;
		list_el.to_idx = i;
		list_el.qt = NULL;
		remap_list.push_back(list_el);
	}


	LOG_DEBUG("--- GOO query tree ---\n");
	printQueryTree(goo_qt);

	// TODO: Get INITIAL GOO QT cost
	std::cout << "GOO Initial Join Tree Cost: " << goo_qt->cost.total << std::endl;
		

	QueryTree<BitmapsetN> *out_qt = gpuqo_run_idp2_rec<BitmapsetN,BitmapsetN>(
						gpuqo_algo, goo_qt, info, remap_list, 
						n_iters > 0 ? n_iters : gpuqo_idp_n_iters);

	LOG_DEBUG("--- final query tree ---\n");
	printQueryTree(out_qt);

	freeQueryTree(goo_qt);
	printf("\tOUT OF RECURSION\n");
	// TODO: Get FINAL QT Cost
	std::cout << "FINAL IDP2 Join Tree Cost: " << out_qt->cost.total << std::endl;
	printf("\n\tEND\n\n");
	level_of_rec = 0;
	return out_qt;
}

template QueryTree<Bitmapset32> *gpuqo_run_idp2<Bitmapset32>(int,  GpuqoPlannerInfo<Bitmapset32>*,int);
template QueryTree<Bitmapset64> *gpuqo_run_idp2<Bitmapset64>(int,  GpuqoPlannerInfo<Bitmapset64>*,int);
template QueryTree<BitmapsetDynamic> *gpuqo_run_idp2<BitmapsetDynamic>(int,  GpuqoPlannerInfo<BitmapsetDynamic>*,int);