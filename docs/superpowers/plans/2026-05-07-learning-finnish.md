# Learning-Finnish Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global Claude Code skill `learning-finnish` that ambiently teaches Finnish during sessions: light Finnish in conversational scaffolding only, with inline glossing and stress-aware quieting; load-bearing content stays English.

**Architecture:** New skill directory `claude/learning-finnish/SKILL.md` symlinked into `~/.claude/skills/learning-finnish/` by `install.sh` (mirroring how aliases and CLAUDE.md are already wired). A one-paragraph pointer in `claude/CLAUDE.md` ensures the skill is discovered at session start. `uninstall.sh` removes the symlink. A new shell test file asserts the wiring.

**Tech Stack:** Bash (install/uninstall/tests), Markdown + YAML frontmatter (skill file), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-07-learning-finnish-design.md`

<!-- end_slide -->

## File Map

**Create:**

- `claude/learning-finnish/SKILL.md` — the skill itself (frontmatter + body)
- `tests/test_learning_finnish_skill.sh` — static checks for the skill wiring

**Modify:**

- `claude/CLAUDE.md` — append a "Learning Finnish ambiently" section that points at the skill
- `install.sh` — add a section that symlinks `claude/learning-finnish/` into `~/.claude/skills/learning-finnish/`
- `uninstall.sh` — add removal logic for that symlink
- `tests/test_claude_rules.sh` — add one assertion that the new pointer lives in CLAUDE.md

Each task below produces an isolated, committable change. Tests come first where practical; they're shell-content assertions, not strict TDD.

<!-- end_slide -->

## Task 1: Write the failing test for the skill file

**Files:**

- Create: `tests/test_learning_finnish_skill.sh`

- [ ] **Step 1: Create the test file**

```bash
cat > /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh <<'EOF'
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
assert_file_contains "$repo_dir/install.sh"   "skills/learning-finnish" "install.sh wires skill symlink"
assert_file_contains "$repo_dir/uninstall.sh" "skills/learning-finnish" "uninstall.sh removes skill symlink"

# 4. CLAUDE.md points at the skill
assert_file_contains "$repo_dir/claude/CLAUDE.md" "learning-finnish" "CLAUDE.md references the skill"

print_summary
EOF
chmod +x /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh`
Expected: every `FAIL` because nothing has been wired yet. The script should still exit cleanly (asserts log a fail, do not abort). The summary should show `Passed: 0` and a non-zero `Failed:`.

- [ ] **Step 3: Commit the failing test**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add tests/test_learning_finnish_skill.sh
git commit -m "test: failing static checks for learning-finnish skill"
```

<!-- end_slide -->

## Task 2: Create the SKILL.md body

**Files:**

- Create: `claude/learning-finnish/SKILL.md`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /home/jayesh0vasudeva/DearDiary/claude/learning-finnish
```

- [ ] **Step 2: Write SKILL.md**

Write to `/home/jayesh0vasudeva/DearDiary/claude/learning-finnish/SKILL.md`:

````markdown
---
name: learning-finnish
description: Use at the start of every conversation to layer light, glossed Finnish into casual conversational moments (greetings, acknowledgments, reactions, sign-offs) while keeping all technical and load-bearing content in English. Drop Finnish entirely if the user signals stress or asks for English only.
---

# Learning Finnish (ambient)

The user is a beginner who wants steady, low-effort Finnish exposure during everyday Claude Code work. Act like a parent gently dropping Finnish into casual moments while the kid does their homework in English. Comprehension of any load-bearing content must stay 100% English — the user must never have to *understand* Finnish to do their job.

## Where Finnish goes (allowed surfaces)

Default dose: 1–3 Finnish bits per reply, not more. Use them in:

- **Greetings / openers** at the start of a session reply
- **Acknowledgments** — got it, one sec, looking, done
- **Small reactions** — nice, weird, ouch, interesting
- **Transitions** — ok, next; and now; by the way
- **Sign-offs** at end-of-turn summaries
- **Occasional simple nouns or time words** in passing prose

## Where Finnish never goes (load-bearing — always English)

- What changed (file paths, function names, diffs)
- Error messages, root-cause explanations, decision rationale
- Code, commands, command output
- Direct technical answers
- Anything inside fenced code blocks or backticks
- Commit messages, PR descriptions, persisted artifacts that other humans will read

If a sentence carries the meaning the user must understand to act, that sentence is English.

## Glossing rule

The user must never be blocked by a Finnish word.

- **First appearance of any non-trivial Finnish word/phrase in a session:** inline gloss in parens. Example: `Selvä (got it), looking at it now.`
- **After first use in the same session:** can appear bare.
- **Always-bare set** (no gloss needed even on first use): `kiitos`, `moi`, `joo`, `ei`, `hei`, `okei`. These are basic enough.
- **Multi-word phrases:** gloss the whole phrase, not word-by-word.
- **No transliteration aids** — Finnish spelling is phonetic; pronunciation guides add noise.

## Volume controls (mid-conversation)

Watch for and respect these signals:

- "less Finnish" / "english only" / "drop the finnish" / "no finnish" → switch to pure English for the rest of the session
- "more Finnish" / "anna mennä" → lean in: greetings + acknowledgments + small reactions in Finnish (always glossed on first use), full sentences where natural
- (no signal) → default light sprinkle, 1–3 bits per reply

These adjustments are session-scoped. Each new session resets to the default.

## Stress check (auto-quiet)

A parent doesn't quiz the kid mid-meltdown.

If the current exchange shows signs of user stress — they hit a bug, something broke, they're frustrated, debugging under time pressure, they curse, they say "ugh" or similar — drop Finnish entirely for that exchange and the next one. Resume the default sprinkle once the situation calms (a successful fix, a tone shift, a new topic).

This is judgment, not a regex. Read the room.

## Phrase pool (curated, ~30–40 items)

Spoken/everyday register, not formal/textbook. Pull from these by function:

**Greetings / sign-offs**
- `Moi` (hi)
- `Hei` (hi)
- `Moikka` (hey)
- `Heippa` (bye / hey)
- `Hyvää huomenta` (good morning)
- `Hyvää iltaa` (good evening)
- `Nähdään` (see you)

**Acknowledgments**
- `Selvä` (got it)
- `Joo` (yeah) — always-bare
- `Okei` (okay) — always-bare
- `Hetki` (one sec)
- `Katsotaan` (let's see)

**Reactions**
- `Hyvä` (good)
- `Hienoa` (great)
- `Outoa` (weird)
- `Harmi` (too bad)
- `Vau` (wow)
- `Ai` (oh)

**Transitions**
- `No niin` (alright then)
- `Eli` (so)
- `Sitten` (then)
- `Ja nyt` (and now)
- `Muuten` (by the way)

**Done / result**
- `Valmis` (ready / done)
- `Onnistui` (succeeded)
- `Toimii` (it works)
- `Korjattu` (fixed)

**Time / quantity**
- `Nyt` (now)
- `Kohta` (soon)
- `Vähän` (a bit)
- `Paljon` (a lot)
- `Vielä` (still / yet)

**Common nouns — used sparingly, never as the carrier of meaning**
- `Koodi` (code)
- `Tiedosto` (file)
- `Virhe` (error)
- `Testi` (test)

## Anti-examples

These are the failure modes to avoid.

**Bad — load-bearing in Finnish:**
> Found the bug — se johtui väärästä polusta tiedostossa `auth.py`.

**Good — Finnish in scaffolding only:**
> Selvä (got it). Found the bug: wrong path in `auth.py:42`.

**Bad — over-saturating with no gloss:**
> Hei! Katsoin koodisi ja huomasin että siinä on virhe rivillä 42.

**Good — sprinkle with first-use gloss:**
> Hei! Looked at the code — there's an error on line 42.

**Bad — ignoring stress signal:**
> *(user)* ugh nothing is working
> *(reply)* Harmi (too bad)! Katsotaan (let's see) what's happening...

**Good — drop Finnish during stress:**
> *(user)* ugh nothing is working
> *(reply)* Looking at it now. Can you paste the last error?

## Non-goals

- Stateful tracking of what the user has been exposed to
- Spaced-repetition word selection
- Pronunciation guides or audio
- Grammar lessons (case endings, conjugation) unless explicitly asked
- Finnish in commit messages, PR descriptions, code comments, or anything that persists past the session
````

- [ ] **Step 3: Run the test and confirm skill-file checks now pass**

Run: `bash /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh`
Expected: the six skill-content assertions pass; the install/uninstall/CLAUDE.md assertions still fail.

- [ ] **Step 4: Commit**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add claude/learning-finnish/SKILL.md
git commit -m "feat: add learning-finnish SKILL.md (skill body, not yet wired)"
```

<!-- end_slide -->

## Task 3: Add CLAUDE.md pointer

**Files:**

- Modify: `claude/CLAUDE.md` (append a new section after the "Theme & viewing" section, before "When in plan mode")

- [ ] **Step 1: Append the new section**

Use Edit on `/home/jayesh0vasudeva/DearDiary/claude/CLAUDE.md`. Find the existing line:

```
## When in plan mode
```

Replace it with the new section followed by the original heading:

```
## Learning Finnish ambiently

The user is learning Finnish. At the start of every session, invoke the
`learning-finnish` skill. The skill defines exactly where Finnish is
allowed (greetings, acknowledgments, reactions, sign-offs), where it is
forbidden (load-bearing content, code, errors, decisions), how to gloss,
how to respond to mid-conversation volume signals, and when to drop
Finnish entirely (user stress).

This is a global behavior: it applies to every session unless a
project-level `CLAUDE.md` overrides it.

## When in plan mode
```

- [ ] **Step 2: Run test_claude_rules.sh and test_learning_finnish_skill.sh**

```bash
bash /home/jayesh0vasudeva/DearDiary/tests/test_claude_rules.sh
bash /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh
```

Expected: `test_claude_rules.sh` still all-pass (none of its existing assertions broke). `test_learning_finnish_skill.sh` now also passes the CLAUDE.md assertion. Install/uninstall asserts still fail.

- [ ] **Step 3: Add the pointer assertion to test_claude_rules.sh too**

Edit `/home/jayesh0vasudeva/DearDiary/tests/test_claude_rules.sh`. Find:

```bash
assert_file_contains "$rules_file" "slides: true"         "opt-in tag documented"
```

Add directly after it:

```bash
assert_file_contains "$rules_file" "learning-finnish"     "rules file points at learning-finnish skill"
```

- [ ] **Step 4: Re-run test_claude_rules.sh, confirm new assertion passes**

```bash
bash /home/jayesh0vasudeva/DearDiary/tests/test_claude_rules.sh
```

Expected: all assertions pass.

- [ ] **Step 5: Commit**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add claude/CLAUDE.md tests/test_claude_rules.sh
git commit -m "feat(claude): add learning-finnish pointer to global rules"
```

<!-- end_slide -->

## Task 4: Wire install.sh

**Files:**

- Modify: `install.sh` (add a new section between `1d.` and `# 2. Merge settings.json`)

- [ ] **Step 1: Add the skill-symlink block**

Edit `/home/jayesh0vasudeva/DearDiary/install.sh`. Find the line:

```bash
ln -sfn "$REPO_DIR/claude/CLAUDE.md" "$GLOBAL_RULES"
echo "    linked $GLOBAL_RULES -> $REPO_DIR/claude/CLAUDE.md"
```

Replace with the same two lines plus a new `1e.` section appended:

```bash
ln -sfn "$REPO_DIR/claude/CLAUDE.md" "$GLOBAL_RULES"
echo "    linked $GLOBAL_RULES -> $REPO_DIR/claude/CLAUDE.md"

# 1e. Symlink skills directories into ~/.claude/skills/<name>/
SKILLS_DIR="$CLAUDE_DIR/skills"
mkdir -p "$SKILLS_DIR"
for skill in learning-finnish; do
    src="$REPO_DIR/claude/$skill"
    dst="$SKILLS_DIR/$skill"
    if [ ! -d "$src" ]; then
        echo "    SKIP: $src missing"
        continue
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        backup="$dst.pre-deardiary-install-backup"
        mv "$dst" "$backup"
        echo "    backed up existing $dst -> $backup"
    fi
    ln -sfn "$src" "$dst"
    echo "    linked $dst -> $src"
done
```

- [ ] **Step 2: Run the skill test and confirm install.sh assertion now passes**

```bash
bash /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh
```

Expected: install assertion passes. Uninstall assertion still fails.

- [ ] **Step 3: Commit**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add install.sh
git commit -m "feat(install): symlink claude/learning-finnish into ~/.claude/skills/"
```

<!-- end_slide -->

## Task 5: Wire uninstall.sh

**Files:**

- Modify: `uninstall.sh` (insert a new block after the global rules removal, before settings.json cleanup)

- [ ] **Step 1: Add the skill-removal block**

Edit `/home/jayesh0vasudeva/DearDiary/uninstall.sh`. Find:

```bash
# Remove global Claude rules symlink (only if it points at our file)
target="$CLAUDE_DIR/CLAUDE.md"
if [ -L "$target" ]; then
    rm -f "$target"
    echo "    removed symlink $target"
elif [ -e "$target" ]; then
    echo "    WARNING: $target exists and is not a symlink — leaving in place"
fi
```

Insert directly after that block (before `# Strip hook entries`):

```bash
# Remove skill symlinks (only if they point at our directories)
SKILLS_DIR="$CLAUDE_DIR/skills"
for skill in learning-finnish; do
    target="$SKILLS_DIR/$skill"
    if [ -L "$target" ]; then
        rm -f "$target"
        echo "    removed symlink $target"
    elif [ -e "$target" ]; then
        echo "    WARNING: $target exists and is not a symlink — leaving in place"
    fi
done
# Remove the skills/ dir if it's now empty
if [ -d "$SKILLS_DIR" ] && [ -z "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
    rmdir "$SKILLS_DIR"
fi
```

- [ ] **Step 2: Run the skill test, confirm all assertions now pass**

```bash
bash /home/jayesh0vasudeva/DearDiary/tests/test_learning_finnish_skill.sh
```

Expected: every assertion passes; summary shows `Failed: 0`.

- [ ] **Step 3: Commit**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add uninstall.sh
git commit -m "feat(uninstall): remove learning-finnish skill symlink"
```

<!-- end_slide -->

## Task 6: Wire the new test file into the runner

**Files:**

- Modify: `tests/run.sh` (only if it lists tests explicitly; otherwise no-op)

- [ ] **Step 1: Inspect the runner**

```bash
cat /home/jayesh0vasudeva/DearDiary/tests/run.sh
```

If it auto-discovers `test_*.sh` (via a glob), no change is needed — skip to Step 3.

If it lists tests explicitly, add `test_learning_finnish_skill.sh` to the list, in alphabetical position.

- [ ] **Step 2: Run the full suite**

```bash
bash /home/jayesh0vasudeva/DearDiary/tests/run.sh
```

Expected: all tests pass, including the new one.

- [ ] **Step 3: Commit (only if Step 1 required a change)**

```bash
cd /home/jayesh0vasudeva/DearDiary
git add tests/run.sh
git commit -m "test: include learning-finnish skill checks in runner"
```

If no change was needed, skip the commit.

<!-- end_slide -->

## Task 7: End-to-end install + manual verification

**Files:** none (this task runs the installer and checks the live system)

- [ ] **Step 1: Run installer**

```bash
cd /home/jayesh0vasudeva/DearDiary
./install.sh
```

Expected output includes a line like:

```
    linked /home/jayesh0vasudeva/.claude/skills/learning-finnish -> /home/jayesh0vasudeva/DearDiary/claude/learning-finnish
```

- [ ] **Step 2: Verify the symlink resolves to the SKILL.md**

```bash
readlink -f /home/jayesh0vasudeva/.claude/skills/learning-finnish/SKILL.md
```

Expected: `/home/jayesh0vasudeva/DearDiary/claude/learning-finnish/SKILL.md`

- [ ] **Step 3: Verify CLAUDE.md is updated and active**

```bash
grep -c learning-finnish /home/jayesh0vasudeva/.claude/CLAUDE.md
```

Expected: at least `1`.

- [ ] **Step 4: Tell the user to restart Claude Code**

Behavioral validation (sprinkled greetings, glossing, volume control, stress quieting) requires a fresh Claude Code session that picks up the new global rules and skill.

The user runs:

- New session, expect: a Finnish greeting on first reply, with gloss
- Ask any technical question, expect: pure-English answer
- Say "less finnish", expect: English-only for rest of session
- Type `ugh` or simulate stress, expect: Finnish drops for the exchange

Document any drift back into the skill file via PR or follow-up.

- [ ] **Step 5: Verify uninstall is reversible (in a sandbox, optional)**

Optional sanity: confirm `./uninstall.sh` removes the skill symlink, then `./install.sh` re-adds it. Run only if comfortable resetting your local state.

```bash
./uninstall.sh
ls -la /home/jayesh0vasudeva/.claude/skills/ 2>/dev/null   # learning-finnish gone
./install.sh
ls -la /home/jayesh0vasudeva/.claude/skills/learning-finnish/   # back
```

<!-- end_slide -->

## Summary

- **6–7 tasks**, each ending in a commit; total work ~30–45 min
- **TDD-style:** failing test file lands first (Task 1), then code makes it pass piece by piece
- **Files touched:** 1 new skill file, 1 new test, 4 modifications (CLAUDE.md, install.sh, uninstall.sh, test_claude_rules.sh, possibly run.sh)
- **No new dependencies** — all bash/markdown
- **Reversible:** `uninstall.sh` cleanly removes the wiring
- **Final gate:** end-to-end install + a fresh Claude Code session, where the user observes the behavior in the wild
