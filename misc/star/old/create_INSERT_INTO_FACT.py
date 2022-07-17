with open(f"./inserts/insert_0_1.sql", 'r') as f:
    data = f.read()

d = ";"
inserts =  [e+d for e in data.split(d) if e]
# fact table
fact_insert = inserts[0].split("\n")
fact_insert_into = "\n".join(fact_insert[:3])
values = fact_insert[3:]

temp = fact_insert_into
with open(f"INSERT_INTO_FACT.sql", "w") as f:
    f.write(temp)