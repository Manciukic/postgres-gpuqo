from tqdm import tqdm
import os
import subprocess

# change these according to your star dataset parameters:
num_dimension_tables = 1599 
fact_table_cardinality = 1_000_000 
max_card_per_insert = 50_000 
db_name = 'star-large'

if __name__ == "__main__":
    print("Reading fill_tables.sql...")
    with open("fill_tables.sql", 'r') as f:
        data = f.read()

    d = ";"
    inserts =  [e+d for e in data.split(d) if e]
    # fact table
    fact_insert = inserts[0].split("\n")
    fact_insert_into = "\n".join(fact_insert[:3])
    values = fact_insert[3:]


    if not os.path.exists(".inserts"):
        print("Creating /inserts directory...")
        os.makedirs("./inserts")
    
    # Break up inserts for FACT table ( assumming 1M rows fact table)
    iters = (fact_table_cardinality) // max_card_per_insert # start and end done alone thats why -2
    print("Breaking up INSERT INTO statements...")
    for i in tqdm(range(iters)):
        with open(f"./inserts/insert_0_{i}.sql", 'w') as f:
            temp = fact_insert_into + "\n" + str("".join(values[max_card_per_insert*i:max_card_per_insert*(i+1)])).rstrip(",")  + ";"
            f.write(temp)
        
    # Break up inserts for DIMENSION tables
    for i in tqdm(range(1, len(inserts))):
        with open(f"./inserts/insert_{i}.sql", 'w') as f:
            f.write(inserts[i])
    
    print("Running up INSERT INTO statements...")
    # Populate FACT table with the new insert scripts
    for i in tqdm(range(iters)):
        subprocess.run(
            f"psql -f inserts/insert_0_{i}.sql {db_name}", 
            shell=True,
        )
    # Populate DIMENSION table with the new insert scripts
    for i in tqdm(range(1,num_dimension_tables+1)):
        subprocess.run(
            f"psql -f inserts/insert_{i}.sql {db_name}",
            shell=True,
        )