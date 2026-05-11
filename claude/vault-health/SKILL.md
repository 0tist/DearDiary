---
name: vault-health
description: Apply when the user asks for a vault health check, audit, or report — e.g. "what's stale", "any contradictions in the vault", "audit DearDiary", "vault health", "what's rotting in here". Read-only scan that produces a grouped report. Never modifies notes.
---

# Vault Health

Read-only scan of `~/DearDiary/` (or the user's vault root). Produces a
report grouped by severity. Doesn't fix anything — only surfaces issues
so the user can decide.

## When to trigger

The user explicitly asks for an audit, health check, or "what's wrong with
the vault". Don't run unprompted; this skill produces a long report, and
running it as a side-effect of a casual mention would be noise.

## What to check (in order)

1. **Inbox backlog.** Files in `diary/inbox/` older than a few hours.
   These are entries the cron hasn't processed yet — could mean
   `diary-process.sh` is broken or the launchd job isn't firing.

2. **Orphan notes.** Notes with NO `[[wikilinks]]` pointing in (nothing
   references them) AND NO outbound `[[wikilinks]]`. They're floating;
   future-Claude can't find them through the link graph.

3. **Stale frontmatter.** Notes missing `type` / `date` / `ai-first: true`
   in frontmatter, or notes without a `## For future Claude` preamble.
   Probably created before the AI-first convention landed, or written by
   hand without following it.

4. **Broken wikilinks.** `[[X]]` references where target file doesn't
   exist anywhere in the vault. Could be typos or notes that got deleted.

5. **Lowercase folders.** Any top-level folder that ISN'T PascalCase.
   These are legacy from before the canonical folders convention; flag
   for migration.

6. **Stale claims.** Notes containing recency markers `(as of YYYY-MM-DD)`
   where the date is more than 6 months old. Flag for re-verification.

7. **Contradictions** (light pass — full reconcile is a separate job).
   Notes about the same `[[entity]]` that state opposing facts in their
   `## For future Claude` preamble. Quick scan only; don't deep-dive.

8. **Processed/ size.** Number of files in `diary/processed/`. Not an
   issue per se — but useful baseline ("you've captured N entries").

## Output

Print a markdown report directly in the conversation. Group by severity:

```
# Vault health report — <today's date>

## Critical (likely broken)
- <issue>: <count> instances — <example>

## Warnings (worth a look)
- <issue>: <count> instances — <example>

## Info (just so you know)
- <issue>: <count> instances — <example>

## Stats
- Total notes: N
- By folder: Ideas N, Projects N, ...
- Captures processed (lifetime): N
```

Don't write the report to a vault file unless the user asks. This is for
quick triage in chat.

## Rules

- Read-only. Never modify, move, or delete notes.
- If a check is going to scan more than ~500 files, print a one-line
  summary instead of full detail.
- If the vault is small (\<50 notes), most warnings will be "0 instances";
  collapse those sections rather than printing empty headers.
