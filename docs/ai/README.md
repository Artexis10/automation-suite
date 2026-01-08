# AI Infrastructure

This directory contains AI-facing infrastructure for deterministic, reviewable AI collaboration.

## Contents

| File | Purpose |
|------|---------|
| `shadow-generator.prompt.md` | Canonical prompt for generating Project Shadows |
| `shadow-spec.md` | Specification defining what a Project Shadow is |
| `examples/` | Reference examples for structure and tone |

## What This Is

- **Meta-tooling** for AI-assisted development
- **Not application logic** — does not affect runtime behavior
- **Version-controlled prompts** that produce consistent, auditable outputs

## What This Is Not

- Documentation for humans (see project-level docs)
- Generated content (generated Shadows live in target repos)
- Tool configuration or IDE settings

## Key Distinction

| Artifact | Location | Purpose |
|----------|----------|---------|
| Generator Prompt | `shadow-generator.prompt.md` | Input to AI — produces Shadows |
| Specification | `shadow-spec.md` | Defines structure and rules |
| Generated Shadow | Target repo's `PROJECT_SHADOW.md` | Output — committed to other repos |

## Usage

1. Open a target repository in a repo-aware AI agent
2. Provide the generator prompt from `shadow-generator.prompt.md`
3. Review and commit the generated `PROJECT_SHADOW.md` to the target repo
