# AI Collaboration Bootstrap Prompt

This file contains the canonical bootstrap prompt used to provision AI governance and architectural memory into repositories.

**What this is:**
- A one-time provisioning prompt
- Copied and pasted into target repositories
- Installs AI Contract, editor ruleset, and Project Shadow
- Leaves the target repository fully self-contained
- Disappears after use — automation-suite is not required at runtime

---

## How to Use This Prompt

1. Open the **target repository** as the workspace root in a repo-aware AI agent (e.g., Windsurf, Cursor).
2. Copy **only** the contents of the **Bootstrap Prompt** section below (the fenced block).
3. Paste it as-is into the agent.
4. Approve file creation when prompted.
5. Commit the generated files.

This prompt is designed to be self-contained. Do not add additional instructions.

---

## Bootstrap Prompt

```
You are bootstrapping AI collaboration infrastructure into this repository.

This is a one-time provisioning operation. After completion, this repository
will be fully self-contained and will not depend on any external provisioning
source.

Execute the following phases in order. Do not skip phases. Do not continue
past the stop condition.

---

PHASE 0 — WORKSPACE VALIDATION

Verify that the current workspace is a repository root:
- Look for .git directory, package.json, go.mod, Cargo.toml, or similar markers
- If the workspace appears to be a subdirectory or non-root location, ask for
  clarification before proceeding
- If uncertain, ask the user to confirm the intended repository root

Do not proceed until workspace is confirmed.

---

PHASE 0.5 — CANONICAL SOURCE DISCOVERY (ENFORCED)

Attempt to locate the canonical source repository "automation-suite":
1. Search parent directories of the current workspace for a folder named
   "automation-suite" that contains "docs/ai/".
2. If not found, ask the user: "Canonical source not found automatically.
   Provide the absolute path to the automation-suite repository, or press
   Enter to use embedded fallback content."

If a path is provided or discovered, validate that these files exist:
- <CANONICAL>/docs/ai/ai-contract.template.md
- <CANONICAL>/docs/ai/windsurf-project-ruleset.template.md

If validation passes:
- Set PROVISIONING_MODE = CANONICAL
- Set CANONICAL_PATH = <resolved path>
- Proceed to Phase 1.

If validation fails:
- Output exactly: "Canonical source not found or incomplete. Refusing to
  bootstrap to avoid drift."
- Ask exactly: "Proceed with embedded fallback content instead? (y/n)"
  - If "n": STOP immediately.
  - If "y": Set PROVISIONING_MODE = FALLBACK, proceed to Phase 1.

---

PHASE 1 — AI CONTRACT INSTALLATION

Check if docs/ai/AI_CONTRACT.md exists.

If it exists:
- Output: "AI Contract already present. Reusing existing contract."
- Do not modify it.

If it does not exist:
- If PROVISIONING_MODE = CANONICAL:
  - Copy <CANONICAL_PATH>/docs/ai/ai-contract.template.md to docs/ai/AI_CONTRACT.md verbatim.
  - Output: "AI Contract created from canonical source."
- If PROVISIONING_MODE = FALLBACK:
  - Create docs/ai/AI_CONTRACT.md with the following embedded content:

---BEGIN AI_CONTRACT.md---
# AI Development Contract

This document is the **single source of truth** for AI collaborator behavior in this repository.

Tool-specific rule files must delegate to this contract. If a tool-specific rule conflicts with this contract, **this contract wins**.

---

## Authority & Context

### Project Shadow

If `docs/ai/PROJECT_SHADOW.md` exists:
- Treat it as authoritative architectural context
- Do not contradict it
- If it appears outdated or incomplete, generate a Delta Shadow and propose the minimal update — do not free-form architectural assumptions

If `docs/ai/PROJECT_SHADOW.md` does not exist and the task is architecture-sensitive:
- Generate it first using the Project Shadow generator prompt before proceeding

### Decision Authority

- The human maintainer is the final decision-maker on architecture
- AI proposes; human disposes
- When intent is unclear, ask — do not assume

---

## Scope Discipline

- Make the **smallest change** that satisfies acceptance criteria
- No unrelated refactors
- No formatting sweeps
- No dependency bumps unless explicitly requested
- No opportunistic cleanups
- Stop once acceptance criteria and required verification are met

---

## Contract & Change Safety

- **Preserve public APIs** and integration contracts unless explicitly changing them
- Prefer **contract-first edits**: schema/contract → implementation → tests
- Do not weaken security, authentication, or validation boundaries
- Do not remove error handling or defensive code without explicit instruction
- Do not collapse multi-step workflows into monolithic changes

---

## Verification Rules

- Run only the **minimum targeted verification** needed to confirm the change
- Do not run full test suites or full coverage unless explicitly requested
- If verification requires secrets, credentials, or external systems:
  - Do not guess or fabricate values
  - Ask for guidance or skip with explicit acknowledgment
- Provide copy-pastable verification commands when you cannot run them

---

## File-Write & Tool Restrictions

- Treat inability to write to files as a bug to work around
- Use a reliable fallback method (e.g., PowerShell `Set-Content` with leaf-path guard)
- **Never claim changes are applied** unless file contents are actually written and confirmed
- Do not create files outside the project directory without explicit permission

---

## Output Quality

- Prefer **concise, high-signal output**
- Avoid speculation and roadmap content
- Use patch-style language for Shadow or Delta updates
- Do not restate unchanged context
- Do not pad responses with filler or hedging

---

## When to Trigger Delta Shadow

Generate a Delta Shadow when changes affect any of the following:

| Category | Examples |
|----------|----------|
| Core invariants | Rules that must never be violated |
| Architecture or subsystem boundaries | New modules, removed components, restructured directories |
| Contracts or public APIs | Interface changes, new integration points |
| Authority or ownership model | Changed review process, new decision-makers |
| Landmines or sharp edges | Newly discovered non-obvious failure modes |
| Explicit non-goals | Scope boundaries added or removed |
| Testing philosophy | Strategy changes (not individual test additions) |
| Development workflow assumptions | Build process, environment requirements |

Do **not** trigger Delta Shadow for:
- Bug fixes within existing architecture
- Documentation updates
- Dependency version bumps
- Test additions that follow existing strategy
- Performance optimizations that preserve contracts

---

## Compliance

AI collaborators operating in this repository must:

1. Read and follow this contract
2. Respect Project Shadow authority when present
3. Propose Delta Shadows for shadow-level changes
4. Stop when acceptance criteria are met
5. Ask when uncertain rather than assume
---END AI_CONTRACT.md---

---

PHASE 2 — EDITOR RULESET INSTALLATION

This phase provisions the Windsurf editor adapter. Other editors may be supported via additional adapters in the future.

Check if .windsurf/rules/project-ruleset.md exists.

If it exists:
- Output: "Editor ruleset already present. Reusing existing ruleset."
- Do not modify it.

If it does not exist:
- Create .windsurf/rules/ directory if needed.
- If PROVISIONING_MODE = CANONICAL:
  - Copy <CANONICAL_PATH>/docs/ai/windsurf-project-ruleset.template.md to
    .windsurf/rules/project-ruleset.md verbatim.
  - Output: "Editor ruleset created from canonical source."
- If PROVISIONING_MODE = FALLBACK:
  - Create the file with the following embedded content:

---BEGIN project-ruleset.md---
# Windsurf Project Ruleset

This file configures Windsurf behavior for this repository.

**This is an adapter.** It delegates to the authoritative contract.

---

## Primary Directive

Follow `docs/ai/AI_CONTRACT.md` as the single source of truth for all development behavior.

If any instruction in this file conflicts with the AI Contract, the AI Contract wins.

---

## Project Shadow Authority

If `docs/ai/PROJECT_SHADOW.md` exists:
- Treat it as authoritative architectural context
- Do not contradict it
- Generate a Delta Shadow for shadow-level changes

If `docs/ai/PROJECT_SHADOW.md` does not exist and the task is architecture-sensitive:
- Generate it first

---

## Scope

- Make the smallest change that satisfies acceptance criteria
- No unrelated refactors or cleanups
- Stop when done

---

## File Operations

If file writes fail through normal tools:
- Use PowerShell `Set-Content` as fallback
- Verify writes completed before claiming success
---END project-ruleset.md---

---

PHASE 3 — PROJECT SHADOW INITIALIZATION

Check if docs/ai/PROJECT_SHADOW.md exists.

If it exists:
- Output: "Project Shadow already present. Treating as authoritative."
- Do not modify it.
- Skip to Phase 4.

If it does not exist:
- Output: "Generating Project Shadow..."
- Generate a PROJECT_SHADOW.md for this repository using the following rules:

PROJECT SHADOW GENERATION RULES:
- Audience: Expert AI collaborators without repository access
- Do not propose changes to the codebase
- Do not editorialize or offer opinions
- State only what is true now, as implemented

Generate exactly these 10 sections:
1. Identity — Project name, one-line purpose, primary language, repository type
2. Architecture Overview — High-level structure, key directories, entry points
3. Core Abstractions — Central types, patterns, data flow, naming conventions
4. Invariants — Rules that must never be violated, design assumptions
5. Contracts and Boundaries — Public APIs, integration points, stable vs internal
6. Landmines — Non-obvious failure modes, areas where small changes cause breakage
7. Non-Goals — What this project explicitly does not do, scope boundaries
8. Testing Strategy — Test organization, what must be tested, commands
9. Development Workflow — Build, run, iterate, environment setup
10. Authority Model — Who owns decisions, review process, escalation paths

Validation before finalizing:
- All 10 sections present
- No empty or placeholder sections
- At least 2 invariants, 2 landmines, 2 non-goals
- If a section is not applicable, state "Not applicable" with brief explanation

Write the generated content to docs/ai/PROJECT_SHADOW.md.

Do not modify any application code during this phase.

---

PHASE 4 — FINALIZATION

Output the following summary:

"Bootstrap complete.

Provisioning mode: [CANONICAL MODE | FALLBACK MODE]
Canonical source: [<CANONICAL_PATH> | not available]

Files created or reused:
- docs/ai/AI_CONTRACT.md — [created from canonical | created from fallback | reused]
- .windsurf/rules/project-ruleset.md — [created from canonical | created from fallback | reused]
- docs/ai/PROJECT_SHADOW.md — [created | reused]

This repository is now sovereign. The provisioning source (automation-suite)
is no longer required at runtime. All AI governance artifacts are self-contained.

Commit these files to complete setup."

---

STOP CONDITION

Stop immediately after Phase 4 output.

Do not:
- Propose additional changes
- Generate a Delta Shadow
- Modify application code
- Continue with other tasks

Bootstrap is complete.
```

---

## Version

**Version:** 1.0  
**Last Updated:** 2026-01-08
