#!/bin/bash

DB=$1
QUERYDIR=../../databases/$DB/queries
RESULTDIR=benchmarks/$DB
ANALYZE=../../plot.py
OUTFILE=plot.png

# you can also pass -r to plot the ratio from the baseline (first parameter, dp in the example)
python3 $ANALYZE \
    -d $QUERYDIR \
    -m plan \
    -t scatter_line \
    -s $OUTFILE \
    $RESULTDIR/{dp,gpuqo_cpu_dpccp,gpuqo_cpu_dpsub_bicc,gpuqo_cpu_dpsub_bicc_parallel,gpuqo_dpsize,gpuqo_filtered_dpsub,gpuqo_bicc_dpsub}