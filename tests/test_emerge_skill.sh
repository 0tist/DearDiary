#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/emerge/SKILL.md"

assert_file_contains "$skill_file" "name: emerge"          "skill has name field"
assert_file_contains "$skill_file" "description:"          "skill has description field"
assert_file_contains "$skill_file" "Recurring entities"    "skill detects recurring entities"
assert_file_contains "$skill_file" "Open questions"        "skill detects recurring open questions"
assert_file_contains "$skill_file" "30 days"               "skill defaults to 30-day window"
assert_file_contains "$skill_file" "Read-only"             "skill is read-only"
assert_file_contains "$skill_file" "Don't fish"            "skill avoids manufactured patterns"

assert_file_contains "$repo_dir/install.sh"   "emerge" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "emerge" "uninstall.sh removes skill"

print_summary
