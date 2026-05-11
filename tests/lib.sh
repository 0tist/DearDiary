#!/usr/bin/env bash
# Shared test helpers. Sourced by each test_*.sh file.

set -u

# Colors for output
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}  PASS${NC} ${msg:-assert_eq}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}  FAIL${NC} ${msg:-assert_eq}"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}  PASS${NC} ${msg:-assert_contains}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}  FAIL${NC} ${msg:-assert_contains}"
        echo "    looking for: $needle"
        echo "    in:          $haystack"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-}"
    assert_contains "$(cat "$file" 2>/dev/null || echo)" "$needle" "$msg"
}

# Create a temp workspace and register cleanup on script EXIT in the caller's shell.
# Usage: setup_tmp tmp    # sets $tmp to a new temp dir, cleans up when test script exits
# (Avoids `local -n` so this works on macOS' default bash 3.2.)
setup_tmp() {
    local _name="$1"
    local _dir
    _dir=$(mktemp -d)
    eval "$_name=\"\$_dir\""
    # shellcheck disable=SC2064
    trap "rm -rf '$_dir'" EXIT
}

# Build a fake `claude` binary that echoes the file at $1 and put it first on PATH.
# Returns the PATH-prefixed dir. Caller must export PATH.
make_fake_claude() {
    local tmpdir="$1" output_file="$2"
    local bin="$tmpdir/bin"
    mkdir -p "$bin"
    cat > "$bin/claude" <<EOF
#!/usr/bin/env bash
# Fake claude CLI for tests. Ignores all args, just outputs the fixture.
cat "$output_file"
EOF
    chmod +x "$bin/claude"
    echo "$bin"
}

# Build a fake `claude` binary that exec's an arbitrary script. Useful when
# the real claude would do file I/O via tools (Write/Edit/mv) — the script
# can simulate those side effects.
# The script runs with the same args claude was called with.
make_fake_claude_script() {
    local tmpdir="$1" script_path="$2"
    local bin="$tmpdir/bin"
    mkdir -p "$bin"
    cat > "$bin/claude" <<EOF
#!/usr/bin/env bash
exec "$script_path" "\$@"
EOF
    chmod +x "$bin/claude"
    echo "$bin"
}

print_summary() {
    echo
    echo "----------------------------------------"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo "----------------------------------------"
    [ "$TESTS_FAILED" -eq 0 ]
}
