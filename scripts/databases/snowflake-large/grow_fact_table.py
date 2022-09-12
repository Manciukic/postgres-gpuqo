from tqdm import tqdm
import subprocess

# change these params
fact_table_cardinality = 1_000_000
times_to_grow_table = 9
db_name = 'snowflake-large'


ALTER_PATTERN = f"""
CREATE SEQUENCE snowflake_new_pk_seq MINVALUE {fact_table_cardinality};
ALTER TABLE T_1 ALTER pk SET DEFAULT nextval('snowflake_new_pk_seq');
ALTER SEQUENCE snowflake_new_pk_seq OWNED BY T_1.pk;
"""


lines = []
with open(f"fill_tables.sql", 'r') as f:
    data = f.read()

d = ";"
inserts =  [e+d for e in data.split(d) if e]
# fact table
fact_insert = inserts[0].split("\n")
fact_insert_into = "\n".join(fact_insert[:3])
values = fact_insert[3:]

temp = fact_insert_into.replace("pk,\n", "").split("VALUES")[0].strip('\n')
table_names = temp.split('(')[1].split(')')[0].strip('\n')

# TODO: the alter etc. need to happen once 
with open(f"INSERT_INTO_FACT.sql", "w") as f:
    f.write(temp)
    f.write("SELECT")
    f.write(str(table_names)+"\n")
    f.write("FROM T_1\n")
    f.write(f"LIMIT {fact_table_cardinality};")

with open(f"ALTER_SERIAL.sql", "w") as f:
    f.write(ALTER_PATTERN)

# this needs to happen only once
subprocess.run(
        f"psql -f ALTER_SERIAL.sql {db_name}",
        shell=True,
    )

# grow fact table


print("Growing Fact table...")
for i in tqdm(range(times_to_grow_table)):
    subprocess.run(
        f"psql -f INSERT_INTO_FACT.sql {db_name}",
        shell=True,
    )
