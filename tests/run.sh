#!/usr/bin/env bash
# Run all test_*.sh files. Exit non-zero on any failure.

set -u
cd "$(dirname "$0")"

overall_failed=0

for t in test_*.sh; do
    [ -f "$t" ] || continue
    echo "=== $t ==="
    if bash "$t"; then
        :
    else
        overall_failed=$((overall_failed + 1))
    fi
    echo
done

if [ "$overall_failed" -gt 0 ]; then
    echo "FAILED: $overall_failed test file(s) had failures"
    exit 1
fi

echo "All test files passed."
