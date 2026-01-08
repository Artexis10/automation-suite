# Project Shadow Generator Prompt

This file contains the canonical, version-controlled prompt used to generate Project Shadows for repositories.

**Usage:** Provide this prompt to a repo-aware AI agent (e.g., Windsurf, Cursor) with full repository access. The agent will produce a `PROJECT_SHADOW.md` file to be committed to the target repository.

This document is intended to remain accurate across multiple development cycles and should only be updated when invariants, architecture, or authority change.

---

## How to Use This Prompt

1. Open a repo-aware AI agent with full repository access.
2. Copy **only** the contents of the **Generator Prompt** section below
   (the fenced block).
3. Paste it as-is into the agent.
4. Do not add additional instructions.
5. Commit the generated `docs/ai/PROJECT_SHADOW.md` file.

This prompt is designed to be self-contained.

---

## Generator Prompt

```
You are generating a PROJECT_SHADOW.md file for this repository.

A Project Shadow is a dense, authoritative reference document designed for expert AI collaborators who do not have direct repository access. It captures the essential context required to provide accurate, safe guidance without exploring the codebase.

The output of this prompt will be committed to the repository. Write for permanence.

---

AUDIENCE

- Expert AI systems acting as senior engineering collaborators
- No access to the repository beyond this document
- Assumed competent; do not explain basics

---

CONSTRAINTS

1. Do not propose changes to the codebase
2. Do not editorialize or offer opinions
3. Do not speculate about future directions
4. Do not include tutorial content or onboarding material
5. Do not reference this prompt or the generation process
6. State only what is true now, as implemented

---

OUTPUT STRUCTURE

Generate exactly these 10 sections in order:

## 1. Identity
- Project name, one-line purpose, primary language/framework
- Repository type (library, service, CLI, monorepo, etc.)

## 2. Architecture Overview
- High-level structure (3-7 bullet points)
- Key directories and their roles
- Entry points

## 3. Core Abstractions
- Central types, interfaces, or patterns
- How data flows through the system
- Naming conventions that carry semantic meaning

## 4. Invariants
- Rules that must never be violated
- Assumptions baked into the design
- Constraints that are not enforced by code but must be honored

## 5. Contracts and Boundaries
- Public API surfaces
- Integration points with external systems
- What is stable vs. internal

## 6. Landmines
- Non-obvious failure modes
- Areas where small changes cause large breakage
- Historical decisions that look wrong but are intentional

## 7. Non-Goals
- What this project explicitly does not do
- Scope boundaries
- Common misconceptions to avoid

## 8. Testing Strategy
- How tests are organized
- What must be tested vs. what is optional
- Commands to run tests

## 9. Development Workflow
- How to build, run, and iterate
- Required environment setup
- Common tasks and their commands

## 10. Authority Model
- Who owns architectural decisions
- How changes are reviewed and merged
- Escalation paths for ambiguity

---

STYLE

- Dense, factual prose
- No filler or hedging
- Concrete over abstract
- Use symbolic code references (module/type/function names) where they add clarity; avoid line numbers
- Prefer tables and lists for structured information

---

VALIDATION

Before finalizing, verify:
- [ ] All 10 sections are present
- [ ] No section is empty or placeholder
- [ ] No opinions or proposals included
- [ ] Landmines section contains at least 2 items
- [ ] Invariants section contains at least 2 items
- [ ] Non-Goals section contains at least 2 items
- [ ] If a section is not applicable, it explicitly states “Not applicable” with a brief explanation

---

Generate the PROJECT_SHADOW.md now.
```

---

## Version

**Version:** 1.0  
**Last Updated:** 2026-01-08
