# Snowflake Schema (3555 tables - 5 level deep snowflake t_l1_l2_l3_l4_l5):   

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
