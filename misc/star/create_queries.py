
import string
import os
from random import randint, sample, choice
import numpy as np
from tqdm import tqdm


class SnowflakeSchema:
    def __init__(self, n_dims, n_leaves):
        self.n_dims = n_dims
        self.n_leaves = n_leaves

    def make_query(self, query_size):
        qs = [] # set of relations

        neigs = [(1,)]
        while neigs and len(qs) < query_size:
            id = choice(neigs)
            neigs.remove(id)

            leaf = id[-1] <= self.n_leaves[len(id)-1] 
            if not leaf:
                neigs += [(*id, i) for i in range(1, self.n_dims[len(id)]+1)]
            qs.append(id)
        
        # here I have all tables in qs; from qs I generate from clause
        from_clause = ", ".join(map(lambda id: f"T_{id_to_str(id)}", qs))
        where_clauses = []
        for t in qs:
            if len(t) == 1:
                continue
            # T {0} is the parent
            where_clauses.append("T_{0}.t_{1} = T_{1}.pk".format(
                                id_to_str(t[:-1]), id_to_str(t)))
            # Tables have a predicate, with randint from 20 to 80% selective
            sel = randint(20,80)
            rows = card[f"t_{id_to_str(t)}"]
            fk = int(np.percentile(np.array(range(rows)), sel))
            # print(f"{rows}\t[{sel}\tt_{id_to_str(t)}")
            # print(f"{t} {sel} {rows} T_{id_to_str(t)}.pk > {fk}")
            # random choice 250 tables?
            where_clauses.append(f"T_{id_to_str(t)}.pk > {fk}") # fk_random is some random selectivity

        where_clause = " AND ".join(where_clauses)
        return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {query_size}"


def id_to_str(id):
    return '_'.join(map(str, id))

card = {}
def readCardinalities():
    global card
    with open(f"cardinalities.txt", 'r') as f:
        for l in f.readlines():
            # print(l)
            # print(" NEXT ")
            temp = [x.strip() for i,x in enumerate(l.split("|")) if i in (0,2)]
            for table_name, cardinality  in zip(temp, temp[1:]):
                if cardinality != "reltuples":
                    card[table_name] = int(cardinality)
    return 

if __name__ == "__main__":
    # to create cardinalities file run :
    # query_cardinalities.sql 
        # SELECT relname, relkind, reltuples, relpages
        # FROM pg_class
        # WHERE relname LIKE 't\_%' AND relkind = 'r';
    # with $psql star3 > ./cardinalities.txt < ./query_cardinalities.sql 
    readCardinalities() #  create cardinality .txt file
    # for k,v in card.items():
    #     if v == 0:
    #         print(k,v)

    schema = SnowflakeSchema((1, 1599, 0),
                             (0, 1599, 0))

    labels = [f"{a}{b}" for a in string.ascii_lowercase for b in string.ascii_lowercase]
    try:
        os.mkdir("queries_with_pred")
    except FileExistsError:
        # directory already exists
        pass
    

    # 10 to 100 step of 10
    for n in tqdm(range(1,9)):
        for i in range(104): # 104 because multiple of the 26 letter in alphabet (letters to name the queries)
            with open(f"queries_with_pred/{n:04d}{labels[i]}.sql", 'w') as f:
                f.write(schema.make_query(n))
                f.write("\n")

    # # create queries 
    # # 10 to 100 step of 10
    # for n in tqdm(range(10,101,10)):
    #     for i in range(104): # 104 because multiple of 26 (letters to name the queries)
    #         with open(f"queries_with_pred/{n:04d}{labels[i]}.sql", 'w') as f:
    #             f.write(schema.make_query(n))
    #             f.write("\n")

    # # 100 to 1000 step of 100
    # for n in tqdm(range(100,1001,100)):
    #     for i in range(104):
    #         with open(f"queries_with_pred/{n:04d}{labels[i]}.sql", 'w') as f:
    #             f.write(schema.make_query(n))
    #             f.write("\n")