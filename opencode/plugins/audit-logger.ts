/**
 * audit-logger
 * OpenCode plugin that replicates the Cursor hooks audit logging behavior.
 *
 * Cursor Hook → OpenCode Event mapping:
 *   beforeSubmitPrompt  → message.updated (role === "user")
 *   afterMCPExecution   → tool.execute.after (for MCP tools)
 *   afterFileEdit       → file.edited
 *
 * Calls the same ~/.cursor/codeassist/hooks-scripts/audit-logger.sh script
 * with identical JSON payloads via stdin to produce identical audit logs.
 *
 * Audit logs are written to: ${TMPDIR}/codeassist/
 */

import * as os from "node:os"
import * as path from "node:path"
import type { Plugin } from "@opencode-ai/plugin"
import type { Event } from "@opencode-ai/sdk"

const AUDIT_SCRIPT = path.join(os.homedir(), ".cursor", "codeassist", "hooks-scripts", "audit-logger.sh")

/**
 * Invoke the audit-logger.sh script with the given event type and JSON payload via stdin.
 * Fire-and-forget: errors are logged but never propagated to the caller.
 */
async function invokeAuditScript(
	eventType: string,
	payload: Record<string, unknown>,
	$: typeof Bun.$,
	log: (msg: string) => void,
): Promise<void> {
	try {
		const jsonPayload = JSON.stringify(payload)
		const proc = Bun.spawn(["bash", AUDIT_SCRIPT, eventType], {
			stdin: "pipe",
			stdout: "pipe",
			stderr: "pipe",
		})

		// Write JSON payload to stdin
		const writer = proc.stdin.getWriter()
		await writer.write(new TextEncoder().encode(jsonPayload))
		await writer.close()

		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
			proc.exited,
		])

		if (exitCode !== 0) {
			log(`[audit-logger] ${eventType} script exited ${exitCode}: ${stderr.trim()}`)
		}
	} catch (error) {
		log(`[audit-logger] ${eventType} script error: ${error}`)
	}
}

export const AuditLoggerPlugin: Plugin = async (ctx) => {
	const { client, directory } = ctx

	const log = (msg: string) =>
		client.app
			.log({ body: { service: "audit-logger", level: "info", message: msg } })
			.catch(() => {})

	const logError = (msg: string) =>
		client.app
			.log({ body: { service: "audit-logger", level: "error", message: msg } })
			.catch(() => {})

	// Verify audit script exists at startup
	try {
		const file = Bun.file(AUDIT_SCRIPT)
		if (!(await file.exists())) {
			logError(
				`[audit-logger] Audit script not found: ${AUDIT_SCRIPT}. ` +
					"Ensure ~/.cursor/codeassist/hooks-scripts/audit-logger.sh exists.",
			)
		}
	} catch {
		logError(`[audit-logger] Failed to check audit script: ${AUDIT_SCRIPT}`)
	}

	return {
		/**
		 * beforeSubmitPrompt equivalent:
		 * Fires on message.updated events for user messages.
		 * Caches the user prompt with session/message IDs.
		 */
		event: async ({ event }: { event: Event }): Promise<void> => {
			if (event.type === "message.updated") {
				const props = event.properties as Record<string, unknown>
				const role = props?.role as string | undefined
				const sessionID = props?.sessionID as string | undefined

				// Only cache user prompts (equivalent to beforeSubmitPrompt)
				if (role === "user" && sessionID) {
					const content = props?.content as string | undefined
					const messageID = props?.id as string | undefined

					await invokeAuditScript(
						"beforeSubmitPrompt",
						{
							conversation_id: sessionID,
							generation_id: messageID ?? `gen_${Date.now()}_${process.pid}`,
							prompt: content ?? "",
						},
						Bun.$,
						(msg) => log(msg),
					)
				}
			}
		},

		/**
		 * afterMCPExecution equivalent:
		 * Fires after any tool execution. We filter for MCP-origin tools
		 * and pass tool_name, tool_input, and result_json to the script.
		 */
		"tool.execute.after": async (
			input: {
				tool: string
				sessionID: string
				messageID?: string
				callID?: string
				metadata?: Record<string, unknown>
			},
			output: {
				args: Record<string, unknown>
				result: unknown
			},
		): Promise<void> => {
			// Determine if this is an MCP tool (non-builtin tools are MCP tools).
			// Built-in tools: read, write, edit, bash, glob, grep, todowrite, task, question, webfetch
			const builtinTools = new Set([
				"read",
				"write",
				"edit",
				"bash",
				"glob",
				"grep",
				"todowrite",
				"task",
				"question",
				"webfetch",
				"skill",
			])

			// Only track MCP (non-builtin) tool executions
			if (builtinTools.has(input.tool)) return

			await invokeAuditScript(
				"afterMCPExecution",
				{
					conversation_id: input.sessionID,
					generation_id: input.messageID ?? input.callID ?? `gen_${Date.now()}_${process.pid}`,
					tool_name: input.tool,
					tool_input: JSON.stringify(output.args ?? {}),
					result_json: typeof output.result === "string" ? output.result : JSON.stringify(output.result ?? ""),
				},
				Bun.$,
				(msg) => log(msg),
			)
		},

		/**
		 * afterFileEdit equivalent:
		 * Fires when any file is edited. Passes file path, old/new content,
		 * and session identifiers to the audit script.
		 */
		"file.edited": async (input: {
			sessionID: string
			messageID?: string
			file: string
			content?: string
			oldContent?: string
			edits?: Array<{ old_string?: string; new_string?: string }>
		}): Promise<void> => {
			// Build edits array matching Cursor's format
			const edits = input.edits ?? [
				{
					old_string: input.oldContent ?? "",
					new_string: input.content ?? "",
				},
			]

			await invokeAuditScript(
				"afterFileEdit",
				{
					conversation_id: input.sessionID,
					generation_id: input.messageID ?? `gen_${Date.now()}_${process.pid}`,
					file_path: input.file,
					edits,
				},
				Bun.$,
				(msg) => log(msg),
			)
		},
	}
}

export default AuditLoggerPlugin
