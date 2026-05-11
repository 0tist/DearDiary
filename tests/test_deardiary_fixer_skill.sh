#!/usr/bin/env bash
# Static checks for the deardiary-fixer skill wiring.

set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/deardiary-fixer/SKILL.md"

# 1. Skill file exists with frontmatter
assert_file_contains "$skill_file" "name: deardiary-fixer" "skill has name field"
assert_file_contains "$skill_file" "description:"         "skill has description field"

# 2. Skill body covers the load-bearing rules
assert_file_contains "$skill_file" "diary-fix/"             "skill defines machine-generated branch prefix"
assert_file_contains "$skill_file" "gh pr create"           "skill opens PRs via gh CLI"
assert_file_contains "$skill_file" "git -C"                 "skill uses git -C to avoid cd (bash allowlist)"
assert_file_contains "$skill_file" "NEVER push to"           "skill forbids pushing to main directly"
assert_file_contains "$skill_file" "tasks/"                 "skill files entries under tasks/"

# 3. Diary processor allowlist permits git + gh
assert_file_contains "$repo_dir/scripts/diary-process.sh" "Bash(git:*)" "diary-process.sh allows git"
assert_file_contains "$repo_dir/scripts/diary-process.sh" "Bash(gh:*)"  "diary-process.sh allows gh"

# 4. install.sh + uninstall.sh wire this skill alongside the others
assert_file_contains "$repo_dir/install.sh"   "deardiary-fixer" "install.sh wires the skill symlink"
assert_file_contains "$repo_dir/uninstall.sh" "deardiary-fixer" "uninstall.sh removes the skill symlink"

# 5. Diary prompt invites skills to participate
assert_file_contains "$repo_dir/scripts/lib/diary-prompt.txt" "{{SKILLS}}" "diary prompt has {{SKILLS}} placeholder"
assert_file_contains "$repo_dir/scripts/diary-process.sh"     "SKILLS_DIR" "diary processor concatenates SKILL.md files"

print_summary
