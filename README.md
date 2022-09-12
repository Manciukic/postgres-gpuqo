# PostgreSQL GPU Query Optimization

This repository contains the implementation of the new join order optimization
algorithms described in the paper "Efficient Massively Parallel Join
Optimization for Large Queries".
It contains:
 - source code for the novel MPDP/UnionDP algorithms, both CPU and GPU
 - source code for the CPU and GPU baseline algorithms (dpsize, dpsub, dpccp,
   dpe, gpu-dpsize, gpu-dpsub)
 - source code of other experimental algorithms (e.g. dpsub-csg)
 - scripts used for running the tests, creating the synthetic databases,
   generating the data to plot (inside the misc/ folder)

## Documentation

1. To compile and install Postgres with GPU optimization follow the [Installation Guide](INSTALLATION.md)
2. To run an example query, experiments and plot the results follow [Tutorial](TUTORIAL.md).
3. Other documentation can be found under [DOCS.md](DOCS.md) and under `/scripts/databases` for each dataset

## Usage

### Configuration

The following settings can be set in Postgres to use the gpuqo module and
choose the algorithm and its parameters:
 + GeQo (genetic optimizer):
   - `geqo`: enable/disable geqo
   - `geqo_threshold`: number of tables to start using geqo
 + GPU-QO:
   - `gpuqo`: enable/disable gpuqo module
   - `gpuqo_threshold`: number of tables to start using gpuqo (set to 2 to always
                      use it)
   - `gpuqo_algorithm`: one of:
     * `cpu_dpsize`:      DPsize on CPU (sequential)
     * `cpu_dpsub`:       DPsub on CPU (sequential)
     * `cpu_dpsub_bicc`:  MP-DP (aka DPsub w/ BiConnected Component optimization)
                        on CPU (sequential)
     * `cpu_dpccp`:       DPccp on CPU (sequential)
     * `dpe_dpsize`:      DPsize on CPU (parallel) using DPE.
     * `dpe_dpsub`:       DPsub on CPU (parallel) using DPE.
     * `dpe_dpccp`:       DPccp on CPU (parallel) using DPE.
     * `parallel_cpu_dpsub`: DPsub on CPU (parallel) using DPsub-specific
                           parallelization.
     * `parallel_cpu_dpsub_bicc`: MP-DP on CPU (parallel) using DPsub-specific
                                parallelization.
     * `dpsize`:          DPsize on GPU. See "dpsize\ options" below
     * `dpsub`:           DPsub on GPU. See "dpsub options" below
   - GPU options:
     * `gpuqo_min_memo_size_mb`: set (lowerbound) for starting size of memo in MB
     * `gpuqo_max_memo_size_mb`: set max size of memo hashtable in MB.
                               The memo grows by powers of 2 (of elements).
     * `gpuqo_n_parallel`: number of items to execute at a time. Set this value
                         depending on your GPU.
                         Heuristically, this should be set in such a way that
                         all GPU threads are kept busy, therefore a good value
                         could be "maximum number of threads per multiprocessor"
                         times "number of multiprocessors".
                         TODO: set it automatically.
     * `gpuqo_scratchpad_size_mb`: size of temporary memory location used to store
                                 intermediate sets. Should be big enough to fit
                                 gpuqo_n_parallel sets.
   - dpsub options (GPU):
     * `gpuqo_dpsub_bicc`: use MPDP instead of plain dpsub
     * `gpuqo_dpsub_csg`: (experimental) use csg enumeration
     * `gpuqo_dpsub_csg_threshold`: (experimental) threshold to start using csg
     * `gpuqo_dpsub_tree`: (experimental) if set is a tree, use MPDP tree variant
                         instead of generic one.
   - dpsub advanced options (GPU):
     * `gpuqo_dpsub_filter`: enable filtering of invalid unranked sets (default: on).
     * `gpuqo_dpsub_filter_threshold`: minimum number of sets to unrank to use
                                     filtering (default: 0).
     * `gpuqo_dpsub_filter_cpu_enum_threshold`: if number of sets is lower than
                                              this threshold, do filtering on
                                              CPU.
     * `gpuqo_dpsub_filter_keys_overprovisioning`: number of sets to unrank at a
                                                 time as multiple of scratchpad
                                                 size.
     * gpuqo_dpsub_ccc: enable CCC warp-divergence prevention algorithm (only
                        works on plain DPsub) (default: on).
   - parallel CPU options:
    * `gpuqo_dpe_n_threads`: number of threads to use (both dpe_* and parallel_*).
    * `gpuqo_cpu_dpsub_parallel_chunk_size`: number of sets to unrank at a time
                                           per worker in DPSUB parallel variant.
   - IDP options:
     * `gpuqo_idp_type`: IDP1 or IDP2 or UNIONDP
     * `gpuqo_idp_n_iters`: k parameter for IDP and UNIONDP (recommended = 25), 0 to disable

### Example
running IDP2 with MPDP (GPU) using k = 25:
```sql
-- to be sure to use gpuqo, disable geqo and set gpuqo threshold to 2
SET geqo TO off;
SET geqo_threshold TO 2;

-- select gpuqo algorithm
SET gpuqo_algorithm TO dpsub;
SET gpuqo_dpsub_bicc TO on;

-- make sure other dpsub features are to default values
SET gpuqo_dpsub_filter TO on;
SET gpuqo_dpsub_filter_threshold TO 0;
SET gpuqo_dpsub_csg TO off;
SET gpuqo_dpsub_tree TO off;

-- enable IDP
SET gpuqo_idp_type TO 2;
SET gpuqo_idp_n_iters TO 25;

SELECT * FROM ...;
```

These settings can be set to the best predefined values using the
`run_all_generic.sh` script inside misc/analysis/.
The script can be used to run tests on multiple queries.
Example (same as above with ):
```bash
idp_type=IDP2 idp_n_iters=25 \
    run_all_generic.sh gpuqo_bicc_dpsub \
    snowflake user \
    60 \
    warmup.sql \
    queries/*.sql
```
Note: the warmup query is called before each query to prevent measuring one-time
overheads of the CUDA driver.
In bash, you can specify also `<(echo "SELECT 1;")` if you don't want to specify a
query.

For more information about how bulk experiments were run refer to [Tutorial](TUTORIAL.md) and [DOCS](DOCS.md)

## Limitations

The current "postgres" cost function implemented in GPU-QO supports only certain
types of joins. It is equivalent to Postgres internal cost function when
Postgres is run with the following options:

```sql
SET enable_seqscan TO on;
SET enable_indexscan TO on;
SET enable_indexonlyscan TO off;
SET enable_tidscan TO off;
SET enable_mergejoin TO off;
SET enable_parallel_hash TO off;
SET enable_bitmapscan TO off;
SET enable_gathermerge TO off;
SET enable_partitionwise_join TO off;
SET enable_material TO off;
SET enable_hashjoin TO on;
SET enable_nestloop TO on;
```

Furthemore, it has only been tested in simple queries of the form:
```sql
SELECT * FROM A, B, C WHERE A.col1 = B.col3 AND ...;
```

## Code Structure

Notes on the code:
a lot of templates are being used in the code to compile the best CUDA code
for different cases (different bitset sizes and so on).

All gpuqo algorithms are inside `src/backend/optimizer/gpuqo/`
 - `gpuqo_main.c`: entry point for the gpuqo module. This file performs all the
                 glueing with Postgres, like extracting information from the
                 planner and building the query plan.
 - `gpuqo_main_internal.cu`: entry point for the C++/CUDA part of the gpuqo module,
                           it is just a proxy to the correct function to be
                           called. It also performs the conversion from Postgres
                           data structures to GPU-friendly datastructures
                           (GpuqoPlannerInfo<...>, QueryTree<...>).
 - `gpuqo_remapper.cu`, `gpuqo_remapper.cuh`:
    Utility for remapping indexes and creating temporary compound tables to be
    used in IDP.
 - `gpuqo_bfs_indexing.cu`:
    Generate a remapper to relabel tables with a BFS-consistent order.
 - `gpuqo_spanning_tree.cu`
    Compute the spanning tree of a graph. Used in tree mode.
 - `gpuqo_bit_manipulation.cuh`
    Low-level bit manipulation
 - `gpuqo_bitmapset.cuh`
    GPU-efficient bitmapset implementation (32 or 64 bits)
 - `gpuqo_bitmapset_dynamic.cuh`
    dynamic bitmapset implementation for CPU based on Postgres bitmapset.
    NB: much slower than static bitmapset.
 - `gpuqo_cost*`:
    Cost functions
 - `gpuqo_row_estimation.cuh`
    Row estimation of a join
 - `gpuqo_binomial.cu`, `gpuqo_binomial.cuh`:
    Binomial coefficient pre-calculation for dpsub unranking.
 - `gpuqo_cpu_*`:
    Implementation of CPU algorithm. There are some common abstract classes that
    are implemented by the different algorithms so that they could be used in
    sequential and DPE mode using a common code.
 - `gpuqo_cpu_level_hashtable.cuh`:
    Memo table where there is one hashtable for each set size, used in parallel
    MPDP (CPU).
 - `gpuqo_dependency_buffer.cu`, `gpuqo_dependency_buffer.cuh`:
    Dependency-aware datastructure used by DPE.
 - `gpuqo_dpsize.cu`:
    dpsize (GPU)
 - `gpuqo_dpsub*`:
    dpsub (GPU). There is a common code and then specific enumeration algorithms
    (plain, mpdp aka bicc, csg, tree).
    Code for filtered and unfiltered is divided.
 - `gpuqo_filter.cuh`:
    Utilities for filtering invalid sets (functions, unary functors, ...).
 - `gpuqo_hashtable.cu`, `gpuqo_hashtable.cuh`:
    Simple GPU hashtable using open addressing
 - `gpuqo_idp.cu`
    IDP1 and IDP2 implementation
 - `gpuqo_dpdp_union.cu`
    UNIONDP implementation
 - `gpuqo_planner_info.cu`, `gpuqo_planner_info.cuh`:
    Utilities for converting planner info between different sizes
 - `gpuqo_postgres.cuh`:
    Import some useful macros from postgres
 - `gpuqo_query_tree.cuh`
    Utilities for converting query trees.
 - `gpuqo_debug.cu`, `gpuqo_debug.cuh`, `gpuqo_timing.cuh`:
    Debugging and profiling macros
 - `gpuqo_uninitalloc.cuh`
    Thrust vector without initialization

Other folders:
 - `scripts/` contains example scripts to run some queries and generate random
databases.
 - `misc/` contains other scripts and files used in the experiments on the paper.

## Publications
 - Riccardo Mancini, Srinivas Karthik, Bikash Chandra, Vasilis Mageirakos, and Anastasia Ailamaki 2022. Efficient Massively Parallel Join Optimization for Large Queries. In SIGMOD '22: International Conference on Management of Data, Philadelphia, PA, USA, June 12 - 17, 2022 (pp. 122–135). ACM. https://doi.org/10.1145/3514221.3517871
 - Vasilis Mageirakos, Riccardo Mancini, Srinivas Karthik, Bikash Chandra, and Anastasia Ailamaki 2022. Efficient GPU-accelerated Join Optimization for Complex Queries. In 38th IEEE International Conference on Data Engineering, ICDE 2022, Kuala Lumpur, Malaysia, May 9-12, 2022 (pp. 3190–3193). IEEE. https://doi.org/10.1109/ICDE53745.2022.00295
