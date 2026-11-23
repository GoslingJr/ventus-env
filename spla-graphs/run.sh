#!/usr/bin/env bash
set -euo pipefail

if (( $# < 3 || $# > 4 )); then
    echo "Usage: $0 SPLA_BUILD MATRIX_DIR RESULTS_DIR [case]" >&2
    exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
build=$(realpath -e "$1")
data=$(realpath -e "$2")
mkdir -p "$3"
output=$(realpath -e "$3")
source "$here/../env.sh"
export VENTUS_BACKEND=spike
export OCL_ICD_FILENAMES="$VENTUS_INSTALL_PREFIX/lib/libpocl.so"
# Spike in this branch keeps a trace file open for each work group.
ulimit -Sn 1048576

run_case() {
    local name=$1
    local args=() exe matrix
    case "$name" in
        bfs) exe=bfs; matrix=netscience; args=(--source=33) ;;
        pr) exe=pr; matrix=netscience ;;
        sssp) exe=sssp; matrix=netscience; args=(--source=33 --matrix-weights --gpu-output=distances.tsv) ;;
        tc) exe=tc; matrix=netscience ;;
        bfs-directed) exe=bfs; matrix=p2p-Gnutella08; args=(--source=0 --directed) ;;
        pr-incoming) exe=pr; matrix=karate; args=(--incoming --gpu-output=ranks.tsv) ;;
        *) echo "Unknown case: $name" >&2; return 2 ;;
    esac
    local run
    run=$(mktemp -d "$output/$name.XXXXXXXX")
    echo "$name: $run"
    (
        cd "$run"
        export POCL_CACHE_DIR="$run/cache"
        "$build/$exe" --mtxpath "$data/$matrix/$matrix.mtx" --niters=1 \
            --run-cpu --run-gpu --run-ref "${args[@]}" > run.log 2>&1
        grep -Eq '^env: .*device: Ventus GPGPU device .*wave:32( |$)' run.log
        grep -qx 'CHECK cpu' run.log
        grep -qx 'CHECK acc' run.log
        if grep -q ' VERIFY:' run.log; then exit 1; fi
        case "$name" in
            sssp) python3 "$here/verify.py" "$data" distances.tsv ;;
            pr-incoming) python3 "$here/verify.py" "$data" ranks.tsv ;;
        esac
    )
    echo "PASS $name"
}

if (( $# == 4 )); then
    run_case "$4"
else
    for name in bfs pr sssp tc bfs-directed pr-incoming; do
        run_case "$name"
    done
fi
