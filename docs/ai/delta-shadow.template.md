# Delta Shadow: YYYY-MM-DD-short-slug

A Delta Shadow records a discrete architectural change that affects the Project Shadow.

Delta Shadows are **append-only**. Once committed, they are not modified.
They provide an auditable history of architectural drift and evolution.

---

## Trigger

What caused this Delta Shadow to be generated:
- <example: New subsystem added>
- <example: Invariant discovered>
- <example: Public API changed>

---

## Previous Shadow Statement

The relevant excerpt from `PROJECT_SHADOW.md` before this change:

```
<quote the affected section(s) verbatim>
```

---

## Updated Truth

The new authoritative statement that should replace or augment the previous:

```
<new content to be merged into PROJECT_SHADOW.md>
```

---

## Affected Sections

List section numbers and titles from `PROJECT_SHADOW.md`:

- <example: 2. Architecture Overview>
- <example: 4. Invariants>

---

## Impact

What changes as a result of this Delta:
- <example: New directory added to architecture overview>
- <example: New invariant documented>
- <example: Landmine removed (no longer applicable)>

---

## Merge Plan

How to apply this Delta to `PROJECT_SHADOW.md`:

1. <example: Add new bullet to section 2>
2. <example: Replace invariant #3 in section 4>
3. <example: Remove landmine #2 from section 6>

---

## Metadata

| Field | Value |
|-------|-------|
| Date | YYYY-MM-DD |
| Author | <human or AI> |
| Reviewed | <pending \| approved> |
| Applied | <pending \| merged> |
