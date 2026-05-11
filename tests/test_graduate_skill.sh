#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/graduate/SKILL.md"

assert_file_contains "$skill_file" "name: graduate"      "skill has name field"
assert_file_contains "$skill_file" "description:"        "skill has description field"
assert_file_contains "$skill_file" "Projects/"           "skill files to Projects/"
assert_file_contains "$skill_file" "graduated_from"      "source idea links back via graduated_from"
assert_file_contains "$skill_file" "type: project"       "skill sets type: project"
assert_file_contains "$skill_file" "## Phases"           "skill scaffolds Phases"
assert_file_contains "$skill_file" "graduated_to"        "source note gets graduated_to backlink"

assert_file_contains "$repo_dir/install.sh"   "graduate" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "graduate" "uninstall.sh removes skill"

print_summary
