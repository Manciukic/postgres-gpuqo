/*-------------------------------------------------------------------------
 *
 * gpuqo.cuh
 *	  function prototypes and struct definitions for CUDA/Thrust code
 *
 * src/include/optimizer/gpuqo.cuh
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_CUH
#define GPUQO_CUH

#include <iostream>
#include "optimizer/gpuqo_common.h"
#include "optimizer/gpuqo_uninitalloc.cuh"

struct JoinRelation{
	unsigned int left_relation_idx;
	unsigned int right_relation_idx;
	unsigned int rows;
	double cost;
	EdgeMask edges;
	// I could store more information but I'm striving to keep it as small as 
	// possible

public:
	__host__ __device__
	bool operator<(const JoinRelation &o) const
	{
		return cost < o.cost;
	}

	__host__ __device__
	bool operator>(const JoinRelation &o) const
	{
		return cost > o.cost;
	}

	__host__ __device__
	bool operator==(const JoinRelation &o) const
	{
		return cost == o.cost;
	}

	__host__ __device__
	bool operator<=(const JoinRelation &o) const
	{
		return cost <= o.cost;
	}

	__host__ __device__
	bool operator>=(const JoinRelation &o) const
	{
		return cost >= o.cost;
	}
};

std::ostream & operator<<(std::ostream &os, const JoinRelation& jr)
{
	os<<"("<<jr.left_relation_idx<<","<<jr.right_relation_idx;
	os<<"): rows="<<jr.rows<<", cost="<<jr.cost;
	return os;
}

typedef thrust::device_vector<RelationID, uninitialized_allocator<RelationID> > uninit_device_vector_relid;
typedef thrust::device_vector<JoinRelation, uninitialized_allocator<JoinRelation> > uninit_device_vector_joinrel;

#endif							/* GPUQO_CUH */
