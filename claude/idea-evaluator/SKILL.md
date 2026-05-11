---
name: idea-evaluator
description: Apply to every diary entry that gets routed to `ideas/`. Append a structured estimate of money required, work needed, and project potential to the entry body so the user can see at a glance whether an idea is worth pursuing.
---

# Idea Evaluator

The user logs raw ideas — business concepts, side projects, home projects,
research bets — into the diary. Before they decide whether to act on one,
they want a quick triage: roughly how much it costs, roughly how much work
it is, and whether the upside looks promising.

## When to trigger

Apply whenever a diary entry is routed to `~/DearDiary/diary/ideas/`. The
routing decision is the gate — if the entry is more of a task than an idea,
don't try to evaluate it; the default routing will have sent it elsewhere.

## What to do

After writing the entry to its destination (with `routed_to` and `tags` in
the frontmatter, same as the default routing), **append** an `## Estimate`
section to the body. Do not overwrite the user's text; add to the end.

### Estimate shape

```markdown
## Estimate

**Cost:** $<low>–$<high> — <one sentence on what dominates the cost>
**Effort:** <hours / days / weeks / months> — <one sentence on the bulk of the work>
**Potential:** <low / medium / high> — <one sentence on the upside if it works>

<2–4 sentences of reasoning. Cover: biggest unknown, cheapest experiment to
de-risk it, and what would change your potential rating.>
```

### Rules for each field

**Cost** — best-effort range in USD. If equipment / subscriptions / cloud
spend dominate, name them. If it's mostly the user's time, say so but
still give a rough $ for incidental spend.

**Effort** — calendar time at the user's normal evenings-and-weekends
pace, NOT total person-hours. If you assume reuse of an existing skill
they have (e.g. they already write bash, they already know Rust), say so.

**Potential** — three levels only:
- `low` — narrow upside, mostly learning value
- `medium` — useful end product, modest external value
- `high` — could change a meaningful slice of the user's life or generate
  significant external value (income, audience, leverage)

Be honest. "Everything is medium" is useless. If you think it's low,
say low — the user can disagree.

## Tone

Skeptical-but-friendly senior engineer doing back-of-envelope estimates
for a friend's side project. Concrete numbers beat hedged ones. If the
idea is genuinely under-specified, give a range and name the variable
that would tighten it.

## Output

Same one-line summary as the default routing, no extra commentary:

```
<id> -> ideas/<id>.md (estimated)
```
