#!/usr/bin/env python3

from os import makedirs
import string
from tqdm import tqdm
from random import choice, randint, shuffle, seed

# This script generates pkfk queries for Musicbrainz

# CONFIGURATION

# max query size
M = 26

# number of queries per size
R = 15

# random seed
SEED = 0xdeadbeef

# CONSTANTS

# Database definition

G_musicbrainz = {
    'n': 56,
    'neig': [
         {2,7,9,14,24,26,30,37,47,18,19,20,21, 4, 6, 8}, #  0
         set(), #  1
         {0,7,9,14,24,26,30, 37,47, 10, 16}, #  2
         set(), #  3
         {0, 4, 6, 8}, #  4
         set(), #  5
         {0, 4, 6, 8}, #  6
         {0,2,9,14,24,26,30, 37,47}, #  7
         {0, 18, 19, 20, 21, 4, 6}, #  8
         {0,2,7,14,24,26,30, 37,47, 10, 16}, #  9
         {2, 9, 14, 16}, # 10
         set(), # 11
         set(), # 12
         set(), # 13
         {0,2,7,9,24,26,30, 37,47,  10, 16}, # 14
         set(), # 15
         {2, 9, 10, 14}, # 16
         set(), # 17
         {0, 8, 19, 20, 21}, # 18
         {0, 8, 18, 20, 21, 45}, # 19
         {0, 8, 18, 19, 21, 44}, # 20
         {0, 8, 18, 19, 20}, # 21
         set(), # 22
         set(), # 23
         {0,2,7,9,14,26,30, 37,47}, # 24
         set(), # 25
         {0,2,7,9,14,24,30, 37,47,27, 28, 29}, # 26
         {26, 28, 29}, # 27
         {26, 27, 29}, # 28
         {30, 34, 37, 26, 27, 28}, # 29
         {0,2,7,9,14,24,26, 37,47, 29, 34}, # 30
         set(), # 31
         set(), # 32
         set(), # 33
         {29, 30, 37}, # 34
         set(), # 35
         set(), # 36
         {0,2,7,9,14,24,26,30, 47, 29, 34}, # 37
         set(), # 38
         set(), # 39
         set(), # 40
         set(), # 41
         set(), # 42
         set(), # 43
         {20}, # 44
         {19}, # 45
         set(), # 46
         {0,2,7,9,14,24,26,30, 37, 49, 50}, # 47
         set(), # 48
         {47, 50}, # 49
         {47, 49}, # 50
         set(), # 51
         set(), # 52
         set(), # 53
         set(), # 54
         set(), # 55
         set() # 56
    ],
    'labels': [
        "artist_alias", #  0
        "artist_alias_type", #  1
        "artist", #  2
        "artist_type", #  3
        "artist_ipi", #  4
        "gender", #  5
        "artist_isni", #  6
        "area", #  7
        "artist_credit_name", #  8
        "area_alias", #  9
        "place", # 10
        "iso_3166_1", # 11
        "iso_3166_2", # 12
        "iso_3166_3", # 13
        "label", # 14
        "area_type", # 15
        "country_area", # 16
        "artist_credit", # 17
        "release_group", # 18
        "release", # 19
        "track", # 20
        "recording", # 21
        "area_alias_type", # 22
        "place_type", # 23
        "place_alias", # 24
        "label_type", # 25
        "label_alias", # 26
        "label_isni", # 27
        "label_ipi", # 28
        "release_label", # 29
        "release_country", # 30
        "release_group_secondary_type_join", # 31
        "release_group_primary_type", # 32
        "isrc", # 33
        "medium", # 34
        "place_alias_type", # 35
        "label_alias_type", # 36
        "release_unknown_country", # 37
        "language", # 38
        "script_language", # 39 - no longer exists
        "script", # 40
        "release_packaging", # 41
        "release_status", # 42
        "medium_format", # 43
        "medium_cdtoc", # 44
        "work", # 45
        "cdtoc", # 46
        "work_alias", # 47
        "work_type", # 48
        "iswc", # 49
        "work_attribute", # 50
        "work_alias_type", # 51
        "work_attribute_type_allowed_value", # 52
        "work_attribute_type", # 53
        "url", # 54
        "release_group_secondary_type", # 55
        "work_language" # 56
    ],
    'edge_attributes': [
        {2:('begin_date_year','begin_date_month'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month'), 8:('name','artist'),18:('name',), 19:('name',),20:('name',),21:('name',),  4:('artist',), 6:('artist',)}, #  0
        {}, #  1
        {0:('begin_date_year','begin_date_month'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month','area'),14:('begin_date_year','begin_date_month','area'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month'),10:('area',), 16:('area',)}, #  2
        {}, #  3
        {0:('artist',), 6:('artist',), 8:('artist',)}, #  4
        {}, #  5
        {0:('artist',), 4:('artist',), 8:('artist',)}, #  6
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month')}, #  7
        {0:('name','artist'),18:('name',), 19:('name',),20:('name',),21:('name',),  4:('artist',), 6:('artist',)}, #  8
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month','area'),7:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month','area'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month'),10:('area',), 16:('area',)}, #  9
        {2:('area',), 9:('area',), 14:('area',), 16:('area',)}, # 10
        {}, # 11
        {}, # 12
        {}, # 13
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month','area'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month','area'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month'),10:('area',), 16:('area',)}, # 14
        {}, # 15
        {2:('area',), 9:('area',), 10:('area',), 14:('area',)}, # 16
        {}, # 17
        {0:('name',),8:('name',),19:('name',),20:('name',),21:('name',)}, # 18
        {0:('name',),8:('name',),18:('name',), 20:('name',),21:('name',)}, # 19
        {0:('name',),8:('name',),18:('name',), 19:('name',),21:('name',), 44:('medium',)}, # 20
        {0:('name',),8:('name',),18:('name',), 19:('name',),20:('name',)}, # 21
        {}, # 22
        {}, # 23
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month')}, # 24
        {}, # 25
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month'),24:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'),47:('begin_date_year','begin_date_month'), 27:('label',), 28:('label',), 29:('label',)}, # 26
        {26:('label',), 28:('label',), 29:('label',)}, # 27
        {26:('label',), 27:('label',), 29:('label',)}, # 28
        { 30:('release',), 34:('release',), 37:('release',),26:('label',), 27:('label',), 28:('label',)}, # 29
        {0:('date_year','date_month'),2:('date_year','date_month'),7:('date_year','date_month'),9:('date_year','date_month'),14:('date_year','date_month'),24:('date_year','date_month'),26:('date_year','date_month'),37:('date_year','date_month','release'),47:('date_year','date_month'), 29:('release',), 34:('release',)}, # 30
        {}, # 31
        {}, # 32
        {}, # 33
        {29:('release',), 30:('release',), 37:('release',)}, # 34
        {}, # 35
        {}, # 36
        {0:('date_year','date_month'),2:('date_year','date_month'),7:('date_year','date_month'),9:('date_year','date_month'),14:('date_year','date_month'),24:('date_year','date_month'),26:('date_year','date_month'),30:('date_year','date_month','release'),47:('date_year','date_month'), 29:('release',), 34:('release',)}, # 37
        {}, # 38
        {}, # 39
        {}, # 40
        {}, # 41
        {}, # 42
        {}, # 43
        {20:('medium',)}, # 44
        {}, # 45
        {}, # 46
        {0:('begin_date_year','begin_date_month'),2:('begin_date_year','begin_date_month'),7:('begin_date_year','begin_date_month'),9:('begin_date_year','begin_date_month'),14:('begin_date_year','begin_date_month'),24:('begin_date_year','begin_date_month'),26:('begin_date_year','begin_date_month'),30:('begin_date_year','begin_date_month'),37:('begin_date_year','begin_date_month'), 49:('work',), 50:('work',)}, # 47
        {}, # 48
        {47:('work',), 50:('work',)}, # 49
        {47:('work',), 49:('work',)}, # 50
        {}, # 51
        {}, # 52
        {}, # 53
        {}, # 54
        {}, # 55
        {}, # 56
    ],
    "ignore_relations": ["script_language"]
}

# FUNCTIONS

def neighbours(G, S):
    neigs = set()
    for node in S:
        neigs |= G['neig'][node]
    neigs -= S
    return neigs

def test_database(G):
    for i, attrs in enumerate(G['edge_attributes']):
        for j in attrs.keys():
            try:
                assert(i in G['edge_attributes'][j])
            except:
                print(i,j)
                raise
    print("Databse description is OK")

def gen_random_query(G, N):
    neigs = set(range(G['n']))
    queryset = set()
    from_clauses = []
    where_clauses = []

    G_out = {'n': N, 'neig': [set() for i in range(N)]}
    remapping = {}

    n = 0
    while len(queryset) < N:
        if not neigs:
            break

        node = choice(tuple(neigs))
        remapping[node] = n

        if queryset:
            peers = [n for n in queryset if n in G['edge_attributes'][node].keys()]
            shuffle(peers)
            if len(peers) == 0:
                break
            for i in range(randint(1,len(peers))):
                peer = peers[i]
                edge = G['edge_attributes'][peer][node]

                for curEdge in range (len(edge)):
                    where_clauses.append(f"\"{G['labels'][peer]}\".\"{G['edge_attributes'][peer][node][curEdge]}\" = \"{G['labels'][node]}\".\"{G['edge_attributes'][node][peer][curEdge]}\"")
                G_out['neig'][remapping[node]].add(remapping[peer])
                G_out['neig'][remapping[peer]].add(remapping[node])

        queryset.add(node)
        from_clauses.append(G['labels'][node])
        neigs = neighbours(G, queryset)

        n += 1

    if len(queryset) < N:
        # print(f"No more neighbors at size {len(queryset)}, retrying")
        return gen_random_query(G, N)
    else:
        from_clause = '", "'.join(from_clauses)
        where_clause = ' AND '.join(where_clauses)
        return G_out, f"SELECT * FROM \"{from_clause}\" WHERE {where_clause};"

# EXECUTION

if __name__ == "__main__":
    seed(SEED)

    test_database(G_musicbrainz)

    labels = [f"{a}{b}" for a in string.ascii_lowercase for b in string.ascii_lowercase]
    combinations = [(n, i) for n in range(2,M+1) for i in range(R) ]

    makedirs("queries", exist_ok=True)
    for n, i in tqdm(combinations):
        G, query = gen_random_query(G_musicbrainz, n)
        with open(f"queries/{n:02d}{labels[i]}.sql", 'w') as f:
            f.write(query)
            f.write("\n")
