"""Check the two exported Ventus vectors against independent graph algorithms."""
import argparse
import heapq
import math
from pathlib import Path


def load_graph(directory, name):
    path = directory / name / (name + ".mtx")
    with path.open() as stream:
        symmetric = stream.readline().split()[-1] == "symmetric"
        rows, cols, count = map(int, next(line for line in stream if not line.startswith("%")).split())
        if rows != cols:
            raise ValueError("expected a square matrix")
        graph = [[] for _ in range(rows)]
        for _ in range(count):
            i, j, *weight = next(stream).split()
            i, j = int(i) - 1, int(j) - 1
            w = float(weight[0]) if weight else 1.0
            graph[i].append((j, w))
            if symmetric and i != j:
                graph[j].append((i, w))
    return graph


def dijkstra(graph, source):
    distances = [math.inf] * len(graph)
    distances[source] = 0.0
    queue = [(0.0, source)]
    while queue:
        distance, i = heapq.heappop(queue)
        if distance != distances[i]:
            continue
        for j, weight in graph[i]:
            candidate = distance + weight
            if candidate < distances[j]:
                distances[j] = candidate
                heapq.heappush(queue, (candidate, j))
    return distances


def pagerank(graph):
    n = len(graph)
    ranks = [1 / n] * n
    for _ in range(1000):
        updated = [0.15 / n] * n
        for i, edges in enumerate(graph):
            for j, _ in edges:
                updated[j] += 0.85 * ranks[i] / len(edges)
        if max(abs(a - b) for a, b in zip(updated, ranks)) < 1e-14:
            return updated
        ranks = updated
    raise ValueError("PageRank reference did not converge")


def verify(directory, path):
    if path.name == "distances.tsv":
        expected = dijkstra(load_graph(directory, "netscience"), 33)
    elif path.name == "ranks.tsv":
        expected = pagerank(load_graph(directory, "karate"))
    else:
        raise ValueError("expected distances.tsv or ranks.tsv")
    actual = []
    for row in path.read_text().splitlines():
        index, value = row.split()
        if int(index) != len(actual) or not math.isfinite(float(value)):
            raise ValueError(f"invalid output at vertex {index}")
        actual.append(float(value))
    if len(actual) != len(expected):
        raise ValueError("incomplete vector")
    max_error = 0.0
    for i, (value, ref) in enumerate(zip(actual, expected)):
        if math.isinf(ref):
            if value < 3.4e38:
                raise ValueError(f"vertex {i} should be unreachable")
        else:
            max_error = max(max_error, abs(value - ref))
    if max_error >= 1e-5:
        raise ValueError(f"maximum absolute error {max_error:g}")
    if path.name == "ranks.tsv" and abs(sum(actual) - 1.0) >= 1e-5:
        raise ValueError("rank sum differs from one")
    print(f"{path.name}: {len(actual)} vertices, max absolute error {max_error:.8g}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix_directory", type=Path)
    parser.add_argument("vector", type=Path)
    args = parser.parse_args()
    verify(args.matrix_directory, args.vector)
