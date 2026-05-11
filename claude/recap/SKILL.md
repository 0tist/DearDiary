---
name: recap
description: Apply when the user asks for a summary, recap, retrospective, or roundup of a time period — e.g. "what did I do this week", "recap the last month", "summarize today", "what happened in May", "weekly recap". Reads vault notes from the period and produces a structured summary in chat.
---

# Recap

Period summary over the user's vault. Reads notes from a time window,
groups them by folder, and produces a structured recap.

## When to trigger

Explicit request from the user with a time-period word:

- Today / yesterday / this week / last week / this month / last month
- A specific date range ("between May 1 and May 10")
- A folder-scoped period ("recap my Ideas/ this month")

If the user just asks "what's in the vault" with no time scope, that's a
different ask — point them at the `vault-health` skill instead.

## What to do

1. Resolve the period to a concrete date range. Default to local timezone.
2. Scan vault notes whose `date:` frontmatter falls in the range. If a
   note has no `date:`, fall back to filesystem mtime.
3. Group by folder (`Ideas/`, `Projects/`, `Decisions/`, `Daily/`,
   `Research/`, anything else).
4. For each group:
   - Count the notes
   - List the most notable 3-7 by title with a one-line summary each
     (use the `## For future Claude` preamble if present, otherwise the
     first non-empty line of the body)
5. Surface cross-cutting patterns (optional, only if obvious):
   - Recurring `[[wikilinked entities]]` across multiple notes
   - Decisions that affected multiple projects
   - Open questions that came up more than once

## Output

Print the recap directly in chat as markdown. Format:

```
# Recap — <period label> (<start> to <end>)

## Ideas (N captured)
- **<title>** — <one-line summary>
- ...

## Decisions (N made)
- **<title>** — <one-line summary>
- ...

## Projects touched (N)
- ...

[... other folders with content in this period ...]

## Patterns
- <recurring theme>: <which notes>
- <open question>: came up in <which notes>

## Stats
- Total notes in period: N
- Top wikilinked entities: [[X]] (N), [[Y]] (N), ...
```

## Optional save

If the user asks to "save the recap" or "file this", write it to
`{{DIARY_ROOT}}/Daily/<YYYY-MM-DD>-recap-<period>.md` with AI-first
frontmatter:

```yaml
---
type: recap
date: <ISO timestamp>
period: <day|week|month|custom>
range: <start> .. <end>
tags: [recap]
ai-first: true
routed_to: Daily
---
```

Body: the report exactly as printed.

## Rules

- Read-only by default. Only write to the vault if the user explicitly
  asks to save.
- If the period has zero notes, say so in one line — don't manufacture
  content.
- Don't summarize the audit log (`.diary-events.log`) — that's
  infrastructure noise, not user content.
