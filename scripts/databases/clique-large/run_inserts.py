from tqdm import tqdm
import os
import subprocess

num_tables = 200
db_name = 'clique-large'

if __name__ == "__main__":
    for i in tqdm(range(1,num_tables+1)):
        subprocess.run(
            f"psql -f inserts/insert_T_{i}.sql {db_name}",
            shell=True,
        )