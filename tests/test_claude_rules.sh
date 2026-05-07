#!/usr/bin/env bash
# Verify the global Claude rules file exists with the expected content,
# and that install.sh / uninstall.sh wire it up correctly.

set -u
source "$(dirname "$0")/lib.sh"

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
rules_file="$repo_dir/claude/CLAUDE.md"

# Rules file exists and has the three rules
assert_file_contains "$rules_file" "presenterm slideshow" "rules file targets presenterm"
assert_file_contains "$rules_file" "Slide boundaries"     "rule 1: slide boundaries documented"
assert_file_contains "$rules_file" "mermaid"              "rule 2: mermaid diagrams"
assert_file_contains "$rules_file" "100 words"            "rule 3: 100-word opt-in cap"
assert_file_contains "$rules_file" "slides: true"         "opt-in tag documented"
assert_file_contains "$rules_file" "learning-finnish"     "rules file points at learning-finnish skill"

# install.sh and uninstall.sh reference the rules symlink
assert_file_contains "$repo_dir/install.sh"   "CLAUDE.md" "install.sh wires CLAUDE.md"
assert_file_contains "$repo_dir/uninstall.sh" "CLAUDE.md" "uninstall.sh removes CLAUDE.md"
assert_file_contains "$repo_dir/install.sh"   "pre-deardiary-install-backup" \
    "install.sh backs up existing non-symlink CLAUDE.md"

print_summary
