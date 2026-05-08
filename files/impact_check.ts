import { tool } from "@opencode-ai/plugin"
import { spawn } from "child_process"

const NODE_PATH = "__NODE_PATH__"
const NPM_PATH = "__NPM_PATH__"

function mcpCall(
  toolName: string,
  args: Record<string, unknown>,
  cwd: string,
  timeoutMs = 60000
): Promise<string | null> {
  return new Promise((resolve) => {
    const child = spawn(NPM_PATH, ["-y", "socraticode"], {
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
    }, timeoutMs)

    const initMsg =
      JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "impact-check", version: "1.0.0" },
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
          if (parsed.error) {
            resolve(`Error: ${parsed.error.message}`)
          } else {
            resolve(parsed.result?.content?.[0]?.text ?? null)
          }
        }
      } catch {}
    }

    child.stdout.on("data", () => {
      tryParse()
    })

    child.on("close", () => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      tryParse()
    })
  })
}

export default tool({
  description:
    "Analyze the impact of changing a file or symbol before making edits. Returns which files and functions would break. Use BEFORE refactoring, renaming, deleting, or modifying shared schemas/types/utilities.",
  args: {
    filePath: tool.schema
      .string()
      .describe("Path to the file to check (relative to project root or absolute)"),
    projectPath: tool.schema
      .string()
      .optional()
      .describe("Absolute path to the project. Defaults to current working directory."),
    symbolName: tool.schema
      .string()
      .optional()
      .describe("Optional symbol/function name to check specifically (e.g. 'formatCurrency')"),
  },
  async execute(args) {
    const projectPath = args.projectPath || process.cwd()
    const sections: string[] = []

    if (args.symbolName) {
      const symbol = await mcpCall(
        "codebase_symbol",
        { name: args.symbolName, projectPath },
        projectPath
      )
      if (symbol) sections.push(`### Symbol: ${args.symbolName}\n${symbol}`)
    }

    const impact = await mcpCall(
      "codebase_impact",
      { target: args.filePath, projectPath },
      projectPath
    )

    if (impact) {
      sections.push(`### Impact Analysis for ${args.filePath}\n${impact}`)
    }

    if (sections.length === 0) {
      return "No impact data available. The project may not be indexed yet. Try running codebase_index first."
    }

    const blastRadius = (impact ?? "").match(/(\d+)\s*(?:file|affected)/i)?.[1]
    if (blastRadius && parseInt(blastRadius) > 5) {
      sections.unshift("## HIGH RISK — Large Blast Radius Detected")
    }

    return sections.join("\n\n")
  },
})
