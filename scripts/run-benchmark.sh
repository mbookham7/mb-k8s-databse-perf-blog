#!/bin/bash
#
# Run pgbench against both PostgreSQL instances (gp3 "standard block" vs WEKA)
# across a range of client concurrency levels, then emit a Markdown results
# table mirroring the blog's "Step 4: Results".
#
# Prerequisites:
#   - kubectl configured against the EKS cluster
#   - manifests/postgres applied; both DB pods Running; pgbench-runner Ready
#
# Usage:
#   scripts/run-benchmark.sh [--scale 100] [--duration 60] \
#       [--clients "4 16 32 64"] [--skip-init]

set -euo pipefail

NS="benchmark"
RUNNER="pgbench-runner"
DB="benchdb"
USER="postgres"
STANDARD_SVC="postgres-standard-svc"
WEKA_SVC="postgres-weka-svc"

# Scale 1000 (~15 GB) deliberately exceeds shared_buffers (4GB) + the pod memory
# limit, so reads hit storage and the workload is storage-bound (not RAM-cached).
SCALE=1000
DURATION=60
CLIENTS="4 16 32 64"
JOBS=4
SKIP_INIT=false

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$REPO_ROOT/results"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scale)    SCALE="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --clients)  CLIENTS="$2"; shift 2 ;;
        --jobs)     JOBS="$2"; shift 2 ;;
        --skip-init) SKIP_INIT=true; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[ERROR] Unknown option: $1"; exit 1 ;;
    esac
done

# Run pgbench in the runner pod against a service. Echoes "<tps>|<latency_ms>".
run_one() {
    local svc="$1" clients="$2"
    local out
    out=$(kubectl exec "$RUNNER" -n "$NS" -- \
        pgbench -h "$svc" -U "$USER" -d "$DB" \
        -c "$clients" -j "$JOBS" -T "$DURATION" -P 10 2>&1)

    # pg16 prints "tps = N (without initial connection time)"; fall back to any tps line.
    local tps lat
    tps=$(echo "$out" | awk '/without initial connection time/ {print $3; found=1} END{ if(!found) print "NA"}')
    [[ "$tps" == "NA" || -z "$tps" ]] && tps=$(echo "$out" | awk '/^tps =/ {print $3; exit}')
    lat=$(echo "$out" | awk '/latency average/ {print $4; exit}')
    printf '%.0f|%s' "${tps:-0}" "${lat:-NA}"
}

init_one() {
    local svc="$1"
    echo "  Initializing pgbench schema on $svc (scale $SCALE)..."
    kubectl exec "$RUNNER" -n "$NS" -- \
        pgbench -h "$svc" -U "$USER" -d "$DB" -i -s "$SCALE" >/dev/null 2>&1
}

echo "=============================================="
echo "PostgreSQL Storage Benchmark (pgbench)"
echo "=============================================="
echo "  Scale factor: $SCALE   Duration: ${DURATION}s   Clients: $CLIENTS"
echo ""

echo "Waiting for pgbench-runner to be Ready..."
kubectl wait --for=condition=Ready "pod/$RUNNER" -n "$NS" --timeout=180s

if [[ "$SKIP_INIT" == "false" ]]; then
    echo "Initializing schemas..."
    init_one "$STANDARD_SVC"
    init_one "$WEKA_SVC"
    echo ""
fi

mkdir -p "$RESULTS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$RESULTS_DIR/results-$STAMP.md"

# Accumulate rows; print live and collect for the file.
declare -a TPS_ROWS LAT_ROWS

for c in $CLIENTS; do
    echo "--- $c clients ---"
    std=$(run_one "$STANDARD_SVC" "$c")
    wek=$(run_one "$WEKA_SVC" "$c")

    std_tps="${std%%|*}"; std_lat="${std##*|}"
    wek_tps="${wek%%|*}"; wek_lat="${wek##*|}"

    tps_impr="NA"
    if [[ "$std_tps" -gt 0 ]] 2>/dev/null; then
        tps_impr=$(awk -v w="$wek_tps" -v s="$std_tps" 'BEGIN{printf "%+d%%", (w-s)/s*100}')
    fi
    lat_impr="NA"
    if [[ "$std_lat" != "NA" && "$wek_lat" != "NA" ]]; then
        lat_impr=$(awk -v w="$wek_lat" -v s="$std_lat" 'BEGIN{printf "%+d%%", (w-s)/s*100}')
    fi

    echo "  standard: ${std_tps} TPS / ${std_lat} ms    weka: ${wek_tps} TPS / ${wek_lat} ms"
    TPS_ROWS+=("| $c | $std_tps | $wek_tps | $tps_impr |")
    LAT_ROWS+=("| $c | $std_lat | $wek_lat | $lat_impr |")
done

{
    echo "# PostgreSQL Storage Benchmark Results"
    echo ""
    echo "- Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "- Scale factor: $SCALE (~$(awk -v s="$SCALE" 'BEGIN{printf "%.1f", s*0.015}') GB dataset)"
    echo "- Run duration: ${DURATION}s per concurrency level"
    echo ""
    echo "## Transactions Per Second (TPS) by Concurrency Level"
    echo ""
    echo "| Concurrent Clients | Standard Block Storage (TPS) | WEKA (TPS) | Improvement |"
    echo "|---|---|---|---|"
    printf '%s\n' "${TPS_ROWS[@]}"
    echo ""
    echo "## Average Latency (ms) by Concurrency Level"
    echo ""
    echo "| Concurrent Clients | Standard Block Storage (ms) | WEKA (ms) | Change |"
    echo "|---|---|---|---|"
    printf '%s\n' "${LAT_ROWS[@]}"
} | tee "$OUT_FILE"

echo ""
echo "[OK] Results written to $OUT_FILE"
