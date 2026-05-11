#!/usr/bin/env bash
# Static checks for the idea-evaluator skill wiring.

set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill_file="$repo_dir/claude/idea-evaluator/SKILL.md"

# 1. Skill file exists with frontmatter
assert_file_contains "$skill_file" "name: idea-evaluator" "skill has name field"
assert_file_contains "$skill_file" "description:"        "skill has description field"

# 2. Skill body covers all three estimate dimensions + ideas-only trigger
assert_file_contains "$skill_file" "ideas/"     "skill triggers on ideas/ routing"
assert_file_contains "$skill_file" "Cost"       "skill names the Cost dimension"
assert_file_contains "$skill_file" "Effort"     "skill names the Effort dimension"
assert_file_contains "$skill_file" "Potential"  "skill names the Potential dimension"
assert_file_contains "$skill_file" "## Estimate" "skill appends an Estimate section to the body"

# 3. install.sh + uninstall.sh wire this skill alongside the others
assert_file_contains "$repo_dir/install.sh"   "idea-evaluator" "install.sh wires the skill symlink"
assert_file_contains "$repo_dir/uninstall.sh" "idea-evaluator" "uninstall.sh removes the skill symlink"

# 4. Skill is reachable through the diary processor's SKILL.md concatenation
assert_file_contains "$repo_dir/scripts/diary-process.sh" "SKILL.md" "diary processor reads SKILL.md files"

print_summary
