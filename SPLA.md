# Running SPLA on Ventus (spike)

This branch collects the fixes needed to run the SPLA test suite
(https://github.com/SparseLinearAlgebra/spla) on Ventus with the spike backend.
Result: 13/13 test programs, 58/58 tests pass.

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
bash build-ventus.sh
```

## Run SPLA

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

## Not covered

* cyclesim and the RTL still decode AMOs as scalar instructions, so atomics
  (`vxm_masked.*`, `vector.eadd_fdb_min`) fail there.
* Kernels without calls that use `__local` arrays with constant indices do not
  get the `s0` prologue adjustment (the epilogue still subtracts it). Not fixed yet.
