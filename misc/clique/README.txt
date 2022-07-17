Clique Schema (200 tables):   

Table cardinalities : Depends on your clique. The clique.dump one has random card between (0, 650k)
Queries: The queries are not just PK-FK joins
--------------------------------------------------------------------------------------

Option 1:
If you have the clique.dump which was created with a custom-format dump file:
$ pg_dump -Fc clique > clique.dump

To  recreate it from the dump: 
$ createdb your_db_name
$ pg_restore -C --no-privileges --no-owner --role=your_user --verbose --clean -d your_db_name clique.dump

Option 2:
Alternatively, to generate the clique database (assuming your_db_name='clique'):

Step 1: The clique.py script will create the .sql scipts; the /inserts folder; the /queries folder.
(Make sure you're running Postgres)
Step 2: $ psql -f create_tables.sql clique
Step 3: $ python3 run_inserts.py 
Step 4: $ psql -f add_foreign_keys.sql clique