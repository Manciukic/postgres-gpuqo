from tqdm import tqdm
import os
import random

if __name__ == "__main__":
    for i in tqdm(range(1,321)): # 320 = 20% of 1.6k tables
        with open(f"./inserts/insert_{i}.sql", 'r+') as f:
            lines = f.readlines()
            num = random.randrange(10,min(10000, len(lines)-1))
            temp = lines[:num]
            temp[-1] = temp[-1].rstrip(",\n") + ";"
            # delete content of file
            f.seek(0)
            f.truncate()
            # write new content
            f.write("".join(temp))
            print(f"t_1_{i} from: {len(lines)} to : {len(temp)}")