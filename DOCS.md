# Datasets

**Download: [Dataset generation scripts and queries](https://drive.google.com/file/d/1_iCxt1H0yIIcBDCMcobiPyyQ-BH0JduP/view?usp=sharing)**


**Genaral note** (needed to work with these large datasets):   
You can change postgres column under `/src/include/access/htup_details.h` where you will find `#define MaxTupleAttributeNumber`

---

## Musicbrainz
loc: `misc/musicbrainz`  

Musicbrainz is real world dataset (56 tables) that includes information about the music industry. 
We do not have access to query logs so we generate our own queries.

You can get MusicBrainz from : https://musicbrainz.org/doc/MusicBrainz_Database   
The NonPKFK.ipynb shows the MusicBrainz schema we use and query generation.

## Snowflake  
loc: `misc/snowflake`  

Snowflake Schema (1000 tables - 4 level deep snowflake t_l1_l2_l3_l4):     

Fact table cardinality : 10M         
Dimension table cardinality : random between (10k, 1M)     
Queries: Up to 1000 relations, but you can generate more with scripts provided   


### Option 1:  
```
If you have the snowflake.dump which was created with a custom-format dump file:  
$ pg_dump -Fc snowflake > snowflake.dump  

To  recreate it from the dump:   
$ createdb your_db_name  
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name snowflake.dump   
```

### Option 2:
Alternatively, to generate the snowflake database (assuming your_db_name='snowflake'):
```
Step 1: The snowflake.py script will create a fact table with 1M rows (so you need to insert into itself until 10M)
Step 2: $ psql -f create_tables.sql snowflake
Step 3: $ psql -f fill_tables.sql snowflake
Step 4: Insert the contents of the fact table into itself until you reach 10M rows.    
	"
	INSERT INTO T_1 (t_1_1, .... )
	SELECT t_1_1, ....
	FROM T_1
	LIMIT 1000000; 
	"
Step 5: $ psql -f add_foreign_keys.sql snowflake
```

## Star
loc: `misc/star`  

Star Schema (1600 tables):   

Fact table cardinality : 1M     
Dimension table cardinality : random between (10k, 1M)
Queries: The queries have predicates with random selectivity between (20%, 80%)

---

### Option 1:
```
If you have the star.dudmp which was created with a custom-format dump file:
$ pg_dump -Fc star > star.dump

To  recreate it from the dump: 
$ createdb your_db_name
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name star.dump
```

### Option 2:
Alternatively, to generate the star database (assuming your_db_name='star'):  
``` 
Step 1: The star.py script will created needed .sql scripts and /queries_with_pred folder
(Make sure you're running Postgres)
Step 2: $ psql -f create_tables.sql star
Step 3: $ psql -f fill_tables.sql star
	if Step 3 fails due to memory issue you need to break up the insert statement:
	Step 3.1: $ python3 break_up_and_insert.py
Step 4: $ psql -f add_foreign_keys.sql star
```

## Clique
loc: `misc/clique`  

Clique Schema (200 tables):   

Table cardinalities : Depends on your clique. The clique.dump one has random card between (0, 650k)
Queries: The queries are not just PK-FK joins


### Option 1:
```
If you have the clique.dump which was created with a custom-format dump file:
$ pg_dump -Fc clique > clique.dump

To  recreate it from the dump: 
$ createdb your_db_name
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name clique.dump
```
### Option 2:
```
Alternatively, to generate the clique database (assuming your_db_name='clique'):

Step 1: The clique.py script will create the .sql scipts; the /inserts folder; the /queries folder.
(Make sure you're running Postgres)
Step 2: $ psql -f create_tables.sql clique
Step 3: $ python3 run_inserts.py 
Step 4: $ psql -f add_foreign_keys.sql clique
```

# Commands

Scripts under `misc/analysis`:

---
## Run Experiments
Uses the EXPLAIN command of postgres to get a printout of the calculated costs

**Example 1:**   
"Run UNIONDP (15) on query 40aa.sql with mpdp on GPU and output json summary with no warmup query":  
`$ idp_type=UNIONDP idp_n_iters=15 ./run_all_generic.sh gpuqo_bicc_dpsub summary-json snowflake3 postgres 65 'SELECT 1;' /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0040aa.sql`   

**Example 2:**  
"Run all 30 and 1000 rel experiments for UNIONDP(MPDP) with max partition size 25, warmup query 0100aa.sql, and save the results in /scratch2/postgres/benchmarks/UNIONDP/<filename.txt>:"

`$ idp_type=UNIONDP idp_n_iters=25 ./run_all_generic.sh gpuqo_bicc_dpsub summary-full snowflake3 postgres 65 /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0100aa.sql /scratch2/rmancini/postgres/src/misc/snowflake2/queries/0030**.sql /scratch2/rmancini/postgres/src/misc/snowflake2/queries/1000**.sql | tee /scratch2/postgres/benchmarks_5/UNIONDP/0315_union15card.txt`

In general:  
`$ idp_type=HEUR_TYPE idp_n_iters=X ./run_all_generic.sh ALGORITHM SUMMARY-TYPE DATABASE USER TIMEOUT WARMUP_QUERY TARGET_QUERY`
- HEURISTIC_TYPE (only needed for heuristics) = IDP2, UNIONDP 
- X (only needed for heuristics) = integer usually 15 or 25 (max partition size)
- `ALGORITHM`: 
    - GEQO = `geqo`
    - MPDP(CPU) = 
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

I usually compile out-of-tree, both debug and release separately (just need to
call the configure script from a different folder, e.g. ../build-debug).

Then you can start it from the binary in the $prefix/bin folder, in my case it
would be ../opt/bin/postgres,you can also add it to your PATH.
I usually ran postgres as a single process (--single) instead of using the
daemon mode (it makes debugging easier).

