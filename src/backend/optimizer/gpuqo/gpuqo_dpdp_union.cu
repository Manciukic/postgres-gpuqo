/*------------------------------------------------------------------------
 *
 * gpuqo_dpdp_union.cu
 *      dp over dp and k-cut implementation
 *
 * src/backend/optimizer/gpuqo/gpuqo_dpdp_union.cu
 *
 *-------------------------------------------------------------------------
 */

#include "gpuqo.cuh" 
#include "gpuqo_query_tree.cuh"
#include "gpuqo_row_estimation.cuh" 
#include "gpuqo_debug.cuh"
#include "gpuqo_bitmapset.cuh"
#include "gpuqo_bitmapset_dynamic.cuh"
#include "gpuqo_planner_info.cuh" // for cost estimation and PathCost
#include "gpuqo_cost.cuh" //calc_join_cost

#include <iostream>
#include <vector>
#include <deque>
#include <string>
#include <algorithm> 
#include <queue> 
#include <unordered_map> 

static int level_of_dp = 0;

template<typename BitmapsetN>
struct GraphEdge;

/// ------------------------------- START OF DISJOINT SET CLASS


template<typename BitmapsetN>
class DisjointSet
{
    std::unordered_map<BitmapsetN, BitmapsetN> parent;
    std::unordered_map<BitmapsetN, int> size;
    std::unordered_map<BitmapsetN, BitmapsetN> csg;
	//TODO: Add total_cost 
    std::unordered_map<BitmapsetN, double> total_cost;

public:
    BitmapsetN getCsg(BitmapsetN node_id){
        return csg[Find(node_id)];
    }
    
	int getSize(BitmapsetN node_id){
        return size[Find(node_id)];
    }

	double getCost(BitmapsetN node_id){
		return total_cost[Find(node_id)];
	}

    void makeSet(GpuqoPlannerInfo<BitmapsetN>* info) 
    {
        for (int base_rel_idx=0; base_rel_idx<info->n_rels; base_rel_idx++){
            BitmapsetN node_id = info->base_rels[base_rel_idx].id;
            parent[node_id] = node_id;
            csg[node_id] = node_id;
            size[node_id] = 1;
			total_cost[node_id] = 0.0f; // cost of single node is nothing since no join
        }
    }
 
    BitmapsetN Find(BitmapsetN node_id)
    {
        if (parent[node_id] != node_id)
        {
            parent[node_id] = Find(parent[node_id]);
        }
 
        return parent[node_id];
    }
 
	void Union(GraphEdge<BitmapsetN>* edge)
    {

        BitmapsetN x = Find(edge->left);
        BitmapsetN y = Find(edge->right);
        
        if (x == y) { 
            return;
        }
		// x takes y
        if (size[x] > size[y]) {
            parent[y] = x;
            size[x] += size[y];
            csg[x] |= csg[y];    
			total_cost[x] += edge->cost.total;
        }
		// y takes x
        else if (size[x] < size[y]) {
            parent[x] = y;
            size[y] += size[x];
            csg[y] |= csg[x];
			total_cost[y] += edge->cost.total;
        }
		// y takes x
        else {
            parent[x] = y;
            size[y] *= 2; 
            csg[y] |= csg[x];
			total_cost[y] += edge->cost.total;
        }
    }
};

template<typename BitmapsetN>
void printSets(GpuqoPlannerInfo<BitmapsetN>* info, DisjointSet<BitmapsetN> &ds)
{
    for (int i=0;i<info->n_rels;i++) {
		BitmapsetN node_id = info->base_rels[i].id;
		printf("\n");
        std::cout << ds.Find(node_id) << ' ';
        // std::cout << 'size: ( ' << ds.getSize(node_id) << ' )' << '-';
        std::cout << 'csg: ( ' << ds.getCsg(node_id) << ' )' << '-';
    }
    std::cout << std::endl;
};

/// ------------------------------- END OF DISJOINT SET CLASS

template<typename BitmapsetN>
struct GraphEdge {
	BitmapsetN left; // base_rels[].id
	BitmapsetN right; // base_rels[].id
	int left_size; 
	int right_size;
	int total_size; 
	float rows;
	float selectivity;
	PathCost cost;
	int width;
	float weight; 
};

template<typename BitmapsetN>
struct CompareLeafEdges{
    bool operator()(const GraphEdge<BitmapsetN>* lhs, const GraphEdge<BitmapsetN>* rhs) {
		return lhs->weight > rhs->weight;
    }
};

template<typename BitmapsetN>
struct CompareEdges{
    bool operator()(const GraphEdge<BitmapsetN>* lhs, const GraphEdge<BitmapsetN>* rhs) {
		if (lhs->total_size == rhs->total_size) {
			return lhs->weight > rhs->weight;			
		}
		return lhs->total_size > rhs->total_size;
    }
};

template<typename BitmapsetN>
using LeafQ = std::priority_queue<GraphEdge<BitmapsetN>*, std::vector<GraphEdge<BitmapsetN>*>, CompareLeafEdges<BitmapsetN>>;
template<typename BitmapsetN>
using EdgeQ = std::priority_queue<GraphEdge<BitmapsetN>*, std::vector<GraphEdge<BitmapsetN>*>, CompareEdges<BitmapsetN>>;


template<typename BitmapsetN>
GraphEdge<BitmapsetN>* createGraphEdge(int left_rel_idx, int right_rel_idx , GpuqoPlannerInfo<BitmapsetN>* info){

	GraphEdge<BitmapsetN>* edge_el = new GraphEdge<BitmapsetN>;

	edge_el->left = info->base_rels[left_rel_idx].id;
	edge_el->right =  info->base_rels[right_rel_idx].id; 

	float left_rel_rows = info->base_rels[left_rel_idx].rows;
	float right_rel_rows = info->base_rels[right_rel_idx].rows;
	
	edge_el->selectivity = estimate_join_selectivity(edge_el->left, edge_el->right, info);
	edge_el->rows = edge_el->selectivity * left_rel_rows * right_rel_rows;

	edge_el->left_size = 1;
	edge_el->right_size = 1;
	edge_el->total_size = edge_el->left_size + edge_el->right_size;


	// 1) Creating Join Relation
	JoinRelation<BitmapsetN> left_rel;
    left_rel.left_rel_id = 0; 
    left_rel.right_rel_id = 0; 
	left_rel.cost = cost_baserel(info->base_rels[left_rel_idx]); 
    left_rel.width = info->base_rels[left_rel_idx].width; 
    left_rel.rows = info->base_rels[left_rel_idx].rows; 

	JoinRelation<BitmapsetN> right_rel;
    right_rel.left_rel_id = 0; 
    right_rel.right_rel_id = 0; 
	right_rel.cost = cost_baserel(info->base_rels[right_rel_idx]); 
    right_rel.width = info->base_rels[right_rel_idx].width; 
    right_rel.rows = info->base_rels[right_rel_idx].rows; 

	// 2) From make_join_relation: 
	// join_rel->rows = estimate_join_rows(edge_el->left, left_rel, edge_el->right, right_rel, info);
	// default is postgres cost I can switch by passing var in makefile
	edge_el->cost = calc_join_cost(edge_el->left, left_rel, edge_el->right, right_rel, edge_el->rows, info);
	edge_el->width = get_join_width(edge_el->left, left_rel, edge_el->right, right_rel, info);

	// std::cout << " COST = " <<  edge_el->cost.total << std::endl;
	// 3) Set edge weight any in (cost, selectivit , cardinality)
	// edge_el->weight = edge_el->cost.total;
	// edge_el->weight = edge_el->selectivity;
	edge_el->weight = edge_el->rows;

	return edge_el;
}


template<typename BitmapsetN>
double fillPriorityQueues(std::vector<GraphEdge<BitmapsetN>*> &edge_pointers_list, LeafQ<BitmapsetN> &LeafPriorityQueue, EdgeQ<BitmapsetN> &EdgePriorityQueue, GpuqoPlannerInfo<BitmapsetN>* info)
{
	std::queue<int> bfs_queue;

	double sum_of_all_edge_costs = 0;

    int bfs_idx = 0;
	bfs_queue.push(0);

    BitmapsetN seen = BitmapsetN::nth(1);
    BitmapsetN seen_2 = BitmapsetN::nth(1);
	while(!bfs_queue.empty() && bfs_idx < info->n_rels){
       
		int base_rel_idx  = bfs_queue.front();
		bfs_queue.pop();
		BitmapsetN edges = info->edge_table[base_rel_idx]; // get the edget of the first rel

		// std::cout << std::endl << "EDGES : " << edges << std::endl;
		bfs_idx++;
		while(!edges.empty()){
			int next = edges.lowestPos();  // get next rel
			Assert(next > 0);
			// even though it is casting to unsigned, it is not a problem because next is (int) not (bms)
			if(!seen_2.isSet(next)){ 
				bfs_queue.push(next - 1);

				GraphEdge<BitmapsetN> *edge_el = createGraphEdge(base_rel_idx, next-1 , info); // create edge between first and next
				// std::cout << "AFTER COST = " <<  edge_el->cost.total << std::endl;
				if (edges.size() == 1)  
				{
					LeafPriorityQueue.push(edge_el);
				}
				std::cout << "Pushing edge_el " << edge_el << " to EdgePriorityQueue" << std::endl;
				EdgePriorityQueue.push(edge_el); // push edge to priority queue
				edge_pointers_list.push_back(edge_el);

				sum_of_all_edge_costs += edge_el->cost.total;
			}
			edges.unset(next); // unset next rel from first's connections
		}
		seen_2 |= BitmapsetN::nth(base_rel_idx+1);
	}


	delete[] bfs_queue;
	return sum_of_all_edge_costs;
}

template<typename BitmapsetOuter, typename BitmapsetInner>
QueryTree<BitmapsetOuter> *gpuqo_run_dpdp_union_dp(int gpuqo_algo, 
						GpuqoPlannerInfo<BitmapsetOuter>* info,
						list<remapper_transf_el_t<BitmapsetOuter> > &remap_list) 
{

	Remapper<BitmapsetOuter, BitmapsetInner> remapper(remap_list);
	GpuqoPlannerInfo<BitmapsetInner> *new_info = remapper.remapPlannerInfo(info);
	new_info->n_iters = new_info->n_rels;

	LOG_PROFILE("Iteration (dp) with %d rels (%d bits)\n", new_info->n_rels, BitmapsetInner::SIZE);
	// printf("\nIteration (dp) with %d rels (%d bits)\n", new_info->n_rels, BitmapsetInner::SIZE);
	QueryTree<BitmapsetInner> *new_qt = gpuqo_run_switch(gpuqo_algo, new_info);
	QueryTree<BitmapsetOuter> *new_qt_remap = remapper.remapQueryTree(new_qt);

	freeGpuqoPlannerInfo(new_info);
	freeQueryTree(new_qt);
	
	return new_qt_remap;
}


template<typename BitmapsetOuter, typename BitmapsetInner>
QueryTree<BitmapsetOuter> *gpuqo_run_dpdp_union_rec(int gpuqo_algo, 
					GpuqoPlannerInfo<BitmapsetOuter>* info,
					list<remapper_transf_el_t<BitmapsetOuter> > &remap_list,
					int n_iters) 
{
	level_of_dp++;
	std::cout << "\n\t LEVEL OF DP: " << level_of_dp << std::endl;
	printf("\n f(x): gpuqo_run_dpdp_union_rec ----- FIRST CHECK ----- LEVEL %d \n", level_of_dp);
	Remapper<BitmapsetOuter, BitmapsetInner> remapper(remap_list);
	GpuqoPlannerInfo<BitmapsetInner> *new_info = remapper.remapPlannerInfo(info);
	
	new_info->n_iters = min(new_info->n_rels, n_iters);

	if (new_info->n_rels == new_info->n_iters){
		printf("\n f(x): gpuqo_run_dpdp_union_rec => -----INSIDE TERMINATION CHECK ----- LEVEL %d \n", level_of_dp);
		QueryTree<BitmapsetOuter> *out_qt = gpuqo_run_dpdp_union_dp<BitmapsetOuter, BitmapsetInner>(gpuqo_algo, info, remap_list);
		freeGpuqoPlannerInfo(new_info);
        return out_qt;
    }


	LeafQ<BitmapsetInner> LeafPriorityQueue;
	EdgeQ<BitmapsetInner> EdgePriorityQueue;
	
	// printf("After initialization of LeafPriorityQueue and EdgePriorityQueue\n");
	std::vector<GraphEdge<BitmapsetInner>*> edge_pointers_list;
	double sum_of_all_edge_costs = fillPriorityQueues(edge_pointers_list, LeafPriorityQueue, EdgePriorityQueue, new_info);

	// std::cout << "Sum of all Edge Costs: " << sum_of_all_edge_costs << std::endl;
	// std::cout << "LeafQ size = " << LeafPriorityQueue.size() << std::endl;
	// printf("After f(x) fillPriorityQueues\n");
	
	DisjointSet<BitmapsetInner> ds;
	ds.makeSet(new_info);
	int total_disjoint_sets = new_info->n_rels;
	// printf("After f(x) ds.makeSet()\n");
	int upper_threshold = 16;

	printf("Starting EdgePriorityQueue while loop\n");
	std::cout << "SIZE OF EdgePriorityQueue = " << EdgePriorityQueue.size() << std::endl;
	while(!EdgePriorityQueue.empty()){
		GraphEdge<BitmapsetInner>* edge = EdgePriorityQueue.top();
		EdgePriorityQueue.pop();


		if (ds.Find(edge->left) != ds.Find(edge->right) ){
			if (edge->total_size != (ds.getSize(edge->left) + ds.getSize(edge->right)) ){
				edge->left_size = ds.getSize(edge->left);
				edge->right_size = ds.getSize(edge->right);
				edge->total_size = edge->left_size + edge->right_size;
				EdgePriorityQueue.push(edge); 
			}
			else{
				if (edge->total_size < upper_threshold)
				{
					ds.Union(edge);
					total_disjoint_sets--;
				}
			}
		}
	}
	
	for (int i=0; i < edge_pointers_list.size(); i++){
		delete edge_pointers_list[i];
	}
	
	printf("\n\t\tPRINTING ALL DISJOINT SETS");
	printSets(new_info, ds);
	
	double total_unoptimized_union_cost = 0.0f;
	std::vector<BitmapsetInner> subgraphs;
	BitmapsetInner seen = BitmapsetInner(0);
	printf("\n f(x): gpuqo_run_dpdp_union_rec => getting csgs ----- CHECK 2 ----- \n");
	for(int i=0; i<new_info->n_rels; i++)
	{
		BitmapsetInner node_id = new_info->base_rels[i].id;
		BitmapsetInner csg = ds.getCsg(node_id);
		if (!csg.isSubset(seen)){
			total_unoptimized_union_cost += ds.getCost(node_id);
			std::cout << "Disjoint Set = " << csg << "\t Cost = " << ds.getCost(node_id) << std::endl;
			subgraphs.push_back(csg);
		}
		seen |= csg;
	}
	std::cout << "Assertion: subgraphs.size() = " <<  subgraphs.size() << "  total_disjoint_sets= " << total_disjoint_sets << std::endl;
	Assert(subgraphs.size() == total_disjoint_sets);
	
	
	std::cout << "Sum of NOT OPTIMIZED Disjoint Set Cost: " << total_unoptimized_union_cost << std::endl;
	std::cout << "Sum of CUT EDGES Cost: " << sum_of_all_edge_costs - total_unoptimized_union_cost << std::endl;
	// printf("\n");
	// double sum_subgraph_costs = 0;
	// for(int i=0; i < subgraphs.size(); i++){
		
	// }
	// std::cout << "Maximal NOT OPTIMIZED Subtree Cost: " << maximal_QT->cost.total << std::endl;


	printf("\n f(x): gpuqo_run_dpdp_union_rec => after subgraphs ----- CHECK 3 ----- \n");

	double total_optimized_cost = 0;
	list<remapper_transf_el_t<BitmapsetInner> > next_remap_list;
	for (int i=0; i < subgraphs.size(); i++){
		list<remapper_transf_el_t<BitmapsetInner> > reopt_remap_list;
		int j = 0;
		BitmapsetInner reopTables = subgraphs[i];
		std::cout << "For Disjoint Set = " << reopTables << " ";
		std::cout << "SIZE = " << reopTables.size() << " ";
		while (!reopTables.empty()) {
			remapper_transf_el_t<BitmapsetInner> list_el;
			list_el.from_relid = reopTables.lowest();
			list_el.to_idx = j++;
			list_el.qt = NULL;
			reopt_remap_list.push_back(list_el);
			reopTables -= list_el.from_relid;
		}
	
		QueryTree<BitmapsetInner> *reopt_qt;
		if (BitmapsetInner::SIZE == 32 || reopt_remap_list.size() < 32) {
			reopt_qt = gpuqo_run_dpdp_union_dp<BitmapsetInner, Bitmapset32>(
									gpuqo_algo, new_info, reopt_remap_list);
		} else if (BitmapsetInner::SIZE == 64 || reopt_remap_list.size() < 64) {
			reopt_qt = gpuqo_run_dpdp_union_dp<BitmapsetInner, Bitmapset64>(
									gpuqo_algo, new_info, reopt_remap_list);
		} else {
			reopt_qt = gpuqo_run_dpdp_union_dp<BitmapsetInner, BitmapsetDynamic>(
									gpuqo_algo, new_info, reopt_remap_list);
		}
		total_optimized_cost +=  reopt_qt->cost.total;
		std::cout << "\t Cost after Optimization = " << reopt_qt->cost.total << std::endl;
		remapper_transf_el_t<BitmapsetInner> list_el;
		list_el.from_relid = reopt_qt->id;
		list_el.to_idx = i;
		list_el.qt = reopt_qt;
		next_remap_list.push_back(list_el);
	}

	std::cout << "Sum of OPTIMIZED Disjoint Set Cost: " << total_optimized_cost << std::endl;
	std::cout << "Total REDUCTED Disjoint Set Cost: " << total_unoptimized_union_cost - total_optimized_cost << std::endl;



	printf("\n f(x): gpuqo_run_dpdp_union_rec => recursing ----- CHECK 4 ----- LEVEL %d \n", level_of_dp);
	QueryTree<BitmapsetInner> *res_qt;
	if (BitmapsetInner::SIZE == 32 || next_remap_list.size() < 32) {
		res_qt = gpuqo_run_dpdp_union_rec<BitmapsetInner, Bitmapset32>(
		gpuqo_algo, new_info, next_remap_list, n_iters);
	} else if (BitmapsetInner::SIZE == 64 || next_remap_list.size() < 64) {
		res_qt = gpuqo_run_dpdp_union_rec<BitmapsetInner, Bitmapset64>(
		gpuqo_algo, new_info, next_remap_list, n_iters);
	} else {
		res_qt = gpuqo_run_dpdp_union_rec<BitmapsetInner, BitmapsetDynamic>(
			gpuqo_algo, new_info, next_remap_list, n_iters);
	}
	printf("\n f(x): gpuqo_run_dpdp_union_rec => after recursion ----- CHECK 5 ----- LEVEL %d \n", level_of_dp);
	QueryTree<BitmapsetOuter> *out_qt = remapper.remapQueryTree(res_qt);
	freeGpuqoPlannerInfo(new_info);
	freeQueryTree(res_qt);
	printf("\n f(x): gpuqo_run_dpdp_union_rec => returning ----- FINAL CHECK ----- LEVEL %d \n", level_of_dp);
	return out_qt;
}


template<typename BitmapsetN>
QueryTree<BitmapsetN> *gpuqo_run_dpdp_union(int gpuqo_algo, 
									GpuqoPlannerInfo<BitmapsetN>* info,
									int n_iters)
{
	printf("\n\tSTART of UnionDP\n\n");
	printf("\n f(x): gpu_run_dpdp_union \n");
	list<remapper_transf_el_t<BitmapsetN> > remap_list;

	for (int i=0; i<info->n_rels; i++){
		remapper_transf_el_t<BitmapsetN> list_el;
		list_el.from_relid = info->base_rels[i].id;
		list_el.to_idx = i;
		list_el.qt = NULL;
		remap_list.push_back(list_el);
	}

	QueryTree<BitmapsetN> *out_qt = gpuqo_run_dpdp_union_rec<BitmapsetN,BitmapsetN>(
						gpuqo_algo, info, remap_list, 
						n_iters > 0 ? n_iters : gpuqo_idp_n_iters);
	printf("\tOUT OF RECURSION\n");
	std::cout << "FINAL UNION_DP Join Tree Cost: " << out_qt->cost.total << std::endl;
	printf("\n\tEND\n\n");
	level_of_dp = 0;
	return out_qt;
}

template QueryTree<Bitmapset32> *gpuqo_run_dpdp_union<Bitmapset32>(int,  GpuqoPlannerInfo<Bitmapset32>*,int);
template QueryTree<Bitmapset64> *gpuqo_run_dpdp_union<Bitmapset64>(int,  GpuqoPlannerInfo<Bitmapset64>*,int);
template QueryTree<BitmapsetDynamic> *gpuqo_run_dpdp_union<BitmapsetDynamic>(int,  GpuqoPlannerInfo<BitmapsetDynamic>*,int);