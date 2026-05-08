import type { Plugin } from "@opencode-ai/plugin"
import { spawn, spawnSync } from "child_process"
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "fs"
import { join } from "path"

interface ImpactEntry {
  timestamp: string
  file: string
  highRisk: boolean
  blastRadius: number
  summary: string
  linkedTasks: string[]
}

interface ImpactState {
  lastCheck: string
  entries: ImpactEntry[]
}

interface BeadsTask {
  id: string
  title: string
  priority: string
  status: string
  type: string
  blocked: boolean
}

function runCommand(command: string, args: string[], cwd: string, timeoutMs = 15000): string | null {
  try {
    const result = spawnSync(command, args, {
      cwd,
      timeout: timeoutMs,
      maxBuffer: 512 * 1024,
      encoding: "utf-8",
    })
    if (result.error || result.status !== 0) return null
    return result.stdout.trim() || null
  } catch {
    return null
  }
}

function mcpCall(
  toolName: string,
  args: Record<string, unknown>,
  cwd: string
): Promise<string | null> {
  return new Promise((resolve) => {
    const child = spawn("/opt/homebrew/bin/npx", ["-y", "socraticode"], {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
    })

    const chunks: string[] = []
    let settled = false

    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      child.kill()
      resolve(null)
    }, 30000)

    const initMsg =
      JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "impact-watcher", version: "1.0.0" },
        },
      }) +
      "\n" +
      JSON.stringify({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: toolName, arguments: args },
      }) +
      "\n"

    child.stdin.write(initMsg)

    child.stdout.on("data", (data: Buffer) => {
      chunks.push(data.toString())
    })

    child.stderr.on("data", () => {})

    let lastParsed = ""

    const tryParse = () => {
      const output = chunks.join("")
      const lines = output.split("\n").filter(Boolean)
      if (lines.length < 2) return

      const lastLine = lines[lines.length - 1]
      if (lastLine === lastParsed) return
      lastParsed = lastLine

      try {
        const parsed = JSON.parse(lastLine)
        if (parsed.id === 2) {
          if (settled) return
          settled = true
          clearTimeout(timer)
          child.kill()
          resolve(
            parsed.error
              ? null
              : (parsed.result?.content?.[0]?.text ?? null)
          )
        }
      } catch {}
    }

    child.stdout.on("data", () => tryParse())

    child.on("close", () => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      tryParse()
    })
  })
}

function countResults(impactText: string): number {
  return impactText.split("\n").filter((l) =>
    l.match(/score:\s*\d+\.\d+/)
  ).length
}

function loadImpactState(statePath: string): ImpactState {
  try {
    return JSON.parse(readFileSync(statePath, "utf-8"))
  } catch {
    return { lastCheck: "", entries: [] }
  }
}

function buildImpactContext(state: ImpactState): string | null {
  if (state.entries.length === 0) return null

  const lines = state.entries.map((e) => {
    let extra = ""
    if (e.linkedTasks.length > 0) {
      extra = ` [linked: ${e.linkedTasks.join(", ")}]`
    }
    return `  - ${e.file} → ${e.blastRadius} files affected (${e.highRisk ? "HIGH RISK" : "moderate"})${extra}`
  })

  const highRiskCount = state.entries.filter((e) => e.highRisk).length
  const header =
    highRiskCount > 0
      ? `## IMPACT WARNING: Recent file changes with blast radius detected`
      : `## Impact: Recent file changes`

  return `${header}\n${lines.join("\n")}\n\nFix any breaking references in affected files before proceeding.`
}

function ensureBeadsInitialized(worktree: string): boolean {
  const beadsDir = join(worktree, ".beads")
  if (existsSync(beadsDir)) return true

  const dirName = worktree.split("/").pop() ?? "project"
  const sanitized = dirName.replace(/[^a-zA-Z0-9_-]/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "project"

  const result = runCommand("/opt/homebrew/bin/bd", ["init", "--quiet", "--stealth", "--prefix", sanitized], worktree, 10000)
  return result !== null
}

function parseBeadsReady(worktree: string): BeadsTask[] {
  const json = runCommand("/opt/homebrew/bin/bd", ["ready", "--json"], worktree, 8000)
  if (!json) return []

  try {
    const parsed = JSON.parse(json)
    if (!Array.isArray(parsed)) return []
    return parsed.map((t: Record<string, unknown>) => ({
      id: (t.id ?? t.ID ?? "") as string,
      title: (t.title ?? t.Title ?? "") as string,
      priority: (t.priority ?? t.Priority ?? "") as string,
      status: (t.status ?? t.Status ?? "") as string,
      type: (t.type ?? t.Type ?? "") as string,
      blocked: (t.blocked ?? false) as boolean,
    }))
  } catch {
    return []
  }
}

function parseBeadsOpen(worktree: string): BeadsTask[] {
  const json = runCommand("/opt/homebrew/bin/bd", ["list", "--status", "open", "--json"], worktree, 8000)
  if (!json) return []

  try {
    const parsed = JSON.parse(json)
    if (!Array.isArray(parsed)) return []
    return parsed.map((t: Record<string, unknown>) => ({
      id: (t.id ?? t.ID ?? "") as string,
      title: (t.title ?? t.Title ?? "") as string,
      priority: (t.priority ?? t.Priority ?? "") as string,
      status: (t.status ?? t.Status ?? "") as string,
      type: (t.type ?? t.Type ?? "") as string,
      blocked: (t.blocked ?? false) as boolean,
    }))
  } catch {
    return []
  }
}

function buildBeadsContext(worktree: string): string | null {
  const beadsDir = join(worktree, ".beads")
  if (!existsSync(beadsDir)) return null

  const ready = parseBeadsReady(worktree)
  const open = parseBeadsOpen(worktree)

  if (ready.length === 0 && open.length === 0) return null

  const parts: string[] = []

  if (ready.length > 0) {
    parts.push("## Beads: Unblocked Tasks Ready to Work")
    for (const t of ready) {
      parts.push(`  - ${t.id} [${t.priority}] ${t.title}`)
    }
  }

  const blocked = open.filter((t) => t.blocked)
  if (blocked.length > 0) {
    parts.push("\n## Beads: Blocked Tasks")
    for (const t of blocked) {
      parts.push(`  - ${t.id} [${t.priority}] ${t.title}`)
    }
  }

  return parts.join("\n")
}

function linkImpactToTasks(
  filePath: string,
  impactText: string,
  worktree: string
): { linkedTaskIds: string[]; taskImpactNotes: string } {
  const open = parseBeadsOpen(worktree)
  const linked: string[] = []
  const notes: string[] = []

  const impactLower = impactText.toLowerCase()
  const pathLower = filePath.toLowerCase()

  for (const task of open) {
    const taskLower = (task.title + " " + task.id).toLowerCase()
    const matches =
      impactLower.includes(taskLower) ||
      impactLower.includes(task.id.toLowerCase()) ||
      taskLower.includes(pathLower.split("/").pop()?.replace(/\.[^.]+$/, "") ?? "")

    if (matches) {
      linked.push(task.id)
      notes.push(`  - ${task.id}: ${task.title} may be affected by changes to ${filePath}`)
    }
  }

  return {
    linkedTaskIds: linked.slice(0, 3),
    taskImpactNotes: notes.length > 0
      ? `\n## Beads: Tasks Potentially Affected by Recent Changes\n${notes.join("\n")}`
      : "",
  }
}

function runBeadsSync(worktree: string): void {
  const beadsDir = join(worktree, ".beads")
  if (!existsSync(beadsDir)) return

  runCommand("/opt/homebrew/bin/bd", ["dolt", "commit"], worktree, 10000)
  runCommand("/opt/homebrew/bin/bd", ["dolt", "push"], worktree, 10000)
}

const lastAnalyzed = new Map<string, number>()

export const ImpactWatcher: Plugin = async ({
  client,
  directory,
  worktree,
}) => {
  const impactDir = join(directory, "impact")
  if (!existsSync(impactDir)) mkdirSync(impactDir, { recursive: true })
  const statePath = join(impactDir, "recent.json")

  ensureBeadsInitialized(worktree)

  return {
    "chat.message": async (_input, output) => {
      const state = loadImpactState(statePath)
      const impactCtx = buildImpactContext(state)
      const beadsCtx = buildBeadsContext(worktree)
      const taskLinks: string[] = []

      for (const entry of state.entries) {
        if (entry.linkedTasks.length > 0) {
          taskLinks.push(
            `  - ${entry.file}: ${entry.linkedTasks.join(", ")}`
          )
        }
      }

      const parts = [impactCtx, beadsCtx].filter(Boolean) as string[]
      if (taskLinks.length > 0) {
        parts.push(`## Task-Impact Links\n${taskLinks.join("\n")}`)
      }

      if (parts.length > 0) {
        output.system = (output.system ?? "") + "\n\n" + parts.join("\n\n")
      }
    },

    "tool.execute.after": async (_input) => {
      const state = loadImpactState(statePath)
      const hasHighRisk = state.entries.some((e) => e.highRisk)
      if (hasHighRisk) {
        runBeadsSync(worktree)
      }
    },

    "experimental.session.compacting": async () => {
      runBeadsSync(worktree)
    },

    event: async ({ event }) => {
      if (event.type !== "file.watcher.updated") return

      const props = event.properties as Record<string, unknown> | undefined
      const filePath = props?.path as string | undefined
      if (!filePath) return

      const now = Date.now()
      const last = lastAnalyzed.get(filePath) ?? 0
      if (now - last < 15000) return
      lastAnalyzed.set(filePath, now)

      ensureBeadsInitialized(worktree)

      const impactText = await mcpCall(
        "codebase_impact",
        { target: filePath },
        worktree
      )
      if (!impactText) return

      const blastRadius = countResults(impactText)
      const highRisk = blastRadius > 3

      const { linkedTaskIds, taskImpactNotes } = linkImpactToTasks(
        filePath,
        impactText,
        worktree
      )

      const entry: ImpactEntry = {
        timestamp: new Date().toISOString(),
        file: filePath,
        highRisk,
        blastRadius,
        summary: impactText.slice(0, 500),
        linkedTasks: linkedTaskIds,
      }

      const state = loadImpactState(statePath)
      state.lastCheck = new Date().toISOString()
      state.entries.unshift(entry)
      state.entries = state.entries.slice(0, 10)

      writeFileSync(statePath, JSON.stringify(state, null, 2))

      if (highRisk) {
        runBeadsSync(worktree)

        try {
          await client.tui.showToast({
            body: {
              message: `${filePath} changed — impacts ${blastRadius} files${linkedTaskIds.length > 0 ? ` | linked tasks: ${linkedTaskIds.join(", ")}` : ""}`,
              variant: "warning",
            },
          })
        } catch {}
      }
    },
  }
}
