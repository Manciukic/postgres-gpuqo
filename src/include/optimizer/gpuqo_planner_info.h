/*-------------------------------------------------------------------------
 *
 * gpuqo_planner_info.h
 *	  declaration of planner info for C files.
 *
 * src/include/optimizer/gpuqo_planner_info.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_PLANNER_INFO_H
#define GPUQO_PLANNER_INFO_H

#include <nodes/bitmapset.h>

typedef struct EquivalenceClass EquivalenceClass;

typedef Bitmapset* EdgeMask;
typedef Bitmapset* RelationID;

typedef struct EqClassInfo{
	EquivalenceClass* eclass;
	RelationID relids;
	float* sels;
	VarInfo* vars;
	RelationID* fk;
	struct EqClassInfo* next;
} EqClassInfo;

typedef struct BaseRelationC{
	RelationID id;
	float rows;
	float tuples;
	PathCost cost;
	int width;
} BaseRelationC;

typedef struct GpuqoPlannerInfoC{
	int n_rels;
	BaseRelationC *base_rels;
	EdgeMask* edge_table;
	EqClassInfo* eq_classes;
    int n_eq_classes;
    int n_eq_class_sels;
    int n_eq_class_fks;
    int n_eq_class_vars;
} GpuqoPlannerInfoC;

typedef struct QueryTreeC{
	RelationID id;
	float rows;
	PathCost cost;
	int width;
	struct QueryTreeC* left;
	struct QueryTreeC* right;
} QueryTreeC;
	
#endif							/* GPUQO_PLANNER_INFO_H */
