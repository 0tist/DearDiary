---
name: decision-logger
description: Apply when a diary entry describes a decision the user made or is making (e.g. "going with Postgres over Mongo", "decided to skip the kayak trip", "settling on React for the rewrite"). File the entry to Decisions/ with ADR-lite structure instead of the default routing.
---

# Decision Logger

The user logs decisions in the diary. Casual ones ("going with X"), and
heavier ones (structural choices, project pivots, repo conventions). Both
deserve a Decisions/ note in ADR-lite shape so future-Claude can answer
"why did we end up doing X?" without reconstructing context from scratch.

## When to trigger

The entry describes a decision IF it contains:

- Past-tense commitment language: "decided", "settled on", "going with",
  "chose", "ruled out", "we'll do X"
- Forward-tense commitment: "will pick X", "next step is X", "the
  approach is X"
- Reversal language: "stop doing X", "moving away from X", "X was wrong"

If the entry is just a thought, observation, or idea (no commitment),
DON'T trigger — let default routing handle it.

## What to do

File the entry to `{{DIARY_ROOT}}/Decisions/<id>.md` with this structure
(replaces the default AI-first body shape):

```markdown
---
type: decision
date: <ISO timestamp from the original `created_at`>
status: accepted              # or `proposed`, `superseded`, `reversed`
tags: [<short, lowercase>]
ai-first: true
routed_to: Decisions
---

## For future Claude

<2–3 short lines: what was decided, when, why it matters>

## Decision

<one-line summary — the actionable commitment>

## Context

<what prompted this — the problem, constraint, or trigger>

## Rationale

<why this option over the alternatives the user mentioned (or hinted at)>

## Consequences

<what changes as a result; if the user named affected projects/people,
[[wikilink]] them here>

## Source

> <user's original text, preserved verbatim>
```

Sections may be terse — a one-line Context is fine. Don't pad. If the
user didn't mention alternatives, omit Rationale; if no consequences are
clear, omit that section. The goal is structure WHERE STRUCTURE FITS,
not bureaucracy.

## TODO appending

If the decision implies follow-up work (e.g. "next step is X"), append
that as a bullet to `## Active` in {{TODO_FILE}} with prefix
`- [decision] `.

## Move the original

Same as default routing: `mv` the inbox file to {{DIARY_ROOT}}/processed/.

## Output

One line to stdout, same shape as default routing:

```
<id> -> Decisions/<id>.md
```
