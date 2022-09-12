# Commands

Scripts under `/scripts` and  `/misc/analysis`:

## Run Experiments
Uses the EXPLAIN command of postgres to get a printout of the calculated costs

**Example 1:**   
"Run UNIONDP (15) on snowflake3 query 40aa.sql with mpdp on GPU and output json summary with no warmup ":  
`$ idp_type=UNIONDP idp_n_iters=15 ./run_all_generic.sh gpuqo_bicc_dpsub summary-json snowflake3 postgres 65 'SELECT 1;' /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0040aa.sql`   

**Example 2:**  
"Run all 30 and 1000 rel experiments for UNIONDP(MPDP) with max partition size 25, warmup query 0100aa.sql, and save the results in /scratch2/postgres/benchmarks/UNIONDP/<filename.txt>:"

`$ idp_type=UNIONDP idp_n_iters=25 ./run_all_generic.sh gpuqo_bicc_dpsub summary-full snowflake3 postgres 65 /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0100aa.sql /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0030**.sql /scratch2/rmancini/postgres/src/misc/snowflake2/queries/1000**.sql | tee /scratch2/postgres/benchmarks_5/UNIONDP/0315_union15card.txt`

In general:  
`$ idp_type=HEUR_TYPE idp_n_iters=X ./run_all_generic.sh ALGORITHM SUMMARY-TYPE DATABASE USER TIMEOUT WARMUP_QUERY TARGET_QUERY`
- HEURISTIC_TYPE (only needed for heuristics) = IDP1, IDP2, UNIONDP 
- X (only needed for idp/union heuristics) = integer k usually 15 or 25 (max partition size)
- `ALGORITHM`: 
    - GEQO = `geqo`
    - MPDP(CPU) = `parallel_cpu_dpsub_bicc`
    - MPDP(GPU) = `gpuqo_bicc_dpsub`
    - GOO = `gpuqo_cpu_goo`
    - Adaptive = `gpuqo_cpu_dplin`
    - IKKBZ = `gpuqo_cpu_ikkbz`
    - IDP_25(MPDP) = `gpuqo_bicc_dpsub` (with idp_type=`IDP2`, idp_n_iters=`25`)
    - UnionDP_15(MPDP) = `gpuqo_bicc_dpsub` (with idp_type=`UNIONDP`, idp_n_iters=`15`)
- `SUMMARY-TYPE`: `summary-full`, `summary-json` etc. (can be found in `run_all_generic.sh` script )
- `DATABASE` : database name eg. snowflake
- `USER` : owner of database
- `TIMEOUT` : timeout in seconds (60 or 65)
- `WARMUP_QUERY`: usually one of the smaller queries
- `TARGET_QUERY`: queries to be optimized (eg. if you want all 100 rel queries do 100**.sql)

---
## Calculate Cost Table

**Example:**   
Assuming all experiments have been saved under directories in `/benchmark/ALGORITHM` calculate the normalized cost (using postgres cost estimator `postgres_cost`) table as per the table in the paper:

`$ python3 analyze_cost.py  /benchmark/GEQO /benchmark_snow2/GOO /benchmark_snow2/LINDP /benchmark_snow2/IDP_25  /benchmark_snow2/UNIONDP_25 /benchmark_snow2/IDP_25_fk  -m postgres_cost -t scatter_line --csv /benchmark_snow2/results/0310_results_fk.csv  -r`   


# Setup build flags (debug and release)   
- RELEASE build used for experiments  
- DEBUG build used for debugging (will print terminal output)  
    - in vscode wishing to debug click "Run"->"Start Debugging" 
    - (needs to be in debug mode)
    - `launch.json` (change snowflake3 to the db you're trying to debug):
    ``` json
    {
    "version": "0.2.0",
    "configurations": [
            {
                "name": "(gdb) Launch",
                "type": "cppdbg",
                "request": "launch",
                "program": "${workspaceFolder}/opt/bin/postgres",
                "args": ["--single", "snowflake3"],
                "stopAtEntry": false,
                "cwd": "${workspaceFolder}",
                "environment": [],
                "externalConsole": false,
                "MIMode": "gdb",
                "setupCommands": [
                    {
                        "description": "Enable pretty-printing for gdb",
                        "text": "-enable-pretty-printing",
                        "ignoreFailures": true
                    }
                ]
            }
        ]
    }
    ```


## SETUP  
Compilation is for a classic makefile project:    
`$ ./configure`    
After configure is done, you can just make it:  
`$ make` use `-j` to specify how many processes to use  
`$ make install`  

There are some flags to enable in config. I've been using the following configurations for debugging and testing (aka release).

### Debug:
``` sh
$ CFLAGS="-O0" ./configure      \ # prevent optimization to improve use of gdb
        --prefix=$(pwd)/../opt  \ # where to install it
        --without-readline      \ # missing package in diascld30
        --enable-debug          \ # debugging symbols
        --enable-cuda           \ # if cuda is installed
        --with-cudasm=61        \ # GTX1080, it may be different in other GPUs
        --enable-cassert        \ # enables sanity Asserts throughout the code
        --enable-depend           # don't remember :)
```
### Release:
``` sh
$ CFLAGS="-march=native -mtune=native"          \ # these enable cpu specific
        CPPFLAGS="-march=native -mtune=native"  \ # extensions (BMI,BMI2)
        ./configure                             \
        --prefix=$(pwd)/../opt                  \
        --without-readline                      \
        --with-icu                              \
        --enable-cuda                           \
        --with-cudasm=61
```


# Databases-large
**note**
You can change postgres max column size under `/src/include/access/htup_details.h` where you will find `#define MaxTupleAttributeNumber`.  
This is needed when working with the large databases.


You will find documentation and scripts needed under `/scripts/databases`


## Snowflake  
- location: `/scripts/databases/snowflake-large`  

Snowflake Schema (1000 tables - 4 level deep snowflake t_l1_l2_l3_l4):   

Fact table cardinality : 10M     
Dimension table cardinality : random between (10k, 1M)   
Queries: Up to 1000 relations, but you can generate more with scripts provided

*You can also change these parameters by changing variables in the star.py script.*

----------------   

To generate the snowflake database (assuming your_db_name='snowflake-large'):  

Step 0: Create a database named 'snowflake-large' :
- have postgres running in a terminal and in another `$ createdb snowflake-large`

Step 1: The snowflake.py script will create a fact table with 1M rows (so you need to insert into itself until 10M)  

Step 2: `$ psql -f create_tables.sql snowflake-large`   

Step 3: `$ psql -f fill_tables.sql snowflake-large`   

Step 4: Then run the grow_fact_table.py script  
- `$ python3 grow_fact_table.py`  
- make sure you have the correct params (based on your snowflake db):  
		default are: 
	``` python3
	fact_table_cardinality = 1_000_000
	times_to_grow_table = 9
	db_name = 'snowflake-large'
	```
- By default it inserts the contents of the fact table into itself until you reach 10M rows (insert 1M rows 9 times).    

Step 5: `$ psql -f add_foreign_keys.sql snowflake-large`   

## Star
- location: `/scripts/databases/star-large`  

1600 total tables   
Fact table cardinality : 1M rows  
Dimension table cardinality : random between (10k, 1M)  
Queries: The queries have predicates with random selectivity between (20%, 80%)  

*You can also change these parameters by changing variables in the star.py script.*

----------------  

To generate the star-large database (assuming your_db_name='star-large'):  

Step 0: Create a database named 'star-large' :
- have postgres running in a terminal and in another `$ createdb star-large`

Step 1: The star.py script will create a fact table with 1M rows and 1599 dimension tables  
- Make sure you're running Postgres

Step 2: `$ psql -f create_tables.sql star-large`    

Step 3: `$ psql -f fill_tables.sql star-large`    
- if Step 3 fails due to memory issue, you need to break up the insert statements into smaller chunks and then insert them into the db. This is done with: 
- Step 3.1: `$ python3 break_up_and_insert.py`   
- Make sure if you changed the star.py parameters to also change variables in this script (num_dimension_tables, fact_table_cardinality,max_card_per_insert,db_name)

Step 4: `$ psql -f add_foreign_keys.sql star-large`  



## Clique
- location: `/scripts/databases/clique-large`  

200 tables  
Table cards : Depends on your clique. Ours had random card between (0, 650k)  
Queries: The queries are not only PK-FK joins, like with snowflake and star   

------------------  

To generate the clique-large database (assuming your_db_name='clique-large'):  
Step 0: Create a database named 'clique-large' :
- have postgres running in a terminal and in another `$ createdb clique-large`  


Step 1: The clique.py script will create the .sql scipts; the /inserts folder; the /queries folder.  
- Make sure you're running Postgres  

Step 2: `$ psql -f create_tables.sql clique-large`  

Step 3: `$ python3 run_inserts.py`   
- make sure if you changed the num of tables in clique.py to change it here also
