#!/usr/bin/env python3

from random import randint, seed
from os import makedirs
import string

# CONFIGURATION

# number of tables (including fact table)
N = 40

# random seed
SEED = 0xdeadbeef

# CONSTANTS

TABLE_PATTERN="""CREATE TABLE T%d (
    pk INT PRIMARY KEY,
    n INT
);
"""

LAST_TABLE_PATTERN="""CREATE TABLE T%d (
    pk INT PRIMARY KEY
);
"""

FK_PATTERN="""ALTER TABLE T%d
ADD FOREIGN KEY (n) REFERENCES T%d(pk);
"""

# FUNCTIONS

def make_create_tables(n):
    out = ""
    for i in range(1,n):
        out += TABLE_PATTERN % i
    out += LAST_TABLE_PATTERN % n
    return out

def make_foreign_keys(n):
    out = ""
    for i in range(1,n):
        out += FK_PATTERN % (i,i+1)
    return out

def make_insert_into(n, size=10000):
    out = ""
    out += f"INSERT INTO T{n} (pk)\nVALUES\n"
    values = [f"    ({j})" for j in range(size)]
    out += ",\n".join(values)
    out += ";\n\n"
    for i in range(n-1,0,-1):
        out += f"INSERT INTO T{i} (pk, n)\nVALUES\n"
        values = [f"    ({j}, {randint(0,size-1)})" for j in range(size)]
        out += ",\n".join(values)
        out += ";\n\n"
    return out

def make_query(n, i=0):
    from_clause = ", ".join(["T%d" % j for j in range(i+1, i+1+n)])
    where_clause = " AND ".join(["T%d.n = T%d.pk" % (j,j+1) for j in range(i+1, i+n)])
    return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {n}"

# EXECUTION

seed(SEED)
labels = [f"{a}{b}" for a in string.ascii_lowercase for b in string.ascii_lowercase]

with open("create_tables.sql", 'w') as f:
    f.write(make_create_tables(N))
    f.write('\n')

with open("add_foreign_keys.sql", 'w') as f:
    f.write(make_foreign_keys(N))
    f.write('\n')

with open("fill_tables.sql", 'w') as f:
    f.write(make_insert_into(N))
    f.write('\n')

makedirs("queries", exist_ok=True)
for n in range(2,N):
    for i in range(N-n):
        with open(f"queries/{n:02d}{labels[i]}.sql", 'w') as f:
            f.write(make_query(n,i))
            f.write("\n")
