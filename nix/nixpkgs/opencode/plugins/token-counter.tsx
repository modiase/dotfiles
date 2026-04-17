/** @jsxImportSource @opentui/solid */

import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui";
import type { AssistantMessage } from "@opencode-ai/sdk/v2";
import { Show } from "solid-js";

const fmt = (n: number): string => {
	if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
	if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
	return `${n}`;
};

const money = new Intl.NumberFormat("en-US", {
	style: "currency",
	currency: "USD",
	minimumFractionDigits: 2,
	maximumFractionDigits: 4,
});

const tui: TuiPlugin = async (api) => {
	api.slots.register({
		slots: {
			sidebar_content(ctx, props: { session_id: string }) {
				const messages = () => api.state.session.messages(props.session_id);
				const status = () => api.state.session.status(props.session_id);
				const busy = () => status()?.type === "busy";

				const totals = () => {
					const msgs = messages();
					let input = 0;
					let output = 0;
					let cost = 0;
					for (const msg of msgs) {
						if (msg.role !== "assistant") continue;
						const a = msg as AssistantMessage;
						input += a.tokens.input;
						output += a.tokens.output;
						cost += a.cost;
					}
					return { input, output, cost };
				};

				return (
					<Show when={busy()}>
						<box flexDirection="row" gap={1}>
							<text fg={ctx.theme.current.success}>
								● ↓{fmt(totals().input)} ↑{fmt(totals().output)}
							</text>
							<Show when={totals().cost > 0}>
								<text fg={ctx.theme.current.textMuted}>
									{money.format(totals().cost)}
								</text>
							</Show>
						</box>
					</Show>
				);
			},
		},
	});
};

const plugin: TuiPluginModule = {
	id: "token-counter",
	tui,
};

export default plugin;
