# Clique Schema (200 tables):   

Table cardinalities : Depends on your clique. Ours had random card between (0, 650k)  
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

