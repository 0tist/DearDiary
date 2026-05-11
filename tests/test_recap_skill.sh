#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/recap/SKILL.md"

assert_file_contains "$skill_file" "name: recap"      "skill has name field"
assert_file_contains "$skill_file" "description:"     "skill has description field"
assert_file_contains "$skill_file" "time period"      "skill triggers on time-period requests"
assert_file_contains "$skill_file" "Group by folder"  "skill groups output by folder"
assert_file_contains "$skill_file" "Read-only"        "skill is read-only by default"

assert_file_contains "$repo_dir/install.sh"   "recap" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "recap" "uninstall.sh removes skill"

print_summary
