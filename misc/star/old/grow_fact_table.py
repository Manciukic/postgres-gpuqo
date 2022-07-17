from tqdm import tqdm
import os
import subprocess

if __name__ == "__main__":
    print("Growing Fact table...")
    for i in tqdm(range(450)): # Insert 9M rows in 20k chunks = 450 times
        subprocess.run(
            f"psql -f INSERT_INTO_FACT.sql star3",
            shell=True,
        )
