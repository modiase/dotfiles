/** @jsxImportSource @opentui/solid */

import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui";
import type { AssistantMessage } from "@opencode-ai/sdk/v2";
import { createMemo, createSignal, Show } from "solid-js";

const fmt = (n: number): string => {
	if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
	if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
	return `${n}`;
};

function deriveActivity(part: {
	type: string;
	tool?: string;
	state?: { status: string };
}): string | null {
	switch (part.type) {
		case "reasoning":
			return "thinking";
		case "text":
			return "generating";
		case "tool": {
			if (part.state?.status === "running") return `running ${part.tool}`;
			if (part.tool) return `calling ${part.tool}`;
			return "generating";
		}
		default:
			return null;
	}
}

const CHARS_PER_TOKEN = 4;

interface StreamState {
	messageID: string;
	chars: number;
	startedAt: number;
}

const tui: TuiPlugin = async (api) => {
	const [latestParts, setLatestParts] = createSignal<
		Record<string, { type: string; tool?: string; state?: { status: string } }>
	>({});

	const [streamState, setStreamState] = createSignal<
		Record<string, StreamState>
	>({});

	api.event.on("message.part.updated", (evt) => {
		const part = evt.properties.part;
		setLatestParts((prev) => ({ ...prev, [part.sessionID]: part }));
	});

	api.event.on("message.part.delta", (evt) => {
		const { sessionID, messageID, delta } = evt.properties;
		const now = performance.now();
		setStreamState((prev) => {
			const cur = prev[sessionID];
			if (cur?.messageID !== messageID)
				return {
					...prev,
					[sessionID]: {
						messageID,
						chars: delta.length,
						startedAt: now,
					},
				};
			return {
				...prev,
				[sessionID]: { ...cur, chars: cur.chars + delta.length },
			};
		});
	});

	api.slots.register({
		slots: {
			session_prompt_right(ctx, props: { session_id: string }) {
				const messages = () => api.state.session.messages(props.session_id);
				const status = () => api.state.session.status(props.session_id);
				const busy = () => status()?.type === "busy";
				const retry = () => {
					const s = status();
					if (s?.type === "retry") return s;
					return null;
				};

				const activity = () => {
					if (!busy()) return null;
					const part = latestParts()[props.session_id];
					if (!part) return null;
					return deriveActivity(part);
				};

				const finalTokens = createMemo(() => {
					const msgs = messages();
					const last = msgs.findLast((m) => m.role === "assistant") as
						| AssistantMessage
						| undefined;
					if (!last) return { input: 0, output: 0 };
					return {
						input: last.tokens?.input ?? 0,
						output: last.tokens?.output ?? 0,
					};
				});

				const streamInfo = () => {
					const ss = streamState()[props.session_id];
					if (!ss) return { tokens: 0, tps: 0 };
					const tokens = Math.round(ss.chars / CHARS_PER_TOKEN);
					const elapsed = (performance.now() - ss.startedAt) / 1000;
					const tps = elapsed > 0.5 ? Math.round(tokens / elapsed) : 0;
					return { tokens, tps };
				};

				const isReceiving = () => activity() === "generating";

				const tokenText = () => {
					const ft = finalTokens();
					if (isReceiving()) {
						const si = streamInfo();
						const out = ft.output > 0 ? ft.output : si.tokens;
						if (out <= 0) return null;
						const rate = si.tps > 0 ? ` ${si.tps}t/s` : "";
						return `↓${fmt(out)}${rate}`;
					}
					if (ft.input > 0) return `↑${fmt(ft.input)}`;
					return null;
				};

				return (
					<>
						<Show when={retry()}>
							{(r) => (
								<text fg={ctx.theme.current.warning}>
									⟳ retry #{r().attempt}: {r().message}
								</text>
							)}
						</Show>

						<Show when={busy()}>
							<box flexDirection="row" gap={1}>
								<text fg={ctx.theme.current.success}>
									● {activity() ?? "starting"}...
								</text>
								<Show when={tokenText()}>
									{(t) => <text fg={ctx.theme.current.textMuted}>{t()}</text>}
								</Show>
							</box>
						</Show>
					</>
				);
			},
		},
	});
};

const plugin: TuiPluginModule = {
	id: "session-status",
	tui,
};

export default plugin;
