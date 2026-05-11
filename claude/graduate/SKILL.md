---
name: graduate
description: Apply when the user wants to promote an idea fragment into a real project — phrases like "let's actually do this", "graduate this idea", "this is a real project now", "make this a project", or when pointing at a specific `Ideas/<id>.md` note and asking for a project spec. Reads the source idea + related vault context, creates a Projects/<title>.md note with goals/phases/tasks, and tags the original as graduated.
---

# Graduate

Promote an `Ideas/` entry from a thought into a structured project. The
output is a `Projects/<title>.md` note with the scaffolding the user
needs to actually start work.

## When to trigger

Explicit ask:

- "Let's actually do this" / "graduate this idea" / "make this a project"
- Direct pointer: "turn `Ideas/<id>.md` into a project"
- Following an `idea-evaluator` Estimate that shows medium/high potential
  and the user says "ok let's do it"

If the user is just musing about an idea (no commitment), DON'T trigger.

## What to do

1. **Identify the source idea.**
   - If the user pointed at a specific note, use that.
   - Otherwise, scan recent `Ideas/` for the most likely match based on
     the user's phrasing.
   - If ambiguous, ASK ONCE which idea — don't guess.

2. **Gather context.** Read:
   - The source idea note (including any `## Estimate` section from
     `idea-evaluator`).
   - Any `Ideas/` or `Daily/` notes with overlapping `[[wikilinks]]`.

3. **Create the project note** at
   `{{DIARY_ROOT}}/Projects/<short-kebab-title>.md`:

   ```markdown
   ---
   type: project
   date: <ISO timestamp now>
   status: active
   graduated_from: Ideas/<source-id>.md
   tags: [<inherited from source + project>]
   ai-first: true
   routed_to: Projects
   ---

   ## For future Claude

   <2–3 lines: what this project is, who it's for, what success looks like>

   ## Goal

   <one-line outcome statement>

   ## Context

   <why now? what changed from idea to commitment? if the source note has
   an Estimate, summarize Cost/Effort/Potential in one line>

   ## Phases

   1. <phase 1 — concrete, scoped>
   2. <phase 2>
   3. <phase 3>

   ## Open questions

   - <thing the user should figure out before phase N starts>
   - ...

   ## Source

   - [[Ideas/<source-id>]]
   - Related: [[<other notes if any>]]
   ```

   Phases should be 3–5 concrete steps, not bureaucratic categories like
   "Discovery / Planning / Execution". Each phase should be something the
   user could schedule a working session on.

4. **Update the source idea note.** Add to its frontmatter:
   ```
   status: graduated
   graduated_to: Projects/<short-kebab-title>.md
   ```
   Don't delete the source — it's the origin story.

5. **Append a TODO.** Add to `## Active` in {{TODO_FILE}}:
   `- [project] kick off [[<short-kebab-title>]]: <phase 1 in 5 words>`

## Output

One-line summary to stdout:

```
graduated <source-id> -> Projects/<title>.md
```

## Rules

- Don't pad. If the idea is small, the project note can be 20 lines.
- Don't invent phases that aren't grounded in the source idea. If you
  don't know what phase 3 looks like, say so in Open Questions instead
  of bullshitting a phase.
- If the source idea has `## Estimate` saying potential is low, RAISE
  this gently in `## Context` — "the evaluator estimated low potential;
  the user is graduating anyway." Don't refuse, just note it for
  future-Claude.
