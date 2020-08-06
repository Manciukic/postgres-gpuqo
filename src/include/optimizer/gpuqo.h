/*-------------------------------------------------------------------------
 *
 * gpuqo.h
 *	  prototypes for gpuqo_main.c
 *
 * src/include/optimizer/gpuqo.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_H
#define GPUQO_H

#include "optimizer/gpuqo_common.h"

#include "nodes/pathnodes.h"

/* routines in gpuqo_main.c */
extern RelOptInfo *gpuqo(PlannerInfo *root,
						int number_of_rels, List *initial_rels);

extern QueryTree* gpuqo_dpsize(BaseRelation baserels[], int N);

#endif							/* GPUQO_H */
