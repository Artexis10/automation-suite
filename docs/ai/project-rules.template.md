# Project Rules: <project-name>

This document defines **authoritative operational policy** for this repository.

It governs environment, tooling, testing, protected areas, and workflow constraints.
It does NOT contain architectural invariants (those belong in `PROJECT_SHADOW.md`).
It does NOT contain tool-adapter logic (that belongs in editor rulesets).

AI collaborators must read and follow this document alongside `AI_CONTRACT.md` and `PROJECT_SHADOW.md`.

---

## 1. Scope and Authority

This document is authoritative for:
- Environment and configuration requirements
- Build, runtime, and tooling contracts
- Testing and verification expectations
- Protected files and change boundaries
- Git and workflow policy

If this document conflicts with `AI_CONTRACT.md`, the AI Contract wins.
If this document conflicts with `PROJECT_SHADOW.md` on architectural matters, the Shadow wins.

---

## 2. Protected Areas and Change Boundaries

Files and directories that require explicit approval before modification:

| Path | Reason |
|------|--------|
| `<example: .env*>` | Contains secrets or environment-specific config |
| `<example: migrations/>` | Schema changes require review |
| `<example: docs/ai/>` | Governance artifacts |

Files that must never be modified by AI:

| Path | Reason |
|------|--------|
| `<example: .git/>` | Git internals |
| `<example: secrets/>` | Sensitive credentials |

---

## 3. Environment and Config Contract

| Variable | Required | Source | Notes |
|----------|----------|--------|-------|
| `<example: DATABASE_URL>` | Yes | `.env` | Connection string |
| `<example: API_KEY>` | Yes | `.env` | External service key |

Environment assumptions:
- <example: Node.js 18+ required>
- <example: PowerShell 5.1+ for scripts>

---

## 4. Build / Runtime / Tooling Contract

| Task | Command | Notes |
|------|---------|-------|
| Install dependencies | `<example: npm install>` | |
| Build | `<example: npm run build>` | |
| Run locally | `<example: npm start>` | |
| Lint | `<example: npm run lint>` | |
| Format | `<example: npm run format>` | |

Tooling constraints:
- <example: Do not add new dependencies without approval>
- <example: Use existing linter config; do not modify>

---

## 5. State / Storage / Artifacts Contract

| Artifact | Location | Persistence | Notes |
|----------|----------|-------------|-------|
| `<example: logs/>` | Local | Ephemeral | Do not commit |
| `<example: dist/>` | Local | Build output | Gitignored |
| `<example: data/>` | Local | Persistent | Backup required |

State assumptions:
- <example: Database migrations are forward-only>
- <example: Cache can be cleared without data loss>

---

## 6. Testing and Verification Contract

| Test Type | Command | Required Before Merge |
|-----------|---------|----------------------|
| Unit tests | `<example: npm test>` | Yes |
| Integration tests | `<example: npm run test:integration>` | Yes |
| E2E tests | `<example: npm run test:e2e>` | No (CI only) |

Verification rules:
- Run targeted tests for changed code
- Do not run full suite unless explicitly requested
- If tests require secrets, ask for guidance

---

## 7. External / CLI / API Contracts (if applicable)

| Interface | Stability | Notes |
|-----------|-----------|-------|
| `<example: /api/v1/*>` | Stable | Do not break without RFC |
| `<example: CLI commands>` | Stable | Preserve existing flags |
| `<example: Internal APIs>` | Unstable | May change freely |

---

## 8. Git and Tooling Policy

Commit rules:
- <example: Use conventional commits>
- <example: One logical change per commit>
- <example: Do not commit generated files>

Branch policy:
- <example: Feature branches off main>
- <example: PRs required for main>

AI-specific rules:
- Do not create commits automatically unless explicitly requested
- Do not push to remote
- Do not modify `.git/` internals

---

## 9. References

| Document | Purpose |
|----------|---------|
| `docs/ai/AI_CONTRACT.md` | AI behavior contract |
| `docs/ai/PROJECT_SHADOW.md` | Architectural truth |
| `docs/ai/PROJECT_RULES.md` | This document |
| `docs/ai/deltas/` | Delta Shadow history |
