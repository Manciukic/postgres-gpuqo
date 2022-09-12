# Star Schema (1600 tables):  

Fact table cardinality : 1M  
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

