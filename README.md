# HELM — Impact Analysis System for OpenCode

Persistent cross-file impact awareness for OpenCode. Automatically tracks what breaks when you change code.

## What HELM Does

| Feature | Automatic? | How |
|---------|-----------|-----|
| Semantic code search | Ask | SocratiCode indexes your codebase (embeddings + BM25 + RRF) |
| Cross-file impact analysis | **Yes** | Detects file changes → runs blast radius analysis → injects into chat context |
| Task tracking (Beads) | **Yes** | Auto-initializes per project, tracks done/blocked/pending tasks |
| Impact-task linking | **Yes** | Links changed files to related open beads tasks automatically |
| Session-end task sync | **Yes** | `bd dolt commit && bd dolt push` on every compaction/exit |
| LSP type checking | **Yes** | OpenCode's built-in LSP — type errors fed to LLM as context |
| Dependency graph viz | Ask | Mermaid diagrams or interactive HTML explorer |
| Symbol lookup | Ask | 360° view of any function/class: definition, callers, callees |

## Quick Install

```bash
# Clone
git clone https://github.com/megadoom99/opencode-helm.git
cd opencode-helm

# Install
./install.sh

# Restart OpenCode
```

### Prerequisites

| Tool | Install |
|------|---------|
| Docker | `brew install docker` or [docker.com](https://docs.docker.com/get-docker/) |
| Node.js | `brew install node` or [nodejs.org](https://nodejs.org/) |
| Ollama | `brew install ollama` or [ollama.com](https://ollama.com/download) |
| Beads (bd) | `brew install beads` or [install script](https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh) |

The installer checks for these and warns if any are missing.

## What Gets Installed

```
~/.config/opencode/
├── plugins/impact-watcher.ts   # Background file watcher + chat injection
├── tools/impact_check.ts       # Manual LLM-callable impact tool
├── impact-context.md           # LLM behavior instructions
├── impact/recent.json          # Auto-generated impact reports (created on first use)
└── opencode.json               # Deep-merged — existing config + HELM entries
```

**Your existing `opencode.json` is never overwritten** — the installer deep-merges HELM entries into it.

## How To Use

### Automatic (No Action Needed)

Every session, HELM automatically:
- Detects file changes and analyzes cross-file impact
- Injects impact reports + open beads tasks into every LLM response
- Shows toast warnings for high-risk changes (>3 affected files)
- Syncs beads state on compaction/session end

### Manual — Ask OpenCode

| What | How |
|------|-----|
| Index codebase | *"Index this codebase"* |
| Search code | *"Find where authentication is handled"* |
| Check what breaks | *"What depends on server/index.ts?"* |
| Dependency graph | *"Show me the dependency graph as a diagram"* |
| Create task | `bd create "Fix auth bug" -t task -p 1 --json` |
| Close task | `bd close <id> --reason "Fixed"` |

## Installing via OpenCode Agent

Tell your OpenCode agent:

```
"Install HELM from https://github.com/megadoom99/opencode-helm:
 clone the repo, run ./install.sh, then index my project using
 codebase_index. After indexing, verify with codebase_health."
```

The agent will handle all steps and report success.

## Architecture

```
HELM
├── SocratiCode (MCP)      → code indexing, semantic search, dependency graphs
├── impact-watcher (plugin) → file change detection, impact analysis, chat injection
├── Beads (bd CLI)         → task tracking, auto-init, session persistence
├── impact_check (tool)    → explicit LLM-callable pre-edit impact check
└── LSP                    → real-time type error detection
```

## Restore Backup

If ECC or another tool overwrites your opencode config, restore from the backup:

```bash
cp backups/macbook-pro/opencode.json ~/.config/opencode/opencode.json
cp backups/macbook-pro/impact-watcher.ts ~/.config/opencode/plugins/
cp backups/macbook-pro/impact_check.ts ~/.config/opencode/tools/
cp backups/macbook-pro/impact-context.md ~/.config/opencode/
cp backups/macbook-pro/package.json ~/.config/opencode/
```

## Uninstall

Remove HELM files from `~/.config/opencode/`:

```bash
rm ~/.config/opencode/plugins/impact-watcher.ts
rm ~/.config/opencode/tools/impact_check.ts
rm ~/.config/opencode/impact-context.md
rm -rf ~/.config/opencode/impact/
```

Then edit `~/.config/opencode/opencode.json` to remove:
- `"socraticode"` from `mcp` (if not needed)
- `"./plugins/impact-watcher.ts"` from `plugin` array
- `"codebase_*"`, `"socraticode_*"`, `"impact_check"` from `tools`
- HELM instruction paths from `instructions`

SocratiCode's Docker containers (`socraticode-qdrant`) and Beads databases (`.beads/`) remain in your projects — delete them manually if desired.

## License

MIT
