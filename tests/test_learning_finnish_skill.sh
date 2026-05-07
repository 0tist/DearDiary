#!/usr/bin/env bash
# Static checks for the learning-finnish skill wiring.

set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/learning-finnish/SKILL.md"

# 1. Skill file exists with frontmatter
assert_file_contains "$skill_file" "name: learning-finnish"        "skill has name field"
assert_file_contains "$skill_file" "description:"                  "skill has description field"

# 2. Skill body covers the core rules
assert_file_contains "$skill_file" "load-bearing"                  "skill names the load-bearing-stays-english rule"
assert_file_contains "$skill_file" "gloss"                         "skill describes inline glossing"
assert_file_contains "$skill_file" "less Finnish"                  "skill teaches the less-finnish volume control"
assert_file_contains "$skill_file" "stress"                        "skill describes the stress auto-quiet"
assert_file_contains "$skill_file" "kiitos"                        "skill includes the always-bare set"

# 3. install.sh and uninstall.sh wire the skill symlink
assert_file_contains "$repo_dir/install.sh"   "learning-finnish" "install.sh wires skill symlink"
assert_file_contains "$repo_dir/install.sh"   "SKILLS_DIR"       "install.sh defines skills dir"
assert_file_contains "$repo_dir/uninstall.sh" "learning-finnish" "uninstall.sh removes skill symlink"
assert_file_contains "$repo_dir/uninstall.sh" "SKILLS_DIR"       "uninstall.sh references skills dir"

# 4. CLAUDE.md points at the skill
assert_file_contains "$repo_dir/claude/CLAUDE.md" "learning-finnish" "CLAUDE.md references the skill"

print_summary
