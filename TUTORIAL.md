
# Tutorial
This file contains walkthroughs to generating some of the results of the paper.

## MPDP on Star database
### Create an example star database
1. change directory to `$REPO/scripts/databases/star-small`

2. generate SQL scripts for creation and queries running `./star.py`

3. create and populate the DB in Postgres
```bash
DBNAME=star-small
createdb -p $PORT $DBNAME
psql -p $PORT -f create_tables.sql $DBNAME
psql -p $PORT -f fill_tables.sql $DBNAME

# try out a query
psql -p $PORT -f queries/02aa.sql $DBNAME
```

### Optimize your first query using GPUs
1. change directory to `$REPO/scripts/query`

2. stop the Postgres daemon
```bash
kill $(head -n 1 < $PGDATA/postmaster.pid)
```

3. run a query:
```bash
QUERYDIR=../databases/small/star/queries

# Usage:
# 1. algorithm
# 2. operation and output style (summary only optimizes)
# 3. database
# 4. role
# 5. timeout (in seconds)
# 6. warmup query (run this before the main query to warm the nvidia driver)
# 7. queries to run
# environment options (most important):
# * GPU options:
#   - max_memo_size: memory available to the GPU algorithm in MB (default 7G).
#       make sure this is lower than the available GPU memory
#   - n_parallel: configures parallelism level (default 40960). As a rule of thumb,
#       set it to number of multiprocessors times number of threads per multiprocessor.
# * CPU otions:
#   - n_threads: number of parallel threads (default 8)
# * IDP options:
#   - idp_n_iters: number of iterations
#   - idp_type: IDP1, IDP2, UNIONDP
# the script stops when it encounters two failures (including timeouts) in a row
bash run_all_generic.sh gpuqo_bicc_dpsub \
    summary \
    star-small \
    $USER \
    60 \
    $QUERYDIR/02aa.sql \
    $QUERYDIR/20aa.sql
# Planning Time: 75.942 ms (for a 20 table star query!)
```

### Run multiple experiments and plot results
In the `scripts/examples/start-small` folder there is an example on how the scripts
in the `scripts/` folder can be used to run multiple experiments on the `star-small`
database just created.

```bash
# this command will run many experiments using the run_all_generic.sh script
# see the contents of the script for more options
bash run_experiments.sh

# this command will aggregate the data in the benchmarks/ folder and generate
# a plot (plot.png)
# see the contents of the script for more options
bash plot.sh
```