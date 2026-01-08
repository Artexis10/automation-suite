# PROJECT_SHADOW.md

> This is an example Project Shadow for reference. It describes a fictional project to demonstrate structure, tone, and completeness.

---

## 1. Identity

**Name:** DataPipe  
**Purpose:** ETL pipeline framework for batch data processing  
**Language:** Python 3.11+  
**Type:** Library (pip-installable)

---

## 2. Architecture Overview

- **`datapipe/core/`** — Pipeline execution engine and scheduler
- **`datapipe/transforms/`** — Built-in transform implementations
- **`datapipe/connectors/`** — Source and sink adapters (S3, Postgres, etc.)
- **`datapipe/cli/`** — Command-line interface for pipeline execution
- **`tests/`** — Pytest test suite organized by module

Entry points:
- `datapipe.Pipeline` — Primary API for defining pipelines
- `datapipe run` — CLI command for execution

---

## 3. Core Abstractions

| Abstraction | Role |
|-------------|------|
| `Pipeline` | Ordered sequence of transforms with a source and sink |
| `Transform` | Stateless function that processes a batch |
| `Connector` | Adapter for external data systems |
| `Context` | Runtime state passed through pipeline execution |

Data flows: Source Connector → Transform chain → Sink Connector

Naming conventions:
- Transforms are verbs: `FilterRows`, `MapColumns`, `AggregateBy`
- Connectors are nouns with suffix: `S3Connector`, `PostgresConnector`

---

## 4. Invariants

- **Transforms must be stateless.** All state lives in `Context`. Transforms that cache data between batches will cause correctness bugs in distributed execution.

- **Connectors must be idempotent for writes.** The scheduler may retry failed batches. Non-idempotent sinks will cause duplicate data.

- **Pipeline definitions are immutable after construction.** Modifying a `Pipeline` object after `build()` is called produces undefined behavior.

---

## 5. Contracts and Boundaries

**Public API (stable):**
- `datapipe.Pipeline`
- `datapipe.Transform` (base class)
- `datapipe.Connector` (base class)
- All classes in `datapipe.transforms`
- All classes in `datapipe.connectors`

**Internal (unstable):**
- `datapipe.core.scheduler` — Implementation detail
- `datapipe.core.batch` — Internal batch representation

**Integration points:**
- S3 via `boto3`
- PostgreSQL via `psycopg2`
- Metrics exported to StatsD

---

## 6. Landmines

- **`PostgresConnector` uses server-side cursors by default.** This reduces memory usage but requires transactions to stay open. Long-running transforms will cause connection timeouts. Override with `server_side=False` for small datasets.

- **The `--parallel` CLI flag shares `Context` across workers.** Context mutations in one worker are not visible to others. This is intentional but frequently causes confusion.

- **`FilterRows` with empty predicates returns all rows, not zero rows.** This matches SQL semantics but surprises users expecting Python's `filter()` behavior.

---

## 7. Non-Goals

- **Streaming execution.** DataPipe is batch-only. For streaming, use a different tool.

- **Schema enforcement.** Pipelines do not validate schemas. Garbage in, garbage out.

- **Orchestration.** DataPipe runs single pipelines. For DAGs of pipelines, use Airflow or similar.

- **Data quality checks.** Validation transforms exist but are opt-in. The framework does not enforce data quality.

---

## 8. Testing Strategy

**Organization:**
- `tests/unit/` — Fast, isolated tests (no I/O)
- `tests/integration/` — Tests requiring Docker services
- `tests/e2e/` — Full pipeline execution tests

**Requirements:**
- All transforms must have unit tests
- Connectors require integration tests
- New features require at least one e2e test

**Commands:**
```bash
pytest tests/unit                    # Fast feedback
pytest tests/integration             # Requires Docker
pytest                               # All tests
```

---

## 9. Development Workflow

**Setup:**
```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

**Run locally:**
```bash
datapipe run examples/simple.yaml
```

**Common tasks:**

| Task | Command |
|------|---------|
| Run tests | `pytest` |
| Type check | `mypy datapipe` |
| Lint | `ruff check datapipe` |
| Format | `ruff format datapipe` |
| Build docs | `mkdocs build` |

---

## 10. Authority Model

- **Architecture decisions:** Require approval from maintainers listed in `CODEOWNERS`
- **New connectors:** Require design doc in `docs/designs/` before implementation
- **Breaking changes:** Require RFC and version bump
- **Bug fixes:** Standard PR review by any maintainer

Escalation: Open a GitHub Discussion for ambiguous cases.
