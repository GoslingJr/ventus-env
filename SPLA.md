# Running SPLA on Ventus (spike)

This branch collects the fixes needed to run the SPLA test suite
(https://github.com/SparseLinearAlgebra/spla) on Ventus with the spike backend.
Result on a clean clone and build: Ventus regression tests 11/11, SPLA 13/13 test programs, 58/58 tests.

## What is changed

Submodules point to forks with the fixes (branch `ventus-env-fixes`):

| submodule | fork | changes | upstream PR |
|---|---|---|---|
| `llvm` | GoslingJr/llvm-project | frame address of `__local` arrays; signed imm12 in `vadd12.vi`/`vsub12.vi`; alignment of by-value struct kernel arguments | THU-DSP-LAB/llvm-project#215, #216, #217 |
| `spike` | GoslingJr/ventus-gpgpu-isa-simulator | 32-bit AMOs executed per thread (from `feature/vector-amo`) + lane masking fix | THU-DSP-LAB/ventus-gpgpu-isa-simulator#53 |
| `pocl` | GoslingJr/pocl | `global_mem_size` and `max_mem_alloc_size` raised to 1.5 GB (the 32-bit address space allows about 1.75 GB above 0x90000000) | none |

`spla-small-tests.patch` reduces the input sizes of the perf tests
(`test_mxv`, `test_vxm`, `test_vector`, `test_opencl_merge`). With the original
sizes they need more memory than a 32-bit device has and take hours on spike.

## Build

```
git clone --recursive -b spla-fixes https://github.com/GoslingJr/ventus-env.git
cd ventus-env
make rodinia_data      # dataset for the rodinia tests run at the end of build-ventus.sh
bash build-ventus.sh
```

With less than about 32 GB of RAM, lower `LLVM_PARALLEL_LINK_JOBS` in
`build-ventus.sh` (for example to 2) before building, otherwise linking LLVM
may run out of memory.

Check the build with the Ventus regression tests (11/11 pass):

```
source env.sh
python3 regression-test.py
```

## Run SPLA

In every new shell, set up the environment first (from the `ventus-env` directory):

```
source env.sh
export OCL_ICD_FILENAMES=$VENTUS_INSTALL_PREFIX/lib/libpocl.so
git clone --recursive https://github.com/SparseLinearAlgebra/spla.git ~/spla
git -C ~/spla apply $PWD/spla-small-tests.patch
cmake -S ~/spla -B ~/spla/build-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build ~/spla/build-debug -j8
bash run-spla.sh ~/spla/build-debug/tests
```

`run-spla.sh` runs every `test_*` program with `VENTUS_BACKEND=spike`
and prints a summary. Spike writes a commit log per kernel into the current
directory, the script deletes it after each program.

In a Debug build SPLA prints `select OpenCL device Ventus GPGPU device` and
`build program` for every kernel, so it is easy to check that the tests really
run on Ventus and not on the CPU fallback.

## Graph algorithms on real matrices

The `spla-graphs` directory reproduces BFS, PageRank, weighted SSSP and triangle
counting on the Spike backend. The patch matches SPLA commit
`b81d1e291d38dad627f4ad863dcfb7c3315951fd`. It selects a 32-lane wave for
the Ventus OpenCL device. The example options are opt-in.

Starting in the root of this built ventus-env checkout:

```bash
ventus=$(pwd)
work=$(mktemp -d)
git clone https://github.com/SparseLinearAlgebra/spla.git "$work/spla"
git -C "$work/spla" checkout --detach b81d1e291d38dad627f4ad863dcfb7c3315951fd
git -C "$work/spla" apply "$ventus/spla-graphs/spla-graphs.patch"
cmake -S "$work/spla" -B "$work/build" -G Ninja -DCMAKE_BUILD_TYPE=Debug -DSPLA_BUILD_TESTS=OFF
cmake --build "$work/build" --parallel 6 --target bfs pr sssp tc
```

Use Matrix Market files from the SuiteSparse Matrix Collection with the layout
`data/NAME/NAME.mtx`. To download just these three matrices into the new directory:

```bash
(
    set -e
    for entry in Newman/netscience Newman/karate SNAP/p2p-Gnutella08; do
        name=${entry##*/}
        mkdir -p "$work/data/$name"
        curl -fLsS "https://www.cise.ufl.edu/research/sparse/MM/$entry.tar.gz" -o "$work/$name.tar.gz"
        tar -xOzf "$work/$name.tar.gz" "$name/$name.mtx" > "$work/data/$name/$name.mtx"
    done
    cd "$work/data"
    sha256sum -c "$ventus/spla-graphs/matrices.sha256"
)
```

Run all six cases, or append a single case name from the table. The runner
selects Ventus via OpenCL and uses one fresh output directory and cache per
case. Allow several minutes per case and a few GB for Spike traces.

```bash
bash "$ventus/spla-graphs/run.sh" "$work/build" "$work/data" "$work/results"
```

| Case | Matrix | Reference result |
| --- | --- | --- |
| `bfs` | Newman/netscience | From vertex 33, 379 of 1589 vertices reachable, maximum distance 10. |
| `pr` | Newman/netscience | Stock SPLA example, checked against CPU and its naive reference. |
| `sssp` | Newman/netscience | Original nonnegative edge weights from the real symmetric matrix. All 1589 distances checked against Dijkstra from vertex 33. |
| `tc` | Newman/netscience | 3764 triangles. |
| `bfs-directed` | SNAP/p2p-Gnutella08 | Push-only BFS on the original arcs from vertex 0. 6031 of 6301 vertices reachable, maximum distance 15. |
| `pr-incoming` | Newman/karate | Standard incoming-neighbor PageRank on this undirected graph without isolated vertices. All 34 ranks checked with a double-precision reference at damping 0.85. |

Vertex IDs are zero-based. A passing case requires successful program exit,
a device log showing Ventus with wave size 32, and passing CPU and accelerator
reference checks in the Debug build. The verifier also requires absolute error
below 1e-5 for all finite SSSP distances and all incoming PageRank values.

## Not covered

* cyclesim and the RTL still decode AMOs as scalar instructions, so atomics
  (`vxm_masked.*`, `vector.eadd_fdb_min`) fail there.
* Kernels without calls that use `__local` arrays with constant indices do not
  get the `s0` prologue adjustment (the epilogue still subtracts it). Not fixed yet.
