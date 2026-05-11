#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/challenge/SKILL.md"

assert_file_contains "$skill_file" "name: challenge"     "skill has name field"
assert_file_contains "$skill_file" "description:"        "skill has description field"
assert_file_contains "$skill_file" "Past failures"       "skill looks for past failures"
assert_file_contains "$skill_file" "Reversed decisions"  "skill looks for reversed decisions"
assert_file_contains "$skill_file" "Read-only"           "skill is read-only"
assert_file_contains "$skill_file" "Quote them"          "skill quotes the user verbatim"

assert_file_contains "$repo_dir/install.sh"   "challenge" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "challenge" "uninstall.sh removes skill"

print_summary
