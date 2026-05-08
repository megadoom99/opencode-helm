# Impact Awareness Rules

Before editing any file, check for cross-file impact.

## Pre-Edit Routine

1. If the target file is a shared schema, type definition, utility, or database model, call `impact_check` with the file path first
2. If the change involves renaming or deleting a function/class/variable, check impact with both `filePath` and `symbolName`
3. For any change where the blast radius could exceed 3 files, report the risk to the user before proceeding

## Post-Edit Verification

1. After making changes, read `/Users/andreicebotari/.config/opencode/impact/recent.json` to see if the automatic watcher flagged any high-risk files
2. If LSP reports diagnostics (type errors, undefined references) on affected files, fix them in the same session
3. When the blast radius is large, suggest running `codebase_graph_visualize` to confirm the dependency chain

## When to Skip

- Documentation-only changes (README, comments, markdown)
- Adding new files (no existing dependents)
- Pure cosmetic changes (formatting, whitespace)

## SocratiCode Quick Reference

| Tool | Use When |
|------|----------|
| `impact_check` | Pre-edit: check what will break before changing a file |
| `codebase_search` | Find code by natural language (e.g. "where is auth handled?") |
| `codebase_impact` | Deep impact analysis for a specific file or symbol |
| `codebase_graph_query` | See what imports/depends on a file |
| `codebase_symbol` | Full details on one function/class (callers + callees) |
| `codebase_graph_visualize` | Visual dependency graph (Mermaid or interactive HTML) |

## Beads Task Management

Beads is your persistent task tracker. It runs automatically — you don't need to initialize it manually.

### Workflow

1. **On session start**: Tasks are auto-injected into context via `bd prime` (handled by the opencode-beads plugin)
2. **Before starting work**: Check the "Beads: Unblocked Tasks" section in system context for ready tasks
3. **Creating tasks**: `bd create "Title" -t task -p 1` for new work. Include descriptions for context.
4. **Claiming tasks**: `bd update <id> --claim` to atomically take ownership
5. **Completing tasks**: `bd close <id> "Summary of changes made"` when done
6. **Dependencies**: `bd dep add <child> <parent>` to link blocking/blocked tasks
7. **Session end**: `bd dolt commit && bd dolt push` runs automatically — commits and pushes task state. NEVER skip this.

### Commands Reference

| Command | Purpose |
|---------|---------|
| `bd ready --json` | List unblocked tasks |
| `bd create "Title" -t task -p 1` | Create new task |
| `bd update <id> --claim` | Claim a task |
| `bd close <id> "Reason"` | Close completed task |
| `bd show <id> --json` | View task details |
| `bd list --status open --json` | List all open tasks |
| `bd dep add <child> <parent>` | Add dependency |
| `bd init --quiet --stealth` | Initialize beads (auto-done) |
| `bd dolt commit && bd dolt push` | Commit + push (auto-done) |

### Important Rules

- NEVER use `bd edit` — it opens an interactive editor. Use `bd update` with flags instead.
- Always use `--json` for programmatic output
- Always include descriptions when creating tasks for future context
- `bd dolt commit && bd dolt push` is MANDATORY at session end — it prevents task state loss
