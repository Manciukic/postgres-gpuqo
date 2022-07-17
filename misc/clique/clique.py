from random import randint, sample
from random_tree import make_tree_query
import string
import os
from tqdm import tqdm

TABLE_PATTERN="""CREATE TABLE T%d (
    pk INT PRIMARY KEY,
%s
);
"""

FK_PATTERN="""ALTER TABLE T%d
ADD FOREIGN KEY (t%d) REFERENCES T%d(pk);
"""

def make_create_tables(n):
    out = ""
    for i in range(1,n+1):
        columns = ",\n".join(["t%d INT" % j for j in range(1,n+1) if i != j])
        out += TABLE_PATTERN % (i,columns)
    return out

def make_foreign_keys(n):
    out = ""
    for i in range(1,n+1):
        for j in range(1,n+1):
            if i != j:
                out += FK_PATTERN % (i,j,j)
    return out

def make_insert_into(n, size=10000):
    # we need to know cardinality for each table 
    # 1. Decide cardinalities of each table
    card = {} # "table":int(cardinality)
    colrng = {}
    for i in range(1,n+1):
        card[f"T{i}"] = randint(1_000, 100_000) # min_size=10_000, max_size=1_000_000
        # card[f"T{i}"] = randint(100, 10_000) # 10 to 10k random rows
        print(f"T{i} : ", card[f"T{i}"])
    for i in range(1,n+1):
        for j in range(i+1,n+1):
            # card[f"T{i}"] = randint(10_000, 1_000_000) # min_size=10_000, max_size=1_000_000
            colrng[f"T{i}T{j}"] = randint(2_000, 200_000)
            colrng[f"T{j}T{i}"] = colrng[f"T{i}T{j}"]
            
    # 2. Populate tables and make sure foreign key constraint is kept based on above cardinalities
    for i in tqdm(range(1,n+1)):
        out = ""
        values = []
        columns = ', '.join([f"t{j}" for j in range(1,n+1) if i != j])
        out += f"INSERT INTO T{i} (pk, {columns})\nVALUES\n"
        # for each row based on this table's cardinality
        # print("here: ", i, card[f"T{i}"])
        for row in range(card[f"T{i}"]):
            temp = []
            for col in range(1,n+1):
                if i != col:
                    h = colrng[f"T{i}T{col}"]
                    # temp.append(str(randint(0,card[f"T{col}"]-1)))
                    temp.append(str(randint(0,h))) 
                    # temp.append(str(randint(0,100))) # random number between 0 and 100
            values.append(f"    ({row}, {', '.join(temp)})")
        # print(row)
        # values.append(f"    ({j}, {', '.join([str(randint(0,card[f"T{t}"]-1)) for t in range(1,n+1) if j != t])})")
        # values = [f"    ({j}, {', '.join([str(randint(0,size-1)) for _ in range(1,n)])})" for j in range(size)]
        out += ",\n".join(values)
        out += ";\n\n"
        with open(f"inserts/insert_T_{i}.sql", 'w') as f:
            f.write(out)
            f.write('\n')

    return out

def make_query(N, n):
    # qs chooses n number of neighbours from N total tables
    qs = sample(list(range(1,N+1)), n)
    from_clause = ", ".join(["T%d" % j for j in qs])
    #todo: look into if joins should change, seems very deterministic no?
    where_clause = " AND ".join([f"T{i}.t{j} = T{j}.t{i}" for i in qs for j in qs if i < j])
    return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {n}"


if __name__ == "__main__":
    labels = [f"{a}{b}" for a in string.ascii_lowercase for b in string.ascii_lowercase]

    # number of relations
    N = 200

    with open("create_tables.sql", 'w') as f:
        f.write(make_create_tables(N))
        f.write('\n')

    with open("add_foreign_keys.sql", 'w') as f:
        f.write(make_foreign_keys(N))
        f.write('\n')

    # print("Make Inserts...")
    try:
        os.mkdir("inserts")
    except FileExistsError:
        # directory already exists
        pass

    make_insert_into(N)

    try:
        os.mkdir("queries")
    except FileExistsError:
        # directory already exists
        pass
    
    for i in range(104):
        with open(f"queries/{200:04d}{labels[i]}.sql", 'w') as f:
            f.write(make_query(N, 200))
            f.write("\n")