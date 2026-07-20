#!/bin/bash
#
# run_and_log.sh — build + run the MMU trace tests and save their console
# output into ./output/ so you can inspect the results.
#
#   ./run_and_log.sh            # build core_tb (if needed), build firmware, run both tests
#   ./run_and_log.sh --no-build # skip 'make core_tb' (use the existing simulator)
#
# Notes:
#   * The Microwatt sim prints its UART console on STDERR; GHDL's own chatter
#     goes to STDOUT.  We keep stderr (the test log) and discard stdout.
#   * core_tb has no fixed run limit; it stops itself when the firmware calls
#     'attn' at the end of main(), which is when the log is flushed.
#
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"        # tests/TRACE_CURATED_LOGGING_TEST
REPO="$(cd "$HERE/../.." && pwd)"            # microwatt/
OUT="$HERE/output"
mkdir -p "$OUT"

DO_BUILD=1
[ "${1:-}" = "--no-build" ] && DO_BUILD=0

if [ "$DO_BUILD" = 1 ]; then
    echo ">> building simulator (make core_tb) ..."
    make -C "$REPO" core_tb || { echo "core_tb build FAILED"; exit 1; }
fi

run_one() {
    local test="$1"
    local log="$OUT/$test.log"
    echo ">> building firmware: $test"
    make -C "$REPO/tests/$test" >/dev/null || { echo "  firmware build FAILED"; return 1; }
    cp "$REPO/tests/$test/$test.bin" "$REPO/tests/main_ram.bin"
    echo ">> running $test  (this can take a few minutes: the stop-on-full test"
    echo "   fills all 2048 records, i.e. several hundred radix walks) ..."
    ( cd "$REPO/tests" && \
      ( tail -f /dev/null | ../core_tb --ieee-asserts=disable --unbuffered 2>&1 >/dev/null ) \
        | tr -d '\r' ) > "$log" 2>/dev/null
    echo ">> log written: $log"
    echo "   ---- SUMMARY line ----"
    grep -E "SUMMARY|ALL TESTS PASSED|SOME TESTS FAILED" "$log" | sed 's/^/     /'
    echo
}

# The curated-logging test is the primary gate; BIT63 is the regression.
run_one TRACE_CURATED_LOGGING_TEST
run_one BIT63_LOGGING_ENABLE_TEST

echo ">> done.  Full logs are in: $OUT"
ls -l "$OUT"/*.log 2>/dev/null
