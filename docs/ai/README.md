# AI Infrastructure

This directory contains AI-facing infrastructure for deterministic, reviewable AI collaboration.

## Contents

### Governance

| File | Purpose |
|------|---------|
| `ai-contract.template.md` | Single source of truth for AI behavior |
| `project-rules.template.md` | Operational policy template (env, tooling, protected areas) |
| `PROTOCOL.md` | Explanatory guide to the governance system |

### Provisioning

| File | Purpose |
|------|---------|
| `ai-collaboration-bootstrap.prompt.md` | One-time prompt to provision AI governance into a repository |

### Project Shadow System

| File | Purpose |
|------|---------|
| `shadow-generator.prompt.md` | Canonical prompt for generating Project Shadows |
| `shadow-delta-generator.prompt.md` | Canonical prompt for generating Delta Shadows |
| `delta-shadow.template.md` | Template for Delta Shadow format |
| `shadow-spec.md` | Specification defining Project Shadow and Delta Shadow semantics |
| `examples/PROJECT_SHADOW.example.md` | Reference example for structure and tone |
| `deltas/` | Storage for append-only Delta Shadow history (per-repo) |

### Editor Adapters

| File | Purpose |
|------|---------|
| `windsurf-project-ruleset.template.md` | Windsurf adapter that delegates to AI Contract |

## What This Is

- **Meta-tooling** for AI-assisted development
- **Not application logic** — does not affect runtime behavior
- **Version-controlled prompts** that produce consistent, auditable outputs

## What This Is Not

- Documentation for humans (see project-level docs)
- Generated content (generated Shadows live in target repos)
- Tool configuration or IDE settings
