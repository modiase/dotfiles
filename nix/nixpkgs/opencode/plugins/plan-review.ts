import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { type Plugin, tool } from "@opencode-ai/plugin";
import { createLogger } from "./devlogs";

const log = createLogger("opencode-plan-review");

const TMUX_NVIM_SELECT = "@tmuxNvimSelect@";
const NVR = "@nvr@";

const plugin: Plugin = async ({ $, client }) => {
	log.debug("plugin loaded");

	return {
		tool: {
			submit_plan: tool({
				description:
					"Submit a plan for user review in neovim. Opens read-only with accept/reject controls. Blocks until the user responds.",
				args: {
					content: tool.schema
						.string()
						.describe(
							"The plan content in markdown. Use - [ ] checkboxes for actionable items.",
						),
					title: tool.schema
						.string()
						.optional()
						.describe("Optional title for the plan"),
				},
				async execute(args, ctx) {
					let nvimSocket: string | undefined;
					const uuid = randomUUID();
					const plansDir = `${ctx.directory}/.opencode/plans`;
					mkdirSync(plansDir, { recursive: true });

					const planFile = `${plansDir}/${uuid}.md`;
					const fifo = `/tmp/opencode-plan-${uuid}.fifo`;
					log.debug(`execute: plan=${planFile}`);

					const content = args.title
						? `# ${args.title}\n\n${args.content}`
						: args.content;
					await Bun.write(planFile, content);
					await $`mkfifo ${fifo}`.quiet();

					try {
						log.debug(
							`execute: TMUX_PANE=${process.env.TMUX_PANE} TMUX=${process.env.TMUX}`,
						);
						const nvimResult = await $`${TMUX_NVIM_SELECT}`.quiet().nothrow();
						log.debug(
							`execute: tmux-nvim-select exit=${nvimResult.exitCode} stdout=${nvimResult.text().trim()} stderr=${nvimResult.stderr.toString().trim()}`,
						);
						if (nvimResult.exitCode !== 0) {
							log.warning("execute: tmux-nvim-select failed");
							return `Plan saved to ${planFile} but could not open in neovim (no tmux/nvim session). Review manually.`;
						}

						const env: Record<string, string> = {};
						for (const line of nvimResult.text().trim().split("\n")) {
							const eq = line.indexOf("=");
							if (eq > 0) env[line.slice(0, eq)] = line.slice(eq + 1);
						}
						log.debug(
							`execute: NVIM_SOCKET=${env.NVIM_SOCKET} TARGET_PANE=${env.TARGET_PANE}`,
						);

						nvimSocket = env.NVIM_SOCKET;
						if (!nvimSocket) {
							log.warning("execute: no NVIM_SOCKET");
							return `Plan saved to ${planFile} but no neovim socket found. Review manually.`;
						}

						const luaCmd = `lua require('utils.opencode-plan').open('${planFile}', '${fifo}')`;
						log.debug(`execute: nvr cmd=${luaCmd}`);
						const nvrResult =
							await $`${NVR} --servername ${nvimSocket} -c ${luaCmd}`
								.quiet()
								.nothrow();
						if (nvrResult.exitCode !== 0) {
							log.warning(
								`execute: nvr failed exit=${nvrResult.exitCode} stderr=${nvrResult.stderr.toString().trim()}`,
							);
						}

						if (env.TARGET_PANE) {
							await $`tmux select-pane -t ${env.TARGET_PANE}`.quiet().nothrow();
						}

						log.debug("execute: blocking on fifo");
						const response = await new Promise<string>((resolve, reject) => {
							if (ctx.abort.aborted) {
								resolve("reject:Plan review cancelled");
								return;
							}
							const onAbort = () => resolve("reject:Plan review cancelled");
							ctx.abort.addEventListener("abort", onAbort, { once: true });

							$`cat ${fifo}`
								.quiet()
								.text()
								.then((text) => {
									ctx.abort.removeEventListener("abort", onAbort);
									resolve(text.trim());
								})
								.catch((err) => {
									ctx.abort.removeEventListener("abort", onAbort);
									reject(err);
								});
						});

						log.debug(`execute: response=${response}`);

						if (response.startsWith("reject:")) {
							const reason = response.slice("reject:".length);
							const updatedPlan = await Bun.file(planFile).text();
							return `Plan rejected. Feedback: ${reason}\n\nPlan with inline comments:\n${updatedPlan}`;
						}

						const planContent = await Bun.file(planFile).text();
						log.debug("execute: switching to build agent");
						await client.session.promptAsync({
							path: { id: ctx.sessionID },
							body: {
								agent: "build",
								parts: [
									{
										type: "text",
										text: `Plan accepted. Implement the following plan:\n\n${planContent}`,
									},
								],
							},
						});

						return `Plan accepted and build agent triggered. Plan file: ${planFile}`;
					} finally {
						if (nvimSocket) {
							await $`${NVR} --servername ${nvimSocket} -c ${`lua require('utils.opencode-plan').close_by_fifo('${fifo}')`}`
								.quiet()
								.nothrow();
						}
						await $`rm -f ${fifo}`.quiet().nothrow();
					}
				},
			}),
		},
	};
};

export default plugin;
