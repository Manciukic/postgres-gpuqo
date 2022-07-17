from tqdm import tqdm
import os
import subprocess


if __name__ == "__main__":
    # STAR
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
    
    # Break up inserts for FACT table
    offset = 50_000 # maximum cardinality per insert (adjustable but make sure every param is correct)
    iters = (1_000_000) // offset # start and end done alone thats why -2

    print("Breaking up INSERT INTO statements...")
    for i in tqdm(range(iters)):
        with open(f"./inserts/insert_0_{i}.sql", 'w') as f:
            temp = fact_insert_into + "\n" + str("".join(values[offset*i:offset*(i+1)])).rstrip(",")  + ";"
            f.write(temp)
        
    # Break up inserts for DIMENSION tables
    for i in tqdm(range(1, len(inserts))):
        with open(f"./inserts/insert_{i}.sql", 'w') as f:
            f.write(inserts[i])
    
    print("Running up INSERT INTO statements...")
    # Populate FACT table with the new insert scripts
    for i in tqdm(range(iters)):
        subprocess.run(
            f"psql -f inserts/insert_0_{i}.sql star", # assuming 'star' is the name of the db you use
            shell=True,
        )
    # Populate DIMENSION table with the new insert scripts
    num_dimension_tables = 1600 # change this to correct
    for i in tqdm(range(1,num_dimension_tables)):
        subprocess.run(
            f"psql -f inserts/insert_{i}.sql star",
            shell=True,
        )