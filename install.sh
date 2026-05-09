#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# HELM — OpenCode Impact Analysis System Installer
# macOS / Linux
# ──────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCODE_DIR="${HOME}/.config/opencode"
OPENCODE_JSON="${OPENCODE_DIR}/opencode.json"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  HELM — Impact Analysis System for OpenCode${NC}"
echo -e "${CYAN}  OS: ${OS}${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

# ──────────── BINARY DETECTION ────────────

find_binary() {
    local name="$1"
    local path
    path="$(command -v "${name}" 2>/dev/null || true)"
    echo "${path}"
}

NODE_BIN=$(find_binary node)
NPM_BIN=$(find_binary npm)
NPX_BIN=$(find_binary npx)
BD_BIN=$(find_binary bd)

echo -e "${YELLOW}Resolved binaries:${NC}"
echo "  node  = ${NODE_BIN:-NOT FOUND}"
echo "  npm   = ${NPM_BIN:-NOT FOUND}"
echo "  npx   = ${NPX_BIN:-NOT FOUND}"
echo "  bd    = ${BD_BIN:-NOT FOUND}"
echo ""

if [ -z "${NODE_BIN}" ] || [ -z "${NPM_BIN}" ] || [ -z "${NPX_BIN}" ]; then
    echo -e "${RED}ERROR: Node.js/npm/npx not found on PATH.${NC}"
    echo "Install Node.js: https://nodejs.org/ or 'brew install node'"
    exit 1
fi

# ──────────── PREREQUISITE CHECKS ────────────

check_optional() {
    local name="$1" cmd="$2" url="$3"
    if command -v "${cmd}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${name} found"
    else
        echo -e "  ${YELLOW}⚠${NC} ${name} not found — install: ${url}"
    fi
}

echo -e "${YELLOW}Prerequisites:${NC}"
check_optional "Docker"       "docker"   "https://docs.docker.com/get-docker/"
check_optional "Ollama"       "ollama"   "https://ollama.com/download"
check_optional "Beads (bd)"   "bd"       "curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash"
echo ""

# ──────────── CREATE DIRECTORIES ────────────

mkdir -p "${OPENCODE_DIR}/plugins" "${OPENCODE_DIR}/tools" "${OPENCODE_DIR}/impact"
echo -e "${GREEN}Created directories:${NC}"
echo "  ${OPENCODE_DIR}/plugins/"
echo "  ${OPENCODE_DIR}/tools/"
echo "  ${OPENCODE_DIR}/impact/"
echo ""

# ──────────── ENSURE PACKAGE.JSON ────────────

PACKAGE_JSON="${OPENCODE_DIR}/package.json"
if [ ! -f "${PACKAGE_JSON}" ]; then
    cat > "${PACKAGE_JSON}" << 'PJSON'
{
  "dependencies": {
    "@opencode-ai/plugin": "^1"
  }
}
PJSON
    echo -e "${GREEN}Created ${PACKAGE_JSON}${NC}"
else
    echo -e "${GREEN}Using existing ${PACKAGE_JSON}${NC}"
fi

# Install dependency
"${NPM_BIN}" install --prefix "${OPENCODE_DIR}" --save @opencode-ai/plugin 2>/dev/null || true
echo ""

# ──────────── WRITE PLUGIN & TOOL FILES ────────────

write_file() {
    local src="${SCRIPT_DIR}/files/$1"
    local dst="${OPENCODE_DIR}/$2"
    if [ ! -f "${src}" ]; then
        echo -e "${RED}ERROR: ${src} not found${NC}"
        exit 1
    fi
    sed \
        -e "s|__NODE_PATH__|${NODE_BIN}|g" \
        -e "s|__NPM_PATH__|${NPX_BIN}|g" \
        -e "s|__BD_PATH__|${BD_BIN}|g" \
        "${src}" > "${dst}"
    echo -e "  ${GREEN}✓${NC} ${dst}"
}

echo -e "${YELLOW}Writing HELM files:${NC}"
write_file "impact-watcher.ts" "plugins/impact-watcher.ts"
write_file "impact_check.ts"   "tools/impact_check.ts"
cp "${SCRIPT_DIR}/files/impact-context.md" "${OPENCODE_DIR}/impact-context.md"
echo -e "  ${GREEN}✓${NC} ${OPENCODE_DIR}/impact-context.md"
echo ""

# ──────────── MERGE INTO OPENCODE.JSON ────────────

echo -e "${YELLOW}Merging into opencode.json:${NC}"

"${NODE_BIN}" -e "
const fs = require('fs');
const path = '${OPENCODE_JSON}';

let config = {};
try { config = JSON.parse(fs.readFileSync(path, 'utf-8')); } catch {}

config['\$schema'] = 'https://opencode.ai/config.json';
if (!config.mcp) config.mcp = {};

// — socraticode MCP (code intelligence engine) —
if (!config.mcp.socraticode) {
    config.mcp.socraticode = { type: 'local', command: ['${NPX_BIN}', '-y', 'socraticode'], enabled: true };
}

// — crawl4ai MCP (web crawling + markdown conversion) —
if (!config.mcp.crawl4ai) {
    config.mcp.crawl4ai = { type: 'local', command: ['${NODE_BIN}', '${HOME}/Downloads/OpenCodeProjects/crawl4ai-mcp.js'], enabled: true };
}

// — github MCP (repository operations) —
if (!config.mcp.github) {
    config.mcp.github = { type: 'local', command: ['${NPX_BIN}', '-y', '@modelcontextprotocol/server-github'], enabled: true };
}

// — searxng MCP (privacy-respecting web search) —
if (!config.mcp.searxng) {
    config.mcp.searxng = { type: 'local', command: ['${NPX_BIN}', '-y', 'mcp-searxng'], enabled: true };
}

// — filesystem MCP (read/write/list file operations) —
if (!config.mcp.filesystem) {
    config.mcp.filesystem = { type: 'local', command: ['${NPX_BIN}', '-y', '@modelcontextprotocol/server-filesystem', '${HOME}/Downloads/OpenCodeProjects'], enabled: true };
}

// — sequential-thinking MCP (multi-step reasoning) —
if (!config.mcp['sequential-thinking']) {
    config.mcp['sequential-thinking'] = { type: 'local', command: ['${NPX_BIN}', '-y', '@modelcontextprotocol/server-sequential-thinking'], enabled: true };
}

// — context7 MCP (remote docs lookup — set CONTEXT7_API_KEY env var) —
if (!config.mcp.context7) {
    config.mcp.context7 = { type: 'remote', url: 'https://mcp.context7.com/mcp', enabled: true, description: 'Fetches latest docs for libraries and frameworks' };
}

// — postgres MCP (disabled by default — enable + update connection string when needed) —
if (!config.mcp.postgres) {
    config.mcp.postgres = { type: 'local', command: ['${NPX_BIN}', '-y', '@modelcontextprotocol/server-postgres', 'postgresql://localhost:5432/mydb'], enabled: false };
}

// — Inject PATH + HOME into ALL local MCP entries —
const defaultEnv = { PATH: '${NODE_BIN%/*}:/usr/local/bin:/usr/bin:/bin', HOME: '${HOME}' };
for (const [key, val] of Object.entries(config.mcp)) {
    if (val.type === 'local') {
        if (!val.environment) val.environment = {};
        val.environment.PATH = val.environment.PATH || defaultEnv.PATH;
        val.environment.HOME = val.environment.HOME || defaultEnv.HOME;
    }
}

// — LSP —
if (config.lsp === undefined) config.lsp = true;

// — Shell —
if (!config.shell) config.shell = '${SHELL:-/bin/zsh}';

// — Plugin array —
if (!config.plugin) config.plugin = [];
if (!config.plugin.includes('./plugins/impact-watcher.ts')) {
    config.plugin.push('./plugins/impact-watcher.ts');
}

// — Tools —
if (!config.tools) config.tools = {};
if (config.tools['codebase_*'] === undefined) config.tools['codebase_*'] = true;
if (config.tools['socraticode_*'] === undefined) config.tools['socraticode_*'] = true;
if (config.tools['impact_check'] === undefined) config.tools['impact_check'] = true;

// — Instructions —
if (!config.instructions) config.instructions = [];
const ctxPath = '${OPENCODE_DIR}/impact-context.md';
if (!config.instructions.includes(ctxPath)) {
    config.instructions.push(ctxPath);
}

fs.writeFileSync(path, JSON.stringify(config, null, 2) + '\n', 'utf-8');
console.log('  ' + path + ' — merged');
"

echo ""

# ──────────── OPTIONAL: PULL EMBEDDING MODEL ────────────

if command -v ollama &>/dev/null; then
    echo -e "${YELLOW}Ollama detected. Pulling nomic-embed-text (274MB)...${NC}"
    ollama pull nomic-embed-text 2>/dev/null && echo -e "${GREEN}  nomic-embed-text pulled${NC}" || echo -e "${YELLOW}  Skipped — pull manually: ollama pull nomic-embed-text${NC}"
    echo ""
fi

# ──────────── OPTIONAL: INIT BEADS ────────────

if [ -n "${BD_BIN}" ] && [ -d "$(pwd)" ]; then
    PROJECT_DIR="$(pwd)"
    if [ ! -d "${PROJECT_DIR}/.beads" ]; then
        DIR_NAME="$(basename "${PROJECT_DIR}")"
        PREFIX="$(echo "${DIR_NAME}" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/^-*//;s/-*$//' | cut -c1-40)"
        [ -z "${PREFIX}" ] && PREFIX="project"
        echo -e "${YELLOW}Initializing beads in ${PROJECT_DIR}...${NC}"
        "${BD_BIN}" init --quiet --stealth --prefix "${PREFIX}" 2>/dev/null && echo -e "${GREEN}  beads initialized (prefix: ${PREFIX})${NC}" || echo -e "${YELLOW}  Skipped${NC}"
        echo ""
    fi
fi

# ──────────── SUMMARY ────────────

echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  HELM installation complete!${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo "    1. Restart OpenCode"
echo "    2. Index your project: ask OpenCode 'Index this codebase'"
echo "    3. Monitor: ask 'Check codebase health'"
echo "    4. Search: ask 'Find where authentication is handled'"
echo ""
echo "  Files installed:"
echo "    ${OPENCODE_DIR}/plugins/impact-watcher.ts"
echo "    ${OPENCODE_DIR}/tools/impact_check.ts"
echo "    ${OPENCODE_DIR}/impact-context.md"
echo "    ${OPENCODE_JSON} (merged)"
echo "    ${OPENCODE_DIR}/impact/recent.json (created on first file change)"
echo ""
echo "  Prerequisites remaining (if any):"
echo "    Docker:   https://docs.docker.com/get-docker/"
echo "    Ollama:   https://ollama.com/download"
echo "    Beads:    brew install beads  or install via script:"
echo "              curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash"
echo ""
