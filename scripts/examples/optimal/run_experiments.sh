#!/bin/bash

DB=$1
RUN_ALL_GENERIC=$(realpath ../../run_all_generic.sh)
QUERYDIR=$(realpath ../../databases/$DB/queries)
OUTDIR=benchmarks/$DB
TIMEOUT=60

QUERIES_STR=$(ls $QUERYDIR/{05,10,15,20,25,30}a{a,b,c}.sql)
read -d '' -r -a QUERIES <<< "$QUERIES_STR"

run(){
	local alg=$1
	local label=$2
	local outdir="${OUTDIR}/${label}"
	mkdir -p "$outdir"
	bash $RUN_ALL_GENERIC \
			$alg \
			summary-full \
			$DB $USER \
			$TIMEOUT \
			${QUERIES[0]} \
			${QUERIES[@]} \
		| tee $outdir/results0.txt
}

for alg in dp geqo gpuqo_cpu_dpccp gpuqo_cpu_dpsub_bicc gpuqo_cpu_dpsub_bicc_parallel gpuqo_dpsize gpuqo_filtered_dpsub gpuqo_bicc_dpsub; do 
	run $alg $alg 
done
