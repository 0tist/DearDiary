#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/vault-health/SKILL.md"

assert_file_contains "$skill_file" "name: vault-health"  "skill has name field"
assert_file_contains "$skill_file" "description:"        "skill has description field"
assert_file_contains "$skill_file" "Read-only"           "skill is explicitly read-only"
assert_file_contains "$skill_file" "Orphan notes"        "skill checks orphans"
assert_file_contains "$skill_file" "Inbox backlog"       "skill checks inbox backlog"
assert_file_contains "$skill_file" "Broken wikilinks"    "skill checks broken wikilinks"
assert_file_contains "$skill_file" "Stale frontmatter"   "skill checks stale frontmatter"

assert_file_contains "$repo_dir/install.sh"   "vault-health" "install.sh wires skill"
assert_file_contains "$repo_dir/uninstall.sh" "vault-health" "uninstall.sh removes skill"

print_summary
