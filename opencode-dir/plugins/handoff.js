// OpenCode plugin: after every Mammouth reply, write <workspace>/HANDOFF.md (and handoff/latest.md)
// so Claude Code can continue where Mammouth stopped. Counterpart of handoff/handoff.ps1.
// The workspace is the folder that contains the handoff folder (three levels above this file).
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..")

const inside = (p) => {
  const full = path.resolve(p).toLowerCase()
  const root = path.resolve(ROOT).toLowerCase()
  return full === root || full.startsWith(root + path.sep)
}

const shorten = (s, max) => {
  s = (s || "").trim()
  return s.length <= max ? s : s.slice(0, max) + " ...[cut]"
}

const textOf = (parts) =>
  parts
    .filter((p) => p.type === "text" && !p.synthetic && p.text && p.text.trim())
    .map((p) => p.text)
    .join("\n")

function describeTool(p) {
  const input = (p.state && p.state.input) || {}
  const file = input.filePath || input.path
  if (["edit", "write", "read", "patch"].includes(p.tool) && file) return `${p.tool} ${file}`
  if (p.tool === "bash") return `bash: ${input.description || shorten(input.command, 150)}`
  return p.tool
}

function build(messages, directory, status, model) {
  const users = []
  const actions = []
  const files = []
  let lastReply = ""
  for (const m of messages) {
    const parts = m.parts || []
    if (m.info.role === "user") {
      const t = textOf(parts)
      if (t) {
        users.push(t)
        lastReply = ""
      }
    } else if (m.info.role === "assistant") {
      const t = textOf(parts)
      if (t) lastReply = t
      for (const p of parts) {
        if (p.type !== "tool") continue
        actions.push(describeTool(p))
        const f = p.state && p.state.input && p.state.input.filePath
        if (["edit", "write", "patch"].includes(p.tool) && f && !files.includes(f)) files.push(f)
      }
    }
  }

  const now = new Date()
  const stamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")} ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`
  const out = []
  out.push("# HANDOFF - continue this work", "")
  out.push(`Written by: **Mammouth via OpenCode** (${model || "unknown model"}), ${stamp}. Status: **${status}**.`)
  out.push(`Project folder: \`${directory}\``, "")
  out.push("## How to continue")
  out.push("- The **last user request** below is the current task. Check its state in the files before changing anything.")
  out.push("- If the last reply ends mid-task or the status says STOPPED, finish that step first.")
  out.push("- Read CLAUDE.md / README.md in the project if they exist.")
  out.push(`- Long-term notes: \`${ROOT}\\.claude-memory\\MEMORY.md\`.`)
  out.push("- Answer in the language the user writes in.", "")
  out.push("## How the session started")
  for (const u of users.slice(0, 3)) out.push("> " + shorten(u, 1200).replace(/\n/g, "\n> "), "")
  out.push("## Latest user requests (oldest first, last one = current task)")
  users.slice(-5).forEach((u, i) => out.push(`${i + 1}. ${shorten(u, 1500).replace(/\n/g, "\n   ")}`))
  out.push("", "## Mammouth's last reply")
  out.push(lastReply ? shorten(lastReply, 5000) : "_(none after the last request - Mammouth was still working when it stopped)_")
  out.push("", "## Last actions (most recent last)")
  for (const a of actions.slice(-12)) out.push(`- ${a}`)
  out.push("", "## Files changed in this session")
  if (files.length) for (const f of files) out.push(`- \`${f}\``)
  else out.push("_(none)_")
  return out.join("\n") + "\n"
}

// Diagnostics: one line per plugin start and per event, so a silent failure is visible.
const DEBUG_LOG = path.join(ROOT, "handoff", "plugin-debug.log")
const debug = (msg) => {
  try {
    if (fs.existsSync(DEBUG_LOG) && fs.statSync(DEBUG_LOG).size > 200000) fs.writeFileSync(DEBUG_LOG, "")
    fs.appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${msg}\n`, "utf8")
  } catch {}
}

export const HandoffPlugin = async ({ client, directory }) => {
  // Loaded from both plugin/ and plugins/ (folder name differs between OpenCode versions); register once.
  if (globalThis.__cloudeHandoffLoaded) return {}
  globalThis.__cloudeHandoffLoaded = true
  debug(`plugin loaded, directory=${directory}`)
  return {
    event: async ({ event }) => {
      const props = event.properties || {}
      const idle =
        event.type === "session.idle" ||
        (event.type === "session.status" && props.status && props.status.type === "idle")
      if (!idle && event.type !== "session.error") return
      debug(`event ${event.type} -> writing handoff`)
      const sessionID = props.sessionID || (props.info && props.info.sessionID)
      if (!sessionID) return
      if (!directory || !inside(directory)) debug(`warning: OpenCode runs outside the workspace (${directory}); handoff still goes to the workspace`)
      try {
        const res = await client.session.messages({ path: { id: sessionID } })
        const messages = (res && res.data) || res || []
        if (!Array.isArray(messages) || !messages.length) return
        const lastAssistant = [...messages].reverse().find((m) => m.info.role === "assistant")
        const model = lastAssistant && lastAssistant.info.modelID
        const status =
          event.type === "session.error"
            ? "STOPPED UNEXPECTEDLY (error or limit) - the last step may be unfinished"
            : "Mammouth finished its last reply normally"
        const text = build(messages, directory, status, model)
        const note = inside(directory || "")
          ? ""
          : `\n> **Warning:** this Mammouth session ran in \`${directory}\`, outside the workspace folder.\n`
        fs.writeFileSync(path.join(ROOT, "HANDOFF.md"), text.replace("\n## How to continue", note + "\n## How to continue"), "utf8")
        fs.writeFileSync(path.join(ROOT, "handoff", "latest.md"), text, "utf8")
      } catch (err) {
        fs.writeFileSync(path.join(ROOT, "handoff", "plugin-error.txt"), String((err && err.stack) || err), "utf8")
      }
    },
  }
}
