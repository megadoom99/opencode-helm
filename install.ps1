# ──────────────────────────────────────────────
# HELM — OpenCode Impact Analysis System Installer
# Windows (PowerShell)
# ──────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OpenCodeDir = "$env:USERPROFILE\.config\opencode"
$OpenCodeJson = "$OpenCodeDir\opencode.json"

Write-Host ""
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  HELM — Impact Analysis System for OpenCode" -ForegroundColor Cyan
Write-Host "  OS: Windows" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ──────────── BINARY DETECTION ────────────

function Find-Binary($name) {
    try { return (Get-Command $name -ErrorAction Stop).Source } catch { return $null }
}

$NodeBin = Find-Binary "node"
$NpmBin  = Find-Binary "npm"
$NpxBin  = Find-Binary "npx"
$BdBin   = Find-Binary "bd"

Write-Host "Resolved binaries:" -ForegroundColor Yellow
Write-Host "  node  = $($NodeBin ?? 'NOT FOUND')"
Write-Host "  npm   = $($NpmBin ?? 'NOT FOUND')"
Write-Host "  npx   = $($NpxBin ?? 'NOT FOUND')"
Write-Host "  bd    = $($BdBin ?? 'NOT FOUND')"
Write-Host ""

if (-not $NodeBin -or -not $NpmBin -or -not $NpxBin) {
    Write-Host "ERROR: Node.js/npm/npx not found on PATH." -ForegroundColor Red
    Write-Host "Install Node.js: https://nodejs.org/ or 'winget install OpenJS.NodeJS'"
    exit 1
}

# ──────────── PREREQUISITE CHECKS ────────────

function Check-Optional($name, $cmd, $url) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ $name found" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ $name not found — install: $url" -ForegroundColor Yellow
    }
}

Write-Host "Prerequisites:" -ForegroundColor Yellow
Check-Optional "Docker"       "docker"  "https://docs.docker.com/desktop/setup/install/windows-install/"
Check-Optional "Ollama"       "ollama"  "https://ollama.com/download/windows"
Check-Optional "Beads (bd)"   "bd"      "winget install beads"
Write-Host ""

# ──────────── CREATE DIRECTORIES ────────────

New-Item -ItemType Directory -Force -Path "$OpenCodeDir\plugins" | Out-Null
New-Item -ItemType Directory -Force -Path "$OpenCodeDir\tools"    | Out-Null
New-Item -ItemType Directory -Force -Path "$OpenCodeDir\impact"   | Out-Null
Write-Host "Created directories:" -ForegroundColor Green
Write-Host "  $OpenCodeDir\plugins\"
Write-Host "  $OpenCodeDir\tools\"
Write-Host "  $OpenCodeDir\impact\"
Write-Host ""

# ──────────── ENSURE PACKAGE.JSON ────────────

$PackageJson = "$OpenCodeDir\package.json"
if (-not (Test-Path $PackageJson)) {
    @'
{
  "dependencies": {
    "@opencode-ai/plugin": "^1"
  }
}
'@ | Out-File -FilePath $PackageJson -Encoding utf8
    Write-Host "Created $PackageJson" -ForegroundColor Green
} else {
    Write-Host "Using existing $PackageJson" -ForegroundColor Green
}

& $NpmBin install --prefix $OpenCodeDir --save @opencode-ai/plugin 2>$null
Write-Host ""

# ──────────── WRITE PLUGIN & TOOL FILES ────────────

$NpmDir = Split-Path -Parent $NpxBin

function Write-Template($srcName, $dstRel) {
    $src = Join-Path $ScriptDir "files\$srcName"
    $dst = Join-Path $OpenCodeDir $dstRel

    if (-not (Test-Path $src)) {
        Write-Host "ERROR: $src not found" -ForegroundColor Red
        exit 1
    }

    $content = Get-Content $src -Raw
    $content = $content.Replace('__NODE_PATH__', $NodeBin)
    $content = $content.Replace('__NPM_PATH__',  $NpxBin)
    $content = $content.Replace('__BD_PATH__',   ($BdBin ?? 'bd'))
    $content | Out-File -FilePath $dst -Encoding utf8 -NoNewline
    Write-Host "  ✓ $dst" -ForegroundColor Green
}

Write-Host "Writing HELM files:" -ForegroundColor Yellow
Write-Template "impact-watcher.ts" "plugins\impact-watcher.ts"
Write-Template "impact_check.ts"   "tools\impact_check.ts"
Copy-Item "$ScriptDir\files\impact-context.md" "$OpenCodeDir\impact-context.md" -Force
Write-Host "  ✓ $OpenCodeDir\impact-context.md" -ForegroundColor Green
Write-Host ""

# ──────────── MERGE INTO OPENCODE.JSON ────────────

Write-Host "Merging into opencode.json:" -ForegroundColor Yellow

$mergeScript = @"
const fs = require('fs');
const path = process.argv[1] || '$OpenCodeJson'.replace(/\\/g,'\\\\');
const nodeBin = process.argv[2] || '$($NodeBin.Replace('\','\\'))';
const npxBin  = process.argv[3] || '$($NpxBin.Replace('\','\\'))';
const home    = process.argv[4] || '$env:USERPROFILE'.replace(/\\/g,'\\\\');
const shell   = process.argv[5] || 'pwsh';
const npmDir  = path.dirname(npxBin).replace(/\\/g,'/') || '';
const opencodeDir = process.argv[6] || '$($OpenCodeDir.Replace('\','\\'))';

let config = {};
try { config = JSON.parse(fs.readFileSync(path, 'utf-8')); } catch {}

config['\$schema'] = 'https://opencode.ai/config.json';
if (!config.mcp) config.mcp = {};

if (!config.mcp.socraticode) {
    config.mcp.socraticode = { type: 'local', command: [npxBin, '-y', 'socraticode'], enabled: true };
}

if (!config.mcp.crawl4ai) {
    config.mcp.crawl4ai = { type: 'local', command: [nodeBin, home + '/Downloads/OpenCodeProjects/crawl4ai-mcp.js'], enabled: true };
}

if (!config.mcp.github) {
    config.mcp.github = { type: 'local', command: [npxBin, '-y', '@modelcontextprotocol/server-github'], enabled: true };
}

if (!config.mcp.searxng) {
    config.mcp.searxng = { type: 'local', command: [npxBin, '-y', 'mcp-searxng'], enabled: true };
}

if (!config.mcp.filesystem) {
    config.mcp.filesystem = { type: 'local', command: [npxBin, '-y', '@modelcontextprotocol/server-filesystem', home + '/Downloads/OpenCodeProjects'], enabled: true };
}

if (!config.mcp['sequential-thinking']) {
    config.mcp['sequential-thinking'] = { type: 'local', command: [npxBin, '-y', '@modelcontextprotocol/server-sequential-thinking'], enabled: true };
}

const defaultEnv = {
    PATH: [npmDir, 'C:\\Program Files\\nodejs', process.env.PATH].filter(Boolean).join(';'),
    HOME: home
};

for (const [key, val] of Object.entries(config.mcp)) {
    if (val.type === 'local') {
        if (!val.environment) val.environment = {};
        val.environment.PATH = val.environment.PATH || defaultEnv.PATH;
        val.environment.HOME = val.environment.HOME || defaultEnv.HOME;
    }
}

if (config.lsp === undefined) config.lsp = true;
if (!config.shell) config.shell = shell;

if (!config.plugin) config.plugin = [];
if (!config.plugin.includes('./plugins/impact-watcher.ts')) {
    config.plugin.push('./plugins/impact-watcher.ts');
}

if (!config.tools) config.tools = {};
if (config.tools['codebase_*'] === undefined) config.tools['codebase_*'] = true;
if (config.tools['socraticode_*'] === undefined) config.tools['socraticode_*'] = true;
if (config.tools['impact_check'] === undefined) config.tools['impact_check'] = true;

if (!config.instructions) config.instructions = [];
const ctxPath = opencodeDir + '/impact-context.md';
if (!config.instructions.includes(ctxPath)) {
    config.instructions.push(ctxPath);
}

fs.writeFileSync(path, JSON.stringify(config, null, 2) + '\n', 'utf-8');
"@

$mergeScript | & $NodeBin - "$OpenCodeJson" "$NodeBin" "$NpxBin" "$env:USERPROFILE" "pwsh" "$OpenCodeDir"
Write-Host "  $OpenCodeJson — merged" -ForegroundColor Green
Write-Host ""

# ──────────── OPTIONAL: PULL EMBEDDING MODEL ────────────

if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Host "Ollama detected. Pulling nomic-embed-text (274MB)..." -ForegroundColor Yellow
    ollama pull nomic-embed-text 2>$null
    Write-Host "  Done" -ForegroundColor Green
    Write-Host ""
}

# ──────────── OPTIONAL: INIT BEADS ────────────

$cwd = Get-Location
if ($BdBin -and $cwd) {
    if (-not (Test-Path (Join-Path $cwd ".beads"))) {
        $dirName = Split-Path -Leaf $cwd
        $prefix = $dirName -replace '[^a-zA-Z0-9_-]', '-' -replace '^-*' -replace '-*$' -replace '(.{40}).+', '$1'
        if (-not $prefix) { $prefix = "project" }
        Write-Host "Initializing beads in $cwd..." -ForegroundColor Yellow
        & $BdBin init --quiet --stealth --prefix $prefix 2>$null
        Write-Host "  beads initialized (prefix: $prefix)" -ForegroundColor Green
        Write-Host ""
    }
}

# ──────────── SUMMARY ────────────

Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  HELM installation complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Restart OpenCode"
Write-Host "    2. Index your project: ask OpenCode 'Index this codebase'"
Write-Host "    3. Monitor: ask 'Check codebase health'"
Write-Host "    4. Search: ask 'Find where authentication is handled'"
Write-Host ""
Write-Host "  Files installed:"
Write-Host "    $OpenCodeDir\plugins\impact-watcher.ts"
Write-Host "    $OpenCodeDir\tools\impact_check.ts"
Write-Host "    $OpenCodeDir\impact-context.md"
Write-Host "    $OpenCodeJson (merged)"
Write-Host "    $OpenCodeDir\impact\recent.json (created on first file change)"
Write-Host ""
Write-Host "  Prerequisites remaining (if any):"
Write-Host "    Docker:   https://docs.docker.com/desktop/setup/install/windows-install/"
Write-Host "    Ollama:   https://ollama.com/download/windows"
Write-Host "    Beads:    winget install beads"
Write-Host ""
