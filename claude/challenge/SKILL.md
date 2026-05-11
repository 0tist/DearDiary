---
name: challenge
description: Apply when the user proposes an idea, plan, or decision and either explicitly asks for pushback (e.g. "challenge this", "argue against", "red-team this") or makes a commitment that has clear analogs in past vault entries. Reads the vault for past failures, reversed decisions, and contradictions on the same topic. Pushes back with the user's own words.
---

# Challenge

Argue against the user's current proposal using their own past notes.
Goal: stop the user from re-making a mistake they already wrote about,
or from contradicting a position they took last quarter without
acknowledging it.

## When to trigger

Either:

- **Explicit ask.** User says "challenge this", "argue against",
  "red-team this", "what could go wrong", "talk me out of this".
- **Strong analog detected.** The user just stated a decision or plan,
  and a quick vault scan finds a `Decisions/` note or `Projects/` note
  on the same `[[topic]]` with `status: reversed`, `status: superseded`,
  or contradictory rationale.

If neither — no trigger. Don't pre-emptively challenge every plan.

## What to do

1. **Identify the claim.** Reduce the user's proposal to one sentence
   ("I want to rewrite the API in Rust", "going with Postgres again",
   "I should buy the espresso machine").

2. **Scan the vault.** Search for notes that touch the claim:
   - `Decisions/` notes on the same topic
   - `Projects/` notes with related `[[wikilinks]]`
   - Recent `Daily/` entries mentioning the topic
   - Anything with status: reversed / superseded / abandoned

3. **Build the pushback.** Look for:
   - **Past failures.** Did the user try this before? What happened?
   - **Reversed decisions.** Did they commit to the opposite once? Why?
   - **Hidden cost markers.** Notes that mention pain, friction, or regret
     associated with the topic.
   - **Contradictions with current priorities.** Does this conflict with
     something the user said was important?

4. **Pushback format.** Print directly in chat:

   ```
   ## Challenge: <one-line restatement of the proposal>

   Past evidence:
   - [[<note title>]] (<date>) — <one-line quote from that note>
   - ...

   The pattern: <one-line synthesis of what the vault says>

   The question: <one specific question the user should answer before
   proceeding>
   ```

5. **No vault evidence?** Say so honestly — don't manufacture
   pushback. One line: "Couldn't find prior notes on this. Want me to
   pressure-test the idea on its own merits anyway?"

## Tone

The user's own voice from past notes is the weapon. Quote them. Don't add
moralizing or generic advice. The point isn't to be right — it's to
surface what the user already knows but might have forgotten.

## Rules

- Read-only. Never modify notes.
- Don't create a `Decisions/` note about the challenge itself unless the
  user asks. The challenge is a conversation, not an artifact.
- If the user dismisses the pushback ("yeah, this time is different
  because…"), DROP it. Don't keep arguing. They've taken the input.
