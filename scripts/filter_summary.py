#!/bin/env python3

from sys import stdin
import re

gpuqo_cost = ''
gpuqo_time = ''
plan_time = ''
postgres_cost = ''

for line in stdin:
    if 'gpuqo_run took' in line:
        gpuqo_time = line.split()[2]
    elif 'gpuqo cost is' in line:
        gpuqo_cost = line.split()[3]
    elif 'Planning Time:' in line:
        plan_time = line.split()[2]
    elif re.match('^[A-Z].*cost.*$', line):
        res = re.search('(?<=\.\.)[0-9\.]+', line)
        postgres_cost = res.group(0)

print('gpuqo_cost', gpuqo_cost, sep='\t')
print('gpuqo_time', gpuqo_time, sep='\t')
print('plan_time', plan_time, sep='\t')
print('postgres_cost', postgres_cost, sep='\t')
