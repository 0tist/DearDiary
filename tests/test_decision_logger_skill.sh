#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/decision-logger/SKILL.md"

assert_file_contains "$skill_file" "name: decision-logger"        "skill has name field"
assert_file_contains "$skill_file" "description:"                 "skill has description field"
assert_file_contains "$skill_file" "Decisions/"                   "skill files to Decisions/"
assert_file_contains "$skill_file" "type: decision"               "skill sets type: decision in frontmatter"
assert_file_contains "$skill_file" "## For future Claude"         "skill keeps AI-first preamble"
assert_file_contains "$skill_file" "ADR-lite"                     "skill describes ADR-lite shape"

assert_file_contains "$repo_dir/install.sh"   "decision-logger" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "decision-logger" "uninstall.sh removes skill"

print_summary
