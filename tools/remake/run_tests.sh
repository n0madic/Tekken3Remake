#!/bin/sh
# Runs the remake's test suites headless (tests/run_tests.gd, no external dependencies).
#
#   tools/remake/run_tests.sh [--quick] [name filter ...]
#
# The whole run is shared by JOBS parallel runners (default: the CPU count less two, at most 12),
# each claiming the next test no runner has taken, the longest first by the times of earlier runs
# (remake/.godot/test_times.txt); a run with name filters or --quick uses one runner unless JOBS
# says otherwise. --quick leaves out the comparisons with the game's traces (suites with
# `const SLOW := true`): seconds instead of about three minutes.
#
# Suites that need the converted assets (tools/remake_import/convert.py) or the golden
# traces (tools/research/export_traces.py) are skipped when those are missing.
# GODOT may point at the Godot 4.7 binary; by default the macOS app or `godot` on PATH.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROJECT="$ROOT/remake"
if [ -z "${GODOT:-}" ]; then
	if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else
		GODOT=godot
	fi
fi

# Refresh the global class cache and imported resources when a project file changed since the
# last refresh.
STAMP="$PROJECT/.godot/tests_import.stamp"
if [ ! -f "$STAMP" ] || [ -n "$(find "$PROJECT" -path "$PROJECT/.godot" -prune -o -newer "$STAMP" -type f -print | head -n 1)" ]; then
	"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
	mkdir -p "$PROJECT/.godot"
	touch "$STAMP"
fi

single=0
[ "$#" -gt 0 ] && single=1
if [ -z "${JOBS:-}" ]; then
	if [ "$single" = 1 ]; then
		JOBS=1
	else
		cpus=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
		JOBS=$((cpus - 2))
		[ "$JOBS" -gt 12 ] && JOBS=12
		[ "$JOBS" -lt 1 ] && JOBS=1
	fi
fi

if [ "$JOBS" -le 1 ]; then
	exec "$GODOT" --headless --path "$PROJECT" -s res://tests/run_tests.gd -- "$@"
fi

OUT=$(mktemp -d "${TMPDIR:-/tmp}/remake_tests.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
TIMES="$PROJECT/.godot/test_times.txt"
mkdir "$OUT/claims"
start=$(date +%s)
i=0
pids=""
while [ "$i" -lt "$JOBS" ]; do
	"$GODOT" --headless --path "$PROJECT" --log-file "$OUT/godot_$i.log" -s res://tests/run_tests.gd \
		-- --claim="$OUT/claims" --times="$TIMES" --times-out="$OUT/times_$i.txt" "$@" >"$OUT/shard_$i.txt" 2>&1 &
	pids="$pids $!"
	i=$((i + 1))
done

status=0
for pid in $pids; do
	wait "$pid" || status=1
done

passed=0
failed=0
skipped=0
i=0
while [ "$i" -lt "$JOBS" ]; do
	grep -v -e '^Godot Engine v' -e '^[0-9]* passed, [0-9]* failed' -e '^$' "$OUT/shard_$i.txt" || true
	summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped' "$OUT/shard_$i.txt" || true)
	if [ -z "$summary" ]; then
		echo "ERROR  runner $i/$JOBS ended without a summary"
		status=1
	else
		set -- $summary
		passed=$((passed + $1))
		failed=$((failed + $3))
		skipped=$((skipped + $5))
	fi
	i=$((i + 1))
done
# The tests' times, for the next run's order (these runs' times replace the earlier ones).
cat "$TIMES" "$OUT"/times_*.txt 2>/dev/null |
	awk -F '\t' 'NF == 2 { t[$1] = $2 } END { for (k in t) print k "\t" t[k] }' >"$OUT/times.txt"
mv "$OUT/times.txt" "$TIMES"
echo
echo "$passed passed, $failed failed, $skipped skipped in $(( $(date +%s) - start )) s ($JOBS runners)"
exit "$status"
