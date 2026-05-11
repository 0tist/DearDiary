---
name: emerge
description: Apply when the user asks "what patterns are emerging", "what's been on my mind", "what themes are showing up", "what's recurring" — anything that asks the vault to name unnamed patterns. Scans recent notes (default last 30 days) for recurring themes, entities, and questions the user keeps circling without explicitly naming. Reports patterns directly in chat.
---

# Emerge

Surface patterns the user is generating without realizing it. The vault
holds the evidence; the user's job is to NAME the pattern so it can
become a project, decision, or deliberate avoidance.

## When to trigger

Explicit ask using pattern-language: "emerging", "patterns", "themes",
"what's recurring", "what keeps coming up", "what's been on my mind".

If the user hasn't asked, DON'T volunteer. Premature pattern-spotting
just adds noise.

## Useful only when the vault has signal

Heuristic: skill is useful when the vault has **≥30 notes from the last
30 days** across `Ideas/`, `Daily/`, `Decisions/`, `Projects/`. Below
that, there isn't enough signal to find patterns the user couldn't see
themselves. If the vault is below the threshold, say so in one line and
suggest revisiting in a month.

## What to do

1. **Set the window.** Default 30 days. User can override
   ("last 90 days", "since March").

2. **Scan notes in the window.** Read every note's `## For future Claude`
   preamble (or first paragraph if no preamble) plus its `tags:` field.

3. **Look for three pattern types:**

   - **Recurring entities.** A `[[wikilink]]` that shows up across 5+
     unrelated notes. The user is circling this person/project/concept
     without giving it a dedicated note yet.
   - **Recurring keywords/phrases.** Same idea phrased differently in
     multiple notes ("onboarding friction" in one, "people leave too
     fast" in another, "ramp-up is brutal" in a third — all the same
     underlying observation).
   - **Open questions.** Notes that end in a question mark or contain
     "wonder if", "not sure", "what would happen". When the same
     question recurs, it's load-bearing unresolved tension.

4. **Filter aggressively.** A pattern needs ≥3 instances across ≥2
   different folders, or ≥5 instances within one folder, to count.
   Below that, it's noise.

5. **Report.** Print directly in chat:

   ```
   # Emerging patterns — <window>

   ## Recurring entity: [[<name>]] (N mentions)
   - [[<source note>]] (<date>) — <one-line context>
   - ...
   Suggestion: <if it warrants a dedicated note, say so; if it warrants
   graduating to a Project, link to the graduate skill>

   ## Recurring theme: <synthesized phrase>
   - <evidence from N notes>
   Question to ask yourself: <one specific question>

   ## Open question that keeps recurring: <verbatim quote>
   - <which notes>
   ```

6. **No patterns above threshold?** Say so honestly: "Nothing emerged at
   significance threshold. The vault from <window> looks varied —
   not a bad thing." Don't fish for false patterns.

## Rules

- Read-only.
- Quote the user verbatim where possible — synthesized phrases should be
  short and clearly labeled as your synthesis, not their words.
- Don't make 5-pattern reports just to fill the response. Better to
  surface 1 real pattern than pad with weak ones.
