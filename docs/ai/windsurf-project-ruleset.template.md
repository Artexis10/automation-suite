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
- Generate it first using `docs/ai/shadow-generator.prompt.md`

---

## Project Rules Authority

If `docs/ai/PROJECT_RULES.md` exists:
- Treat it as authoritative operational policy
- Follow environment, tooling, and testing contracts
- Respect protected areas and change boundaries

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

---

## Reference

| Document | Purpose |
|----------|---------|
| `docs/ai/AI_CONTRACT.md` | Authoritative behavior contract |
| `docs/ai/PROJECT_SHADOW.md` | Architectural context (if present) |
| `docs/ai/PROJECT_RULES.md` | Operational policy (if present) |
| `docs/ai/deltas/` | Delta Shadow history |
| `docs/ai/shadow-generator.prompt.md` | Generate new Project Shadow |
| `docs/ai/shadow-delta-generator.prompt.md` | Generate Delta Shadow |
