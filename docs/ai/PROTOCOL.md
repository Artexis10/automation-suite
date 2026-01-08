# AI Collaboration Protocol

This document explains how to operate the AI Contract and Project Shadow
system across repositories.

It is explanatory, not enforceable.
The AI_CONTRACT.md is authoritative.

---

## Core Concepts

- AI Contract: governs behavior
- Project Shadow: durable architectural memory
- Shadow Generator: creates memory
- Delta Shadow: evolves memory safely

---

## One-Time Setup (Per Repository)

1. Add AI_CONTRACT.md
2. Add editor ruleset adapter
3. Generate PROJECT_SHADOW.md
4. Commit

---

## Normal Development Flow

- AI reads AI_CONTRACT.md automatically
- AI reads PROJECT_SHADOW.md automatically
- No special action required

---

## When to Generate a Project Shadow

Generate a full Project Shadow only when:
- The repository has no PROJECT_SHADOW.md
- Or the existing Shadow is intentionally discarded

This should be rare.

---

## When to Generate a Delta Shadow

Generate a Delta Shadow when:
- Architectural assumptions change
- Invariants are added or removed
- Contracts or public APIs change
- Development workflow changes
- You feel the urge to re-explain architecture

Do not generate Deltas for implementation-only changes.

---

## Decision Authority

- AI proposes
- Human decides
- No silent architectural changes

---

## What “Automatic” Means Here

- Zero decision-making
- One explicit action when required
- Deterministic behavior thereafter

---

## What This System Intentionally Does Not Do

- No background automation
- No silent updates
- No auto-application of Deltas
- No tool lock-in

---

## Evolution of This Protocol

- Changes to this document are deliberate
- Changes should be rare
- Prefer stability over cleverness
