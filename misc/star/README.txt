Star Schema (1600 tables):   

Fact table cardinality : 1M     
Dimension table cardinality : random between (10k, 1M)
Queries: The queries have predicates with random selectivity between (20%, 80%)
---------------------------------------------------------------------------------

Option 1:
If you have the star.dudmp which was created with a custom-format dump file:
$ pg_dump -Fc star > star.dump

To  recreate it from the dump: 
$ createdb your_db_name
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name star.dump

Option 2:
Alternatively, to generate the star database (assuming your_db_name='star'):

Step 1: The star.py script will created needed .sql scripts and /queries_with_pred folder
(Make sure you're running Postgres)
Step 2: $ psql -f create_tables.sql star
Step 3: $ psql -f fill_tables.sql star
	if Step 3 fails due to memory issue you need to break up the insert statement:
	Step 3.1: $ python3 break_up_and_insert.py
Step 4: $ psql -f add_foreign_keys.sql star