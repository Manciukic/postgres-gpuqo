from tqdm import tqdm
import os
import subprocess


if __name__ == "__main__":
    num_dimension_tables = 200
    for i in tqdm(range(1,num_dimension_tables+1)):
        subprocess.run(
            f"psql -f inserts/insert_T_{i}.sql clique",
            shell=True,
        )