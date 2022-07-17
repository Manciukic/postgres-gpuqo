Snowflake Schema (1000 tables - 4 level deep snowflake t_l1_l2_l3_l4):   

Fact table cardinality : 10M     
Dimension table cardinality : random between (10k, 1M)   
Queries: Up to 1000 relations, but you can generate more with scripts provided
---------------------------------------------------------------------------------

Option 1:
If you have the snowflake.dump which was created with a custom-format dump file:
$ pg_dump -Fc snowflake > snowflake.dump

To  recreate it from the dump: 
$ createdb your_db_name
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name snowflake.dump

Option 2:
Alternatively, to generate the snowflake database (assuming your_db_name='snowflake'):

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