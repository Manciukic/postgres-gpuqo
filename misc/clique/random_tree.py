from random import choices, choice, sample

def pruefer_sequence_to_edges(a):
    n = len(a)
    T = list(range(1, n+3))
    degrees = [1 for _ in range(n+3)]
    degrees[0] = 0
    edges = []

    for i in a:
        degrees[i] += 1
    
    for i in a:
        for j in T:
            if degrees[j] == 1:
                edges.append((i,j))
                degrees[i] -= 1
                degrees[j] -= 1
                break
    
    u = 0
    v = 0
    for i in T:
        if degrees[i] == 1:
            degrees[i] -= 1
            if u == 0:
                u = i
            else:
                v = i
                break
    edges.append((u,v))
    
    assert(all(d == 0 for d in degrees))

    return edges


def make_tree_query(N, n):
    qs = sample(list(range(1,N+1)), n)
    from_clause = ", ".join(["T%d" % j for j in qs])
    edges = pruefer_sequence_to_edges(choices(list(range(1,n+1)), k=n-2))
    real_edges = [choice([(qs[i-1], qs[j-1]), (qs[j-1], qs[i-1])]) for i, j in edges]
    where_clause = " AND ".join([f"T{i}.t{j} = T{j}.t{i}" for i, j in real_edges])
    return f"SELECT * FROM {from_clause} WHERE {where_clause}; -- {n}"

