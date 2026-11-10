#!/usr/bin/env python3
"""Design probe: how many skill-graph nodes does a Fire blast disc reach?

NOT game code and not shipped. It answers the numbers in
docs/handoffs/elements-split/cast-shapes-rates.md without launching Godot.
Nothing is cached on disk; a run takes seconds. Needs numpy and scipy.

What it ports (a Python re-implementation of the generator, not a binding):
  - procgen/placement/poisson_disk_sampler.gd     Bridson sampling, k = 30, random active pick,
                                                   circular mask of area N * spacing^2 * 1.6
                                                   (GraphProcgen._POISSON_AREA_PER_POINT)
  - procgen/phases/procgen_topology.gd             Delaunay -> Kruskal MST + the shortest 25% of
    (triangulate_and_prune)                        the leftover edges (connectivity 0.25)
  - procgen/modules/topology.gd                    min spacing = 2 * max node radius + padding
  - attack/range_finder/euclidean_range_finder.gd  a node is hit when d - candidate_radius <= reach
Disc radius (px) = A * (sqrt(power) + B) * node_radius. B = 0 is a plain multiplier (today's
Explosive disc is A = 3). Sources are random nodes of the whole graph (centre excluded from the
count); every node has the same radius. The first-level radius ramp is NOT ported.

Validation, both at the defaults (spacing 150, node radius 32, 10 maps, 300 sources, seed 1):
  1. `--hops`: unique nodes within L hops, L = 1..4, expect 3.0 / 7.8 / 14.5 / 23.0
     (the measured table in the report: 3.0 / 7.9 / 14.5 / 23.1).
  2. `--a 3 --b 0 --powers 1,2,3,4,6,8,10`: nodes hit expect 0 / 1.21 / 2.61 / 3.59 / 5.21 / 6.91 / 8.42
     (the report's first-published row: 0 / 1.2 / 2.6 / 3.6 / 5.2 / 6.9 / 8.4).

Examples:
  disc_reach.py --a 2 --b 1 --powers 1,2,3,4,6,10
  disc_reach.py --a 2 --b 1 --per-point 5 --points 1,2,3,5,10
  disc_reach.py --a 3 --b 0 --per-point 3 --fit-ladder
"""
import argparse
import math
import random
import sys

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import shortest_path
from scipy.spatial import Delaunay

K_TRIES = 30
CONNECTIVITY = 0.25
AREA_PER_POINT = 1.60
LADDER_POINTS = (1, 3, 6, 10)
LADDER_TARGET = (3, 8, 15, 23)  # Lightning scheme B: nodes within L hops, L = 1..4


def poisson(rng, n_max, spacing):
    """Bridson sampling in a circular mask, same loop as PoissonDiskSampler.sample (no anchors)."""
    radius = math.sqrt(n_max * spacing * spacing * AREA_PER_POINT / math.pi)
    cell = spacing / math.sqrt(2)
    cols = rows = int(math.ceil(2 * radius / cell))
    grid = -np.ones(cols * rows, int)
    pts, active = [], []

    def ok(p):
        if p[0] * p[0] + p[1] * p[1] > radius * radius:
            return False
        gx, gy = int((p[0] + radius) / cell), int((p[1] + radius) / cell)
        if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
            return False
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                nx, ny = gx + dx, gy + dy
                if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
                    continue
                i = grid[ny * cols + nx]
                if i != -1 and (pts[i][0] - p[0]) ** 2 + (pts[i][1] - p[1]) ** 2 < spacing * spacing:
                    return False
        return True

    def emit(p):
        if not ok(p):
            return False
        pts.append(p)
        i = len(pts) - 1
        grid[int((p[1] + radius) / cell) * cols + int((p[0] + radius) / cell)] = i
        active.append(i)
        return True

    for _ in range(64):
        if emit((rng.uniform(-radius, radius), rng.uniform(-radius, radius))):
            break
    while active and len(pts) < n_max:
        ai = rng.randrange(len(active))
        o = pts[active[ai]]
        placed = False
        for _ in range(K_TRIES):
            a = rng.random() * 2 * math.pi
            r = rng.uniform(spacing, 2 * spacing)
            if emit((o[0] + math.cos(a) * r, o[1] + math.sin(a) * r)):
                placed = True
                if len(pts) >= n_max:
                    break
        if not placed:
            active.pop(ai)
    return np.array(pts)


def prune(pts):
    """Delaunay edges -> Kruskal spanning tree + the shortest 25% of the leftovers."""
    n = len(pts)
    edges = set()
    for a, b, c in Delaunay(pts).simplices:
        for u, v in ((a, b), (b, c), (a, c)):
            edges.add((min(u, v), max(u, v)))
    edges = list(edges)
    length = [((pts[u] - pts[v]) ** 2).sum() for u, v in edges]
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    kept, extra = [], []
    for i in sorted(range(len(edges)), key=lambda i: length[i]):
        u, v = edges[i]
        ru, rv = find(u), find(v)
        if ru != rv:
            parent[ru] = rv
            kept.append((u, v))
        else:
            extra.append((u, v))
    return kept + extra[:int(round(CONNECTIVITY * len(extra)))]


def collect(args):
    """Per source: sorted (centre distance - node radius) of every node, the largest such value over
    its graph neighbours, and the hop distances. Any reach is then a searchsorted away."""
    eff_sorted, nb_max, hop_balls = [], [], {L: [] for L in range(1, 9)}
    for mi in range(args.maps):
        rng = random.Random(args.seed * 1000 + mi)
        pts = poisson(rng, args.nodes, args.spacing)
        n = len(pts)
        edges = prune(pts)
        adj = [[] for _ in range(n)]
        for u, v in edges:
            adj[u].append(v)
            adj[v].append(u)
        rows = [u for u, v in edges] + [v for u, v in edges]
        cols = [v for u, v in edges] + [u for u, v in edges]
        hops = shortest_path(csr_matrix((np.ones(len(rows)), (rows, cols)), shape=(n, n)),
                             unweighted=True, directed=False)
        for s in random.Random(args.seed * 77 + mi).sample(range(n), min(args.sources, n)):
            eff = np.linalg.norm(pts - pts[s], axis=1) - args.node_radius
            eff_sorted.append(np.sort(eff))
            nb_max.append(max(eff[j] for j in adj[s]))
            for L in hop_balls:
                hop_balls[L].append(((hops[s] <= L) & (hops[s] > 0)).sum())
    return np.array(eff_sorted), np.array(nb_max), hop_balls


def stats(eff_sorted, nb_max, reach):
    """(mean nodes hit, share hitting nothing, share covering every graph neighbour) for one reach.
    The source itself is always inside (d - r < 0), so it is subtracted."""
    hit = np.array([np.searchsorted(row, reach, side="right") for row in eff_sorted]) - 1
    return hit.mean(), (hit == 0).mean(), (nb_max <= reach).mean()


def rms(values, target):
    return math.sqrt(sum((v - t) ** 2 for v, t in zip(values, target)) / len(target))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", type=float, default=3.0, help="A in radius = A * (sqrt(p) + B) * node_radius")
    ap.add_argument("--b", type=float, default=0.0, help="B, the offset")
    ap.add_argument("--per-point", type=float, help="blast power per point (real); needs --points or --fit-ladder")
    ap.add_argument("--powers", help="comma list of blast powers to table")
    ap.add_argument("--points", help="comma list of points; power = per-point * points")
    ap.add_argument("--fit-ladder", action="store_true",
                    help="nodes at 1/3/6/10 points against Lightning B's 3/8/15/23, with the rms")
    ap.add_argument("--hops", action="store_true", help="also print unique nodes within L hops (validation 1)")
    ap.add_argument("--spacing", type=float, default=150.0, help="Poisson min spacing, px")
    ap.add_argument("--node-radius", type=float, default=32.0)
    ap.add_argument("--nodes", type=int, default=800)
    ap.add_argument("--maps", type=int, default=10)
    ap.add_argument("--sources", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    if args.fit_ladder:
        points = list(LADDER_POINTS)
    elif args.points:
        points = [float(x) for x in args.points.split(",")]
    else:
        points = None
    if points is not None:
        if args.per_point is None:
            sys.exit("--points / --fit-ladder need --per-point")
        rows = [(f"{x:g} pt", args.per_point * x) for x in points]
    else:
        powers = [float(x) for x in (args.powers or "1,2,3,4,6,8,10").split(",")]
        rows = [(f"p={p:g}", p) for p in powers]

    eff_sorted, nb_max, hop_balls = collect(args)
    print(f"A={args.a:g} B={args.b:g} node_radius={args.node_radius:g} spacing={args.spacing:g} "
          f"maps={args.maps} sources={args.sources} seed={args.seed}\n")
    print("| | power | radius px | nodes hit | hits nothing | covers every neighbour |")
    print("|---|---|---|---|---|---|")
    hits = []
    for label, p in rows:
        radius = args.a * (math.sqrt(p) + args.b) * args.node_radius
        mean, none, allnb = stats(eff_sorted, nb_max, radius)
        hits.append(mean)
        print(f"| {label} | {p:g} | {radius:.0f} | {mean:.2f} | {none * 100:.1f}% | {allnb * 100:.1f}% |")
    if args.fit_ladder:
        print(f"\nladder nodes {' / '.join(f'{h:.1f}' for h in hits)} against "
              f"{' / '.join(str(t) for t in LADDER_TARGET)}: rms {rms(hits, LADDER_TARGET):.2f}")
    if args.hops:
        print("\nunique nodes within L hops, L = 1..4: "
              + " / ".join(f"{np.mean(hop_balls[L]):.1f}" for L in range(1, 5)))


if __name__ == "__main__":
    main()
