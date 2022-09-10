#!/bin/env python3

import argparse
import os
import csv
import numpy as np
import matplotlib.pyplot as plt
from numpy.polynomial import Chebyshev as T
from scipy.stats.mstats import gmean
from itertools import cycle, chain

def format_func(value, tick_number):
    if value >= 1:
        if abs(round(value) - value) < 1e-10:
            return "%d" % round(value)
        else:
            return "%.2f" % value
    else:
        if value < 1e-10:
            return "0"
        elif abs(round(1/value) - 1/value) < 1e-10:
            return "1/%d" % (round(1/value))
        else:
            return "1/%.2f" % (1/value)


def folder2series(folder, depth=1):
    return '/'.join(folder.split('/')[-depth:])

def ratio(v, ref):
    return v/ref

def count_tables(query):
    return len(query[query.find("FROM"):query.find("WHERE")].split(','))

def read_query(filename):
    with open(filename) as f:
        lines = f.readlines()
        s = ' '.join(l.strip() for l in lines)
        return s

def load_results(folder, timeout=np.nan):
    queries = {}
    for filename in os.listdir(folder):
        with open(os.path.join(folder, filename), 'r') as f:
            query = None
            plan_time = 0
            exec_time = 0
            gpuqo_time = 0
            gpuqo_warmup_time = 0
            for line in chain(f.readlines(), ['end.sql']):
                if 'sql' in line:
                    if query:
                        if not (plan_time or exec_time or gpuqo_time):
                            plan_time = timeout
                            exec_time = timeout
                            gpuqo_time = timeout

                        # save if there was a query previously
                        # create dict item if missing
                        if query not in queries:
                            queries[query] = {
                                'plan_time_raw': [],
                                'exec_time_raw': [],
                                'total_time_raw': [],
                                'gpuqo_time_raw': [],
                            }

                        # fill dict item
                        queries[query]['plan_time_raw'].append(plan_time)
                        queries[query]['exec_time_raw'].append(exec_time)
                        queries[query]['total_time_raw'].append(plan_time + exec_time)
                        queries[query]['gpuqo_time_raw'].append(gpuqo_time)

                        # reset values
                        plan_time = 0
                        exec_time = 0
                        gpuqo_time = 0
                        gpuqo_warmup_time = 0
                    query = line[:-5].split('/')[-1]
                elif 'Planning' in line:
                    plan_time = float(line.split(':')[1][:-3])
                elif 'plan_time' in line:
                    if len(line.split()) > 1:
                        plan_time = float(line.split()[1])
                elif 'Execution' in line:
                    exec_time = float(line.split(':')[1][:-3])
                elif 'gpuqo' in line and 'took' in line:
                    if 'ms' in line.split():
                        t = float(line.split()[-2])
                    else:
                        t = float(line.split()[-1][:-2])
                    if gpuqo_warmup_time == 0:
                        gpuqo_warmup_time = t
                    else:
                        gpuqo_time = t
                # else:
                #     print(f"Unexpected line: {line.strip()}")

    for query, d in queries.items():
        for metric in ['plan', 'exec', 'total', 'gpuqo']:
            d[f"{metric}_time_avg"] = np.mean(d[f"{metric}_time_raw"])
            d[f"{metric}_time_std"] = np.std(d[f"{metric}_time_raw"])
            d[f"{metric}_time_count"] = len(d[f"{metric}_time_raw"])

    return queries

def add_table_count(queries, sql_folder):
    remove_keys = set()
    for query, d in queries.items():
        path = (os.path.join(sql_folder, os.path.basename(query + '.sql'))
                    if sql_folder else query + '.sql')
        try:
            d['tables'] = count_tables(read_query(path))
        except FileNotFoundError:
            s = query.split('/')[-1][:-2]
            if s.isdigit():
                d['tables'] = int(s)
            else:
                print("%s not found" % path)
                remove_keys.add(query)

    for k in remove_keys:
        del queries[k]

    return queries

def remove_incomplete_runs(queries):
    remove_tables = set()
    for _query, d in queries.items():
        if any(np.isnan(d[f"{metric}_time_avg"])
                for metric in ['plan', 'exec', 'total', 'gpuqo']):
            remove_tables.add(d['tables'])

    remove_keys = set()
    for query, d in queries.items():
        if d["tables"] in remove_tables:
            remove_keys.add(query)

    for key in remove_keys:
        del queries[key]

def load_results_complete(result_folder, sql_folder):
    queries = load_results(result_folder)
    add_table_count(queries, sql_folder)
    remove_incomplete_runs(queries)
    return queries

def scatter_plot_count_time(queries, metric="plan", label=None, ratio=False, color=None, marker="o", shift=0, marker_size=100):
    keys = sorted(list(queries.keys()))
    x = np.array([queries[k]['tables'] for k in keys]) + shift
    if ratio:
        y = [queries[k][f'{metric}_time_ratio'] for k in keys]
    else:
        y = [queries[k][f'{metric}_time_avg'] for k in keys]
        yerr = [queries[k][f'{metric}_time_std'] for k in keys]
        plt.errorbar(x, y, yerr=yerr, linestyle="None", color=color)

    plt.scatter(x, y, label=label, color=color, marker=marker, s=marker_size)

def line_plot_count_time(queries, metric="plan", label=None, ratio=False, color=None, errorbar=False):
    keys = sorted(list(queries.keys()))
    x = np.array([queries[k]['tables'] for k in keys])
    x_line = []
    y_line = []
    y_err = []

    if ratio:
        y = np.array([queries[k][f'{metric}_time_ratio'] for k in keys])

        for n in np.sort(np.unique(x)):
            mask = (x == n) & (y > 0)
            if np.any(mask):
                x_line.append(n)
                y_line.append(gmean(y[mask]))
                y_err.append([np.min(y[mask]), np.max(y[mask])])
    else:
        y = np.array([queries[k][f'{metric}_time_avg'] for k in keys])

        for n in np.sort(np.unique(x)):
            mask = (x == n) & (y > 0)
            if np.any(mask):
                x_line.append(n)
                y_line.append(np.average(y[mask]))
                y_err.append([np.min(y[mask]), np.max(y[mask])])

    if errorbar:
        plt.errorbar(x_line, y_line, yerr=np.array(y_err).T, label=label, color=color)
    else:
        plt.plot(x_line, y_line, label=label, color=color)

def generic_plot(series, line=False, scatter=True, metric="plan", ratio_baseline=None, max_shift=0, minor_ticks=[], error_bar = False):
    markers = cycle(['+','x','1','2','3','4',])
    shifts = np.linspace(-max_shift, max_shift, len(series))
    for i, (s, queries) in enumerate(series.items()):
        if scatter:
            scatter_plot_count_time(
                queries,
                metric=args.metric,
                label=s if not line else None,
                ratio=ratio_baseline is not None,
                color=f"C{i if not ratio_baseline else i+1}",
                marker=next(markers),
                shift=shifts[i],
                marker_size=10 if line else 40
            )
        if line:
            line_plot_count_time(
                queries,
                metric=args.metric,
                label=s,
                ratio=ratio_baseline is not None,
                color=f"C{i if not ratio_baseline else i+1}",
                errorbar=(error_bar and not scatter)
            )

    # configure matplotlib
    if ratio_baseline:
        plt.ylabel("Time ratio (lower is better)")
        plt.yscale("log")
        vals = np.array(minor_ticks)
        ticks = []
        ticks += (1/vals[::-1]).tolist()
        ticks += vals.tolist()
        plt.gca().yaxis.set_minor_locator(plt.FixedLocator(ticks))
        plt.gca().yaxis.set_minor_formatter(plt.FuncFormatter(format_func))
        plt.gca().yaxis.set_major_formatter(plt.FuncFormatter(format_func))
        plt.axhline(1, label=ratio_baseline)
    else:
        plt.ylabel("Time (ms)")
        plt.yscale("log")

    plt.legend()
    plt.grid(which="major")
    plt.grid(which="minor", linestyle="--")
    plt.xlabel("Number of tables")


def scatter_plot(*args, **kwargs):
    return generic_plot(*args, **kwargs, line=False, scatter=True)

def line_plot(*args, **kwargs):
    return generic_plot(*args, **kwargs, line=True, scatter=False)

def scatter_line_plot(*args, **kwargs):
    return generic_plot(*args, **kwargs, line=True, scatter=True)

def bar_plot(series, metric="plan", ratio_baseline=None, minor_ticks=[]):
    keys = sorted(list(next(iter(series.values())).keys()))
    print(keys)

    n_series = len(series)
    n_bars = len(keys)
    base_x = np.arange(n_bars)  # the label locations
    width = 1/(n_series+1)  # the width of the bars

    fig, ax = plt.subplots()

    begin = - (n_series - 1) * width / 2
    for i, s in enumerate(series.keys()):
        queries = series[s]
        x = base_x + begin + i*width
        if ratio_baseline:
            y = [queries[k][f'{metric}_time_ratio'] for k in keys]
            plt.bar(x, y, width, label=s)
        else:
            y = [queries[k][f'{metric}_time_avg'] for k in keys]
            yerr = [queries[k][f'{metric}_time_std'] for k in keys]
            plt.bar(x, y, width, label=s)
            plt.errorbar(x, y, yerr=yerr, linestyle="None")

    # configure matplotlib
    ax.legend()
    ax.grid()
    ax.set_xlabel("Query (#tables)")
    if ratio_baseline:
        ax.set_ylabel("Time ratio\n(Y = series > reference ? series/reference : reference/series)")
    else:
        ax.set_ylabel("Time (ms)")

    ax.set_xticks(base_x)
    ax.set_xticklabels([f"{k.split('/')[-1]} ({next(iter(series.values()))[k]['tables']})" for k in keys])

def export_csv(csv_file, series, metric, ratio=False, ratio_baseline=None):
    key = f"{metric}_time_{'ratio' if ratio else 'avg'}"
    aggr_fun = gmean if ratio else np.average
    aggr_label = "gmean" if ratio else "avg"

    header = (
        "series",
        "query",
        "type",
        "n_rels",
        f"{metric}_time{f'_ratio({ratio_baseline})' if ratio else ''}"
    )
    output = []

    for s, queries in series.items():
        for query in queries:
            output.append((
                s,
                query,
                'raw',
                queries[query]['tables'],
                queries[query][key]
            ))

        keys = sorted(list(queries.keys()))
        x = np.array([queries[k]['tables'] for k in keys])
        y = np.array([queries[k][key] for k in keys])

        for n in np.sort(np.unique(x)):
            mask = (x == n) & (y > 0)
            if np.any(mask):
                output.append((
                    s,
                    f"{aggr_label}({np.sum(mask)})",
                    aggr_label,
                    n,
                    aggr_fun(y[mask])
                ))

    with open(csv_file, 'w', newline='') as myfile:
        wr = csv.writer(myfile, quoting=csv.QUOTE_ALL)
        wr.writerow(header)
        wr.writerows(output)

    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Plot some stats")
    parser.add_argument("result_folders", nargs='+', type=str, help="Folders where results are stored. Each folder should contain one or more result file. Each different folder will be treated as a different experiment.")
    parser.add_argument("-d", "--sql_folder", default=None, help="Path to the sql queries.")
    parser.add_argument("-s", "--save", default=None, help="Path to save plot to.")
    parser.add_argument("-m", "--metric", default="plan", choices=["plan", "exec", "total", "gpuqo"], help="Show whether to choose plan or execution time or their sum.")
    parser.add_argument("-t", "--type", default="scatter", choices=["scatter", "bar","line", "scatter_line", "none"], help="Choose plot type: scatter or bar.")
    parser.add_argument("-r", "--ratio", default=False, action="store_true", help="Plot ratio related to the baseline (default: first) series.")
    parser.add_argument("-b", "--baseline", type=int, default=0, help="Set the baseline series for ratio plot.")
    parser.add_argument("--min_tables", type=int, default=0, help="Limit the number of tables to only the ones that have more than this number of tables.")
    parser.add_argument("--max_tables", type=int, default=1e10, help="Limit the number of tables to only the ones that have less than this number of tables.")
    parser.add_argument("--name_depth", type=int, default=1, help="Set depth of series name wrt to folder path (default=1).")
    parser.add_argument("--shift", type=float, default=0.25, help="Set spread of points in scatter and line plots (default 0.25).")
    parser.add_argument("-v", "--verbose", default=False, action="store_true", help="Print debug messages.")
    parser.add_argument("--ticks", default=[1.5,2,3,4,5,8,15,25,50,75,150,200,250,300], type=float, nargs="+", help="Minor ticks for ratio plot.")
    parser.add_argument("--csv", type=str, default=None, help="Dump series data in given csv file.")

    args = parser.parse_args()

    if args.verbose:
        print(args)

    series = {
        folder2series(folder, args.name_depth):
        {
            query:content
            for query, content in load_results_complete(folder, args.sql_folder).items()
            if (content['tables'] >= args.min_tables
                and content['tables'] <= args.max_tables)
        }
        for folder in args.result_folders
    }

    ratio_baseline = None
    metric=args.metric
    if args.ratio:
        baseline = folder2series(args.result_folders[args.baseline], args.name_depth)
        new_series = {}
        for s, queries in series.items():
            if s == baseline:
                continue
            new_label = s
            new_series[new_label] = {}
            for query in queries:
                new_series[new_label][query] = {
                    f"{metric}_time_ratio": ratio(
                        queries[query][f"{metric}_time_avg"],
                        series[baseline][query][f"{metric}_time_avg"]
                    ) if query in series[baseline] else np.nan
                    # for metric in ['plan', 'exec', 'total', 'gpuqo']
                }
                new_series[new_label][query]['tables'] =queries[query]['tables']

        series = new_series
        ratio_baseline = baseline

    if args.verbose:
        print(series)

    if args.type == 'scatter':
        scatter_plot(
            series,
            metric=args.metric,
            ratio_baseline=ratio_baseline,
            max_shift=args.shift,
            minor_ticks=args.ticks
        )
    elif args.type == 'bar':
        bar_plot(
            series,
            metric=args.metric,
            ratio_baseline=ratio_baseline,
            minor_ticks=args.ticks
        )
    elif args.type == 'line':
        line_plot(
            series,
            metric=args.metric,
            ratio_baseline=ratio_baseline,
            max_shift=args.shift,
            minor_ticks=args.ticks
        )
    elif args.type == 'scatter_line':
        scatter_line_plot(
            series,
            metric=args.metric,
            ratio_baseline=ratio_baseline,
            max_shift=args.shift,
            minor_ticks=args.ticks
        )

    if args.csv:
        export_csv(args.csv, series, args.metric, args.ratio, ratio_baseline)

    if args.save:
        plt.savefig(args.save)
    else:
        plt.show()
