# Global Claude Code instructions for jayesh

These rules apply to **every** Claude Code session unless overridden by a
project-level `CLAUDE.md`. They exist so that long-form artifacts (plans,
specs, design docs, the live TODO) are immediately viewable as a
[presenterm](https://github.com/mfontanini/presenterm) slideshow without
post-processing.

The `todo` alias (`~/DearDiary/scripts/todo-presenterm.sh`) and direct
`presenterm <file>.md` are the two entry points — write your markdown so both
work.

## Plan / spec files are presenterm slideshows

Whenever you create or edit a plan, spec, design doc, or any long-form
markdown intended for review (paths like `docs/**/plans/*.md`,
`docs/**/specs/*.md`, `~/.claude/plans/*.md`, anything the user calls a
"plan"), structure it as a presenterm deck:

- **Slide boundaries:** put `<!-- end_slide -->` between sections. This is
  presenterm's canonical separator. Don't use bare `---` thematic breaks —
  they only act as separators if the file's front matter sets
  `options.end_slide_shorthand: true`, which we don't enable by default.
- **One topic per slide.** A new `## ` heading is almost always a new slide.
- **Hard cap: ~200 words per slide.** If a slide grows past this, split it.
  Two short slides beat one wall of text. Bullet lists, short paragraphs, a
  diagram, and a single takeaway — that's a good slide.
- **First slide is the title.** Use a single `# Title`, an italicized
  subtitle, and nothing else. No body content competing with the title.
- **Last slide summarizes** with the key decisions/next steps in 3–5 bullets.

### Tight-slides opt-in: `<!-- comment slides: true -->` marker

When a plan file has this marker near the top, two things change:

1. **Tighter word cap.** Each slide must stay ≤100 words (vs. the default
   ~200). Split aggressively into multiple `## ` (or `### `) sub-slides.
2. **`---` becomes a valid separator.** Emit
   `options.end_slide_shorthand: true` in the frontmatter block, then you
   may use bare `---` thematic breaks as slide markers in addition to
   `<!-- end_slide -->`.

Example:

```yaml
---
options:
  end_slide_shorthand: true
---
```
```
<!-- comment slides: true -->
```

Why this exact shape: presenterm rejects unknown frontmatter keys, and it
parses every `<!-- X ... -->` as a directive where `X` must be a known
command (`end_slide`, `pause`, `comment`, `speaker_note`, …). `comment` is
the only no-op variant — anything else hard-fails the deck. Don't fight
the parser.

Untagged plans keep the default 200-word cap and require `<!-- end_slide -->`.

Example skeleton:

````markdown
# Auth Rewrite Plan

_2026-05-06 · jayesh · scope: backend only_

<!-- end_slide -->

## Why

- Legal flagged session-token storage as non-compliant
- Current middleware blocks the planned SSO migration
- Cost of doing nothing: hard deadline 2026-Q3

<!-- end_slide -->

## Architecture

```
┌────────┐     ┌─────────┐     ┌──────────────┐     ┌────────────┐
│        │     │         │     │              │     │            │
│ Client ├────►│ Gateway ├────►│ Auth Service ├────►│    KMS     │
│        │     │         │     │              │     │            │
└────────┘     └─────────┘     └───────┬──────┘     └────────────┘
                                       │
                                       ▼
                                ┌────────────┐
                                │ Session DB │
                                └────────────┘
```

<!-- end_slide -->

## Rollout

1. Land schema migration (week 1)
2. Dual-write phase (week 2–3)
3. Cutover behind feature flag (week 4)
4. Remove old code path (week 5)
````

## Diagrams: pre-render to ASCII

`mermaid +render` via `mmdc` is unreliable in this presenterm setup, so
diagrams in slide source files are **always ASCII art in a plain fenced
code block** — never `mermaid` blocks with `+render`.

Workflow when adding a diagram:

1. Sketch in mermaid syntax in your head or a scratch file.
2. Pipe through `mmd --ascii -w <width>` to render to ASCII art.
3. Paste the ASCII output into a plain fenced code block (no language tag).

Example shell invocation:

```bash
echo 'flowchart TD
  A[Input] --> B{Validate}
  B -->|ok| C[Process]
  B -->|fail| D[Reject]' | mmd --ascii -w 60
```

Resulting slide content (paste verbatim into the deck):

```
┌──────────┐
│  Input   │
└─────┬────┘
      │
      ▼
┌──────────┐
│ Validate ├───fail────┐
└─────┬────┘           │
      │                │
     ok                │
      │                ▼
      ▼          ┌────────┐
┌──────────┐     │ Reject │
│ Process  │     └────────┘
└──────────┘
```

`mmd --ascii` (uses `mermaid-ascii` under the hood) panics on some edge
configurations — cycles, dense crossings. When that happens, hand-draw
the ASCII art using box-drawing characters (`┌─┐│└┘├┤┬┴┼►▼◄▲`). Either
way, the slide ends up as a plain code block.

- **Don't pre-render to PNG** and embed images. Slide files stay
  human-editable.
- Mermaid syntax types worth knowing as a sketching language:
  `flowchart`/`graph`, `sequenceDiagram`, `classDiagram`, `erDiagram`,
  `stateDiagram`, `gantt`, `gitGraph`.

## Quirks to avoid

Presenterm's parser is stricter than vanilla CommonMark. Things to escape or
avoid in slide content:

- **Bare `<word>` patterns** are read as HTML tags and fail parsing.
  Backslash-escape them: `\<session_id\>` instead of `<session_id>`. Or wrap
  in a code span: `` `<session_id>` ``.
- **Long unbroken lines** can overflow the slide. Break at sentence
  boundaries.
- **Tables** render fine but don't auto-wrap — keep cells short.
- **Fenced code blocks inside list items fail to parse.** Pull ` ```...``` ` to root level, not indented under a bullet.

## When *not* to use this format

- Short README sections, error messages, command help — plain markdown is
  fine.
- Code review comments, commit messages — keep terse, no slide structure.
- One-off chat replies — only use slide structure when the user explicitly
  asks for a plan/spec or when the artifact will live as a `*.md` plan file.

If unsure whether a doc should be a presenterm deck: if it has more than two
`## ` sections **and** is named like a plan/spec/design doc, yes.

## Theme & viewing

Default presenterm theme: `gruvbox-dark` (set in
`~/.config/presenterm/config.yaml`). Override per-invocation with
`PRESENTERM_THEME=<name> presenterm <file>` or, for the live TODO,
`PRESENTERM_THEME=<name> todo`.

## The DearDiary vault layout

`~/DearDiary/` is both DearDiary's data directory AND an Obsidian vault
(opened as a folder-vault). The
[obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain)
skill (when installed by the user separately) runs nightly agents over this
same path and expects a specific top-level layout: `Ideas/`, `Projects/`,
`People/`, `Decisions/`, `Daily/`, `Research/`. When filing into the diary
from any context (skills, scripts, ad-hoc invocations), prefer these
PascalCase folders. Use AI-first note format — frontmatter with `type`,
`date`, `tags`, `ai-first: true`, and a `## For future Claude` preamble —
so the vault stays consumable by obsidian-second-brain's agents.

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

- Plan must be presented in the preseterm deck format at first save, not retrofitted later.
- If the plan is technical and requires a thorough insight and feedback from the orchestrator follow the walking-through-plans skill to finish up your plan, make these edits before the final save as well. This must be the last step before you deliver the plan to orchestrator.
- After every save of the plan file (initial save AND each subsequent edit) to `~/.claude/plans/<slug>.md`, also (re)write `/tmp/<slug>` — an executable shell script (`chmod +x`) whose body is `#!/bin/bash` then `exec presenterm "<abs path of the plan file>"`. This gives the user a per-plan ephemeral entry point keyed off the plan filename: they type `/tmp/<slug>` from any shell to render that specific plan, and the `/tmp` location ensures the entry points clear on reboot while the plan files themselves persist under `~/.claude/plans/`. Always overwrite without asking — the script body is deterministic from the plan path.
