from random import randint, sample
from random_tree import make_tree_query
import string
import os
from tqdm import tqdm

def make_query(N, n):
    # qs chooses n number of neighbours from N total tables
    qs = sample(list(range(1,N)), n)
    from_clause = ", ".join(["T%d" % j for j in qs])
    #todo: look into if joins should change, seems very deterministic no?
    where_clause = " AND ".join([f"T{i}.t{j} = T{j}.t{i}" for i in qs for j in qs if i < j])
    return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {n}"


def make_query_skip_some(N, n):
    # qs chooses n number of neighbours from N total tables
    skip = (110,97,89,56,31,45,28,25,20,19,18,12,10,7,5,3,2)
    qs = sample(list(range(1,N)), n)
    from_clause = ", ".join(["T%d" % j for j in qs])
    #todo: look into if joins should change, seems very deterministic no?
    where_clause = " AND ".join([f"T{i}.t{j} = T{j}.t{i}" for i in qs for j in qs if i < j and (i not in skip) and (j not in skip)])
    return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {n}"


if __name__ == "__main__":
    labels = [f"{a}{b}" for a in string.ascii_lowercase for b in string.ascii_lowercase]

    N = 50

    try:
        os.mkdir("queries_for_50")
    except FileExistsError:
        # directory already exists
        pass

    
    # 2 to 10 step 1
    for n in tqdm(range(10,50,5)):
        for i in range(104):
            with open(f"queries_for_50/{n:04d}{labels[i]}.sql", 'w') as f:
                f.write(make_query(N, n))
                f.write("\n")

    try:
        os.mkdir("queries_3")
    except FileExistsError:
        # directory already exists
        pass

    N = 200
    # 2 to 10 step 1
    for n in tqdm(range(10,200,10)):
        for i in range(104):
            with open(f"queries_3/{n:04d}{labels[i]}.sql", 'w') as f:
                f.write(make_query_skip_some(N, n))
                f.write("\n")