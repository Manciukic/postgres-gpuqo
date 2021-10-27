/*------------------------------------------------------------------------
 *
 * gpuqo_remapper.cu
 *      implementation for class for remapping relations to other indices
 *
 * src/backend/optimizer/gpuqo/gpuqo_remapper.cu
 *
 *-------------------------------------------------------------------------
 */

#include "gpuqo_remapper.cuh"
#include "gpuqo_cost.cuh"

template<typename BitmapsetIN, typename BitmapsetOUT>
Remapper<BitmapsetIN,BitmapsetOUT>::Remapper(list<remapper_transf_el_t<BitmapsetIN> > _transf) 
                                : transf(_transf) {}

template<typename BitmapsetIN, typename BitmapsetOUT>
void Remapper<BitmapsetIN,BitmapsetOUT>::countEqClasses(GpuqoPlannerInfo<BitmapsetIN>* info, 
                                        int* n, int* n_sels, int *n_fk, int *n_vars)
{
    *n = 0;
    *n_sels = 0;
    *n_fk = 0;
    *n_vars = 0;

    for (int i = 0; i < info->eq_classes.n; i++){
        bool found = false;
        for (remapper_transf_el_t<BitmapsetIN> &e : transf){
            if (info->eq_classes.relids[i].isSubset(e.from_relid)){
                found = true;
                break;
            }
        }
        if (!found){
            (*n)++;
            (*n_fk) += info->eq_classes.relids[i].size();
            (*n_vars) += info->eq_classes.relids[i].size();
            (*n_sels) += eqClassNSels(info->eq_classes.relids[i].size());
        }
    }
}

template<typename BitmapsetIN, typename BitmapsetOUT>
BitmapsetOUT Remapper<BitmapsetIN,BitmapsetOUT>::remapRelid(BitmapsetIN id)
{
    BitmapsetOUT out(0);
    for (remapper_transf_el_t<BitmapsetIN> &e : transf){
        if (e.from_relid.intersects(id)){
            out.set(e.to_idx+1);
        }
    }

    return out;
}

template<typename BitmapsetIN, typename BitmapsetOUT>
BitmapsetOUT Remapper<BitmapsetIN,BitmapsetOUT>::remapRelidNoComposite(BitmapsetIN id, GpuqoPlannerInfo<BitmapsetIN> *info_from)
{
    BitmapsetOUT out = BitmapsetOUT(0);
    for (remapper_transf_el_t<BitmapsetIN> &e : transf){
        if (e.from_relid.size() > 1 || info_from->base_rels[e.from_relid.lowestPos()-1].composite)
            continue;
        if (e.from_relid.intersects(id)){
            out.set(e.to_idx+1);
        }
    }

    return out;
}

template<typename BitmapsetIN, typename BitmapsetOUT>
BitmapsetIN Remapper<BitmapsetIN,BitmapsetOUT>::remapRelidInv(BitmapsetOUT id)
{
    BitmapsetIN out = BitmapsetIN(0);
    for (remapper_transf_el_t<BitmapsetIN> &e : transf){
        if (id.isSet(e.to_idx+1)){
            out |= e.from_relid;
        }
    }

    return out;
}

template<typename BitmapsetIN, typename BitmapsetOUT>
void Remapper<BitmapsetIN,BitmapsetOUT>::remapEdgeTable(BitmapsetIN* edge_table_from, 
                                            BitmapsetOUT* edge_table_to,
                                            GpuqoPlannerInfo<BitmapsetIN> *info_from,
                                            bool ignore_composite)
{
    for (remapper_transf_el_t<BitmapsetIN> &e : transf){
        edge_table_to[e.to_idx] = BitmapsetOUT(0);
        
        BitmapsetIN temp = e.from_relid;
        while(!temp.empty()){
            int from_idx = temp.lowestPos()-1;

            if (ignore_composite)
                edge_table_to[e.to_idx] |= remapRelidNoComposite(edge_table_from[from_idx], info_from);
            else
                edge_table_to[e.to_idx] |= remapRelid(edge_table_from[from_idx]);

            temp.unset(from_idx+1);
        }
        edge_table_to[e.to_idx].unset(e.to_idx+1);
    }
}

template<typename BitmapsetIN, typename BitmapsetOUT>
void Remapper<BitmapsetIN,BitmapsetOUT>::remapBaseRels(
                                BaseRelation<BitmapsetIN>* base_rels_from, 
                                BaseRelation<BitmapsetOUT>* base_rels_to)
{

    for (remapper_transf_el_t<BitmapsetIN> &e : transf){
        if (e.qt != NULL){
            base_rels_to[e.to_idx].id = remapRelid(e.from_relid);
            base_rels_to[e.to_idx].rows = e.qt->rows;
            base_rels_to[e.to_idx].cost = e.qt->cost;
            base_rels_to[e.to_idx].width = e.qt->width;
            base_rels_to[e.to_idx].tuples = e.qt->rows;
        } else {
            BaseRelation<BitmapsetIN> &baserel = base_rels_from[e.from_relid.lowestPos()-1];

            base_rels_to[e.to_idx].id = remapRelid(e.from_relid);
            base_rels_to[e.to_idx].rows = baserel.rows;
            base_rels_to[e.to_idx].cost = baserel.cost;
            base_rels_to[e.to_idx].width = baserel.width;
            base_rels_to[e.to_idx].tuples = baserel.tuples;
        }
        
        if (e.from_relid.size() == 1){
            int idx = e.from_relid.lowestPos()-1;

            base_rels_to[e.to_idx].composite = base_rels_from[idx].composite;
        } else {
            base_rels_to[e.to_idx].composite = true;
        }
    }
}

template<typename BitmapsetIN, typename BitmapsetOUT>
void Remapper<BitmapsetIN,BitmapsetOUT>::remapEqClass(BitmapsetIN* eq_class_from,
                                        float* sels_from,
                                        BitmapsetIN* fks_from,
                                        VarInfo* vars_from,
                                        GpuqoPlannerInfo<BitmapsetIN>* info_from,
                                        int off_sels_from, int off_fks_from,
                                        BitmapsetOUT* eq_class_to,
                                        float* sels_to,
                                        BitmapsetOUT* fks_to,
                                        VarInfo* vars_to)
{
    *eq_class_to = remapRelid(*eq_class_from);

    int s_from = eq_class_from->size();
    int s_to = eq_class_to->size();

    for (int idx_l_to = 0; idx_l_to < s_to; idx_l_to++){
        BitmapsetOUT id_l_to = expandToMask(BitmapsetOUT::nth(idx_l_to), 
                                            *eq_class_to); 
        BitmapsetIN id_l_from = remapRelidInv(id_l_to);
        int idx_l_from = (id_l_from.allLower() & *eq_class_from).size();

        Assert(idx_l_from < s_from);
        Assert(idx_l_to < s_to);

        for (int idx_r_to = idx_l_to+1; idx_r_to < s_to; idx_r_to++){
            BitmapsetOUT id_r_to = expandToMask(BitmapsetOUT::nth(idx_r_to), 
                                                *eq_class_to); 
            BitmapsetIN id_r_from = remapRelidInv(id_r_to);
            int idx_r_from = (id_r_from.allLower() & *eq_class_from).size();

            int sels_to_idx = eqClassIndex(idx_l_to, idx_r_to, s_to);
            int sels_from_idx = eqClassIndex(idx_l_from, idx_r_from, s_from);

            if (id_l_from.size() == id_l_to.size() 
                && id_r_from.size() == id_r_to.size())
            {
                sels_to[sels_to_idx] = sels_from[sels_from_idx];
            } else {
                sels_to[sels_to_idx] = estimate_ec_selectivity(
                    *eq_class_from, off_sels_from, off_fks_from,
                    id_l_from, id_r_from, info_from
                );

            }
        }

        if (id_l_from.size() == 1 && !info_from->base_rels[id_l_from.lowestPos()-1].composite)
            fks_to[idx_l_to] = remapRelidNoComposite(fks_from[idx_l_from], info_from);
        // choose one at random
        vars_to[idx_l_to] = vars_from[idx_l_from]; 
        if (id_l_from.size() > 1) {
            vars_to[idx_l_to].index.available = false;
        }
    }
}

template<typename BitmapsetIN, typename BitmapsetOUT>
GpuqoPlannerInfo<BitmapsetOUT> *Remapper<BitmapsetIN,BitmapsetOUT>::remapPlannerInfo(
                                        GpuqoPlannerInfo<BitmapsetIN>* old_info)
{
    int n_rels = transf.size();
    int n_eq_classes, n_eq_class_sels, n_eq_class_fks, n_eq_class_vars; 
    countEqClasses(old_info, &n_eq_classes, &n_eq_class_sels, &n_eq_class_fks, &n_eq_class_vars); 

    size_t size = plannerInfoSize<BitmapsetOUT>(n_eq_classes, n_eq_class_sels, 
                                            n_eq_class_fks, n_eq_class_vars);

	char* p = new char[size];
    memset(p, 0, size);

	GpuqoPlannerInfo<BitmapsetOUT> *info = (GpuqoPlannerInfo<BitmapsetOUT>*) p;
	p += plannerInfoBaseSize<BitmapsetOUT>();

	info->size = size;
	info->n_rels = n_rels;
	info->n_iters = old_info->n_iters;
    info->params = old_info->params;

    initGpuqoPlannerInfo(info);

    remapEdgeTable(old_info->edge_table, info->edge_table, old_info);

    if (gpuqo_spanning_tree_enable)
        remapEdgeTable(old_info->subtrees, info->subtrees, old_info);

	remapBaseRels(old_info->base_rels, info->base_rels);

	info->eq_classes.n = n_eq_classes;
	info->eq_classes.n_sels = n_eq_class_sels;
	info->eq_classes.n_fks = n_eq_class_fks;
	info->eq_classes.n_vars = n_eq_class_vars;

	info->eq_classes.relids = (BitmapsetOUT*) p;
	p += plannerInfoEqClassesSize<BitmapsetOUT>(info->eq_classes.n);
	info->eq_classes.sels = (float*) p;
	p += plannerInfoEqClassSelsSize<BitmapsetOUT>(info->eq_classes.n_sels);
	info->eq_classes.fks = (BitmapsetOUT*) p;
	p += plannerInfoEqClassFksSize<BitmapsetOUT>(info->eq_classes.n_fks);
	info->eq_classes.vars = (VarInfo*) p;
	p += plannerInfoEqClassVarsSize<BitmapsetOUT>(info->eq_classes.n_vars);

    int off_sel = 0, off_fk = 0, old_off_sel = 0, old_off_fk = 0, j = 0;
	for (int i = 0; i < old_info->eq_classes.n; i++){
        bool found = false;
        for (remapper_transf_el_t<BitmapsetIN> &e : transf){
            if (old_info->eq_classes.relids[i].isSubset(e.from_relid)){
                found = true;
                break;
            }
        }
        if (!found){
            remapEqClass(
                &old_info->eq_classes.relids[i], 
                &old_info->eq_classes.sels[old_off_sel], 
                &old_info->eq_classes.fks[old_off_fk], 
                &old_info->eq_classes.vars[old_off_fk], 
                old_info, old_off_sel, old_off_fk,
                &info->eq_classes.relids[j], 
                &info->eq_classes.sels[off_sel],
                &info->eq_classes.fks[off_fk],
                &info->eq_classes.vars[off_fk]
            );
            off_fk += info->eq_classes.relids[j].size();
            off_sel += eqClassNSels(info->eq_classes.relids[j].size());
            j++;
        }

        old_off_fk += old_info->eq_classes.relids[i].size();
        old_off_sel += eqClassNSels(old_info->eq_classes.relids[i].size());
    }

	return info;
}

template<typename BitmapsetIN, typename BitmapsetOUT>
QueryTree<BitmapsetIN>* Remapper<BitmapsetIN,BitmapsetOUT>::remapQueryTree(QueryTree<BitmapsetOUT>* qt){
    if (qt == NULL)
        return NULL;

    if (qt->id.size() == 1){
        int idx = qt->id.lowestPos() - 1;

        for (remapper_transf_el_t<BitmapsetIN> &e : transf){
            if (e.qt != NULL && e.to_idx == idx){
                return e.qt;
            }
        }
    }

    QueryTree<BitmapsetIN> *qt_out = new QueryTree<BitmapsetIN>;
    qt_out->id = remapRelidInv(qt->id);
    qt_out->left = remapQueryTree(qt->left);
    qt_out->right = remapQueryTree(qt->right);
    qt_out->rows = qt->rows;
    qt_out->cost = qt->cost;
    qt_out->width = qt->width;
    return qt_out;
}

template<typename BitmapsetIN, typename BitmapsetOUT>
QueryTree<BitmapsetOUT>* Remapper<BitmapsetIN,BitmapsetOUT>::remapQueryTreeFwd(QueryTree<BitmapsetIN>* qt){
    if (qt == NULL)
        return NULL;

    QueryTree<BitmapsetOUT> *qt_out = new QueryTree<BitmapsetOUT>;
    qt_out->id = remapRelid(qt->id);
    if (qt_out->id.size() == 1){
        qt_out->left = NULL;
        qt_out->right = NULL;
    } else {
        qt_out->left = remapQueryTreeFwd(qt->left);
        qt_out->right = remapQueryTreeFwd(qt->right);
    }
    qt_out->rows = qt->rows;
    qt_out->cost = qt->cost;
    qt_out->width = qt->width;
    return qt_out;
}

template class Remapper<Bitmapset32,Bitmapset32>;
template class Remapper<Bitmapset64,Bitmapset64>;
template class Remapper<Bitmapset64,Bitmapset32>;
template class Remapper<BitmapsetDynamic,BitmapsetDynamic>;
template class Remapper<BitmapsetDynamic,Bitmapset64>;
template class Remapper<BitmapsetDynamic,Bitmapset32>;


template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN> *cloneGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN>* info) 
{
    list<remapper_transf_el_t<BitmapsetN> > remap_list;
    for (int i = 0; i < info->n_rels; i++) {
        remapper_transf_el_t<BitmapsetN> el;
        el.from_relid = info->base_rels[i].id;
        el.to_idx = i;
        el.qt = NULL;
        remap_list.push_back(el);
    }
    Remapper<BitmapsetN,BitmapsetN> remapper(remap_list);
    return remapper.remapPlannerInfo(info);
}

template GpuqoPlannerInfo<Bitmapset32> *cloneGpuqoPlannerInfo(GpuqoPlannerInfo<Bitmapset32>* info);
template GpuqoPlannerInfo<Bitmapset64> *cloneGpuqoPlannerInfo(GpuqoPlannerInfo<Bitmapset64>* info);
template GpuqoPlannerInfo<BitmapsetDynamic> *cloneGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetDynamic>* info);