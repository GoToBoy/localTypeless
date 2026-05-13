# docs

Progressive spec for local-typeless. Read on demand — the [root `AGENTS.md`](../AGENTS.md) is the entry point; this tree holds the deep material.

Each section has an `index.md` that's safe to skim for orientation.

## Sections

- **[architecture/](architecture/index.md)** — component map, pipeline, model lifecycle, hotkeys.
- **[operations/](operations/index.md)** — build + test workflow, permissions, logging, filesystem layout.
- **[references/](references/index.md)** — external dependencies, localization, data schemas.
- **[product/](product/index.md)** — what the user sees: features, settings, known limitations.

## Conventions for this tree

- Describes the **current** state of the app. Not a changelog.
- No migration records, "we used to", or completed ExecPlans — commit history is the source of truth for that.
- Link out to concrete files (with `path:line` when helpful) instead of reproducing code that will drift.
