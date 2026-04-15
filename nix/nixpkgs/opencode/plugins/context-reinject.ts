import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { createLogger } from "./devlogs";

const log = createLogger("opencode-context-reinject");

const AGENTS_LOCATIONS = ["AGENTS.md", ".opencode/AGENTS.md"] as const;

async function readAgentsMd(directory: string): Promise<string | null> {
	for (const loc of AGENTS_LOCATIONS) {
		const file = Bun.file(`${directory}/${loc}`);
		if (await file.exists()) {
			return await file.text();
		}
	}
	return null;
}

const plugin: Plugin = async (ctx) => {
	log.debug("plugin loaded");

	return {
		"experimental.chat.system.transform": async (_input, output) => {
			const content = await readAgentsMd(ctx.directory);
			if (content) {
				output.system.push(`<project-rules>\n${content}\n</project-rules>`);
				log.debug("injected AGENTS.md into system prompt");
			}
		},

		tool: {
			reinject_context: tool({
				description:
					"Re-read and return the AGENTS.md guidelines. Use when you need to explicitly review project rules mid-session.",
				args: {},
				async execute(_args, toolCtx) {
					const content = await readAgentsMd(toolCtx.directory);
					if (content) {
						log.info("manual reinjection requested");
						return content;
					}
					log.warning("AGENTS.md not found");
					return "No AGENTS.md found in working directory.";
				},
			}),
		},
	};
};

export default plugin;
