/*------------------------------------------------------------------------
 *
 * gpuqo_remapper.cuh
 *      class for remapping relations to other indices
 *
 * src/backend/optimizer/gpuqo/gpuqo_remapper.cuh
 *
 *-------------------------------------------------------------------------
 */

#ifndef GPUQO_REMAPPER_CUH
#define GPUQO_REMAPPER_CUH

#include <list>
#include "optimizer/gpuqo_common.h"
#include "gpuqo_planner_info.cuh"

using namespace std;

template<typename BitmapsetIN>
struct remapper_transf_el_t {
    BitmapsetIN from_relid;
    int to_idx;
    QueryTree<BitmapsetIN> *qt;
};

template<typename BitmapsetIN, typename BitmapsetOUT>
class Remapper{
private:
    list<remapper_transf_el_t<BitmapsetIN> > transf;

    void countEqClasses(GpuqoPlannerInfo<BitmapsetIN>* info, 
                                            int* n, int* n_sels, int *n_fk, int *n_vars);
    BitmapsetOUT remapRelid(BitmapsetIN id);
    BitmapsetOUT remapRelidNoComposite(BitmapsetIN fid, GpuqoPlannerInfo<BitmapsetIN> *info_from);
    BitmapsetIN remapRelidInv(BitmapsetOUT id);
    void remapEdgeTable(BitmapsetIN* edge_table_from, BitmapsetOUT* edge_table_to, GpuqoPlannerInfo<BitmapsetIN> *info_from,
                        bool ignore_composite=false);
    void remapBaseRels(BaseRelation<BitmapsetIN>* base_rels_from,
                        BaseRelation<BitmapsetOUT>* base_rels_to);
    void remapEqClass(BitmapsetIN* eq_class_from, float* sels_from, 
                    BitmapsetIN* fks_from, VarInfo* vars_from,
                    GpuqoPlannerInfo<BitmapsetIN>* info_from,
                    int off_sels_from, int off_fks_from, 
                    BitmapsetOUT* eq_class_to, float* sels_to, BitmapsetOUT* fks_to,
                    VarInfo* vars_to);

public:
    Remapper<BitmapsetIN,BitmapsetOUT>(list<remapper_transf_el_t<BitmapsetIN>> _transf);

    GpuqoPlannerInfo<BitmapsetOUT>* remapPlannerInfo(
                                            GpuqoPlannerInfo<BitmapsetIN>* info);
    QueryTree<BitmapsetIN>* remapQueryTree(QueryTree<BitmapsetOUT>* qt);
    QueryTree<BitmapsetOUT>* remapQueryTreeFwd(QueryTree<BitmapsetIN>* qt);
};

template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN> *cloneGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN>* info);

#endif              // GPUQO_REMAPPER_CUH
