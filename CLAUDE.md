## CHANGELOG.md Rules

When the user asks to log changes into `CHANGELOG.md`:

1. **Prepend** a new section at the top (below the file header, above all existing entries)
2. **Section header format**: `## [YYYY-MM-DD] — <short description of the session's theme>`
3. **Group entries** under these subsections as applicable:
   - `### Added` — new files, dependencies, features
   - `### Changed` — modifications to existing files or behaviour
   - `### Removed` — deleted files or dropped functionality
   - `### Fixed` — bug fixes
   - `### Decisions` — reasoning behind non-obvious choices (architecture, naming, trade-offs, workarounds)
4. Each bullet should name the **file or artifact** first, then a concise description of what changed and why
5. The `### Decisions` block is mandatory when a non-trivial design choice was made — explain *why*, not just *what*
6. Never overwrite or delete existing entries
