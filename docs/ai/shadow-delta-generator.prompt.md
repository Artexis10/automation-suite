# Project Shadow Delta Generator Prompt

This file contains the canonical, version-controlled prompt used to generate Delta Shadows for repositories that already have a `PROJECT_SHADOW.md`.

**Usage:** Provide this prompt to a repo-aware AI agent (e.g., Windsurf, Cursor) with full repository access. The agent will compare the current repository state against the existing `PROJECT_SHADOW.md` and produce either a "no update required" statement or a minimal Delta Shadow.

This document is intended to remain accurate across multiple development cycles and should only be updated when the delta generation process itself changes.

Producing "No Project Shadow update required" is a valid and successful outcome.

---

## Generator Prompt

```
You are generating a DELTA SHADOW for this repository.

A Delta Shadow describes ONLY the meaningful changes that affect the existing
PROJECT_SHADOW.md. It does not restate unchanged context.

The goal is to keep the Project Shadow accurate over time with minimal churn.

---

PRECONDITION

Before proceeding, verify that a PROJECT_SHADOW.md exists in this repository.

If no PROJECT_SHADOW.md exists:
- Output exactly: "Cannot generate Delta Shadow. No PROJECT_SHADOW.md exists in this repository. Generate a full Project Shadow first using the shadow-generator prompt."
- Stop immediately.

---

INPUTS YOU MAY USE

- The current repository state
- The existing PROJECT_SHADOW.md
- Recent changes (commits, diffs, migrations, refactors)

---

AUDIENCE

- Expert AI collaborators
- Maintainers reviewing whether the Project Shadow must be updated
- No repository access beyond the Shadow documents

---

CONSTRAINTS

1. Do NOT restate the full Project Shadow
2. Do NOT propose speculative or future changes
3. Do NOT editorialize
4. Do NOT repeat unchanged information
5. Do NOT update sections that are semantically unchanged
6. Prefer omission over verbosity
7. If unsure whether something is shadow-worthy, err on the side of exclusion

---

WHAT COUNTS AS A SHADOW-LEVEL CHANGE

Only include changes that affect one or more of the following:

- Core invariants
- Architecture or subsystem boundaries
- Contracts or public APIs
- Authority or ownership model
- Landmines or sharp edges
- Explicit non-goals
- Testing philosophy (not individual tests)
- Development workflow assumptions

Implementation-level changes that do NOT affect the above are excluded:
- Bug fixes within existing architecture
- New tests that follow existing strategy
- Documentation updates
- Dependency version bumps
- Performance optimizations that preserve contracts

---

OUTPUT STRUCTURE

Produce ONE of the following outcomes.

### Case A — No Shadow Update Required

Output exactly:

"No Project Shadow update required. All recent changes are implementation-level
and do not affect invariants, architecture, contracts, or authority."

Stop.

---

### Case B — Shadow Update Required

Output a Delta Shadow with this structure:

## Delta Shadow — <short description>

### Affected Sections
List section numbers and titles exactly as they appear in PROJECT_SHADOW.md.

### Summary of Change
A concise description of what changed and why it matters at the shadow level.

### Required Updates
For each affected section:
- State what must be added, removed, or revised
- Keep changes minimal and precise
- Use patch-style language (e.g., "Add invariant: …", "Remove non-goal: …", "Revise: …")

### Rationale
Why this change must be reflected in the Project Shadow (1–3 sentences max).

---

STYLE

- Factual
- Minimal
- Diff-oriented
- No filler
- No restating unchanged context
- Use symbolic code references (module/type/function names) where they add clarity; avoid line numbers

---

VALIDATION

Before finalizing, verify:
- [ ] PROJECT_SHADOW.md exists (precondition met)
- [ ] Either Case A or Case B is followed exactly
- [ ] No unchanged sections are restated
- [ ] All listed changes are shadow-level, not implementation-level
- [ ] Output could be applied manually to PROJECT_SHADOW.md without ambiguity
- [ ] No speculation or future proposals included

---

Generate the Delta Shadow now.
```

---

## Version

**Version:** 1.0  
**Last Updated:** 2026-01-08
