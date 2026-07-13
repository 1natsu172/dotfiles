#!/usr/bin/env bun
/**
 * Claude Code Stop hook: モデルの「thinking 空転」（reasoning 非収束）を transcript から検出する。
 *
 * シグネチャ（Opus 4.8 で観測。kestrel の a9d84fa0 / b205add0 セッション参照）:
 *   - A型: stop_reason === "max_tokens" なのに可視出力（thinking/text/tool入力）がほぼゼロ
 *          → 出力トークン予算を使い切っても収束しなかった完全空振りターン
 *   - B型: output_tokens が巨大（>= 30k）なのに可視出力がほぼゼロ
 *          → 自力終了はしたが中身のない空転ターン（end_turn でも起こる）
 *
 * 検出したら ~/.claude/spin-incidents.jsonl に追記し、stderr で警告して exit 1
 * （非ブロッキングエラー: ユーザーに stderr が表示される。モデルには渡らない —
 * 罹患モデル自身に警告を読ませても幻覚の確信に飲まれて無意味なため、通知先は人間に限定）。
 *
 * 赤旗時の対処フロー:
 *   1. 即停止。説得・問い詰めをしない（ターンを重ねるごとに虚偽報告がコンテキストに蓄積する）
 *   2. git status / log / diff を自分の目で確認。以降の自己申告は検証するまで信用しない
 *   3. A型 → まず /rewind で該当ターン直前へ巻き戻して1回だけ再試行
 *      再発 or B型 → /model で5系に切替え「ここまでの作業報告を全部検証し直せ」から再開。
 *      それでもダメなら新規セッションで旧 transcript を検証から
 *
 * incident ログは Anthropic 報告用の requestId 置き場を兼ねる。モデル非依存の検出器なので、
 * Opus 再挑戦セッションで赤旗ゼロが続けば「直った」の証拠にもなる。
 */

import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const OUTPUT_TOKENS_MIN = 30_000; // B型: これ以上燃やして
const PRODUCED_CHARS_MAX = 200; // 可視出力（thinking+text+tool入力）がこれ未満なら空転
const INCIDENTS_LOG =
	process.env.SPIN_INCIDENTS_LOG ??
	join(homedir(), ".claude", "spin-incidents.jsonl");
const SOUND = "/System/Library/Sounds/Basso.aiff";

// 全行 JSON.parse すると大きな transcript で無駄なので、候補行だけ先に正規表現で絞る
const PREFILTER =
	/"stop_reason"\s*:\s*"max_tokens"|"output_tokens"\s*:\s*(\d{5,})/;

interface ContentBlock {
	type?: string;
	thinking?: string;
	text?: string;
	input?: unknown;
}

interface AssistantMessage {
	model?: string;
	stop_reason?: string | null;
	content?: ContentBlock[];
	usage?: { output_tokens?: number };
}

interface TranscriptEntry {
	type?: string;
	timestamp?: string;
	requestId?: string;
	sessionId?: string;
	cwd?: string;
	message?: AssistantMessage;
}

interface Incident {
	detectedBy: string;
	kind: "A:max_tokens-exhausted" | "B:silent-burn";
	turnTimestamp: string | undefined;
	model: string | undefined;
	outputTokens: number;
	stopReason: string | null | undefined;
	producedChars: number;
	toolUseCount: number;
	requestId: string | undefined;
	sessionId: string | undefined;
	cwd: string | undefined;
	transcript: string;
}

/**
 * assistant メッセージが実際に外へ出した文字量と tool_use 数を返す。
 * tool_use の input も数えるのは、巨大な Write 等では output_tokens が
 * 大きくても正常ターンであり、誤検出しないため。
 */
function producedChars(message: AssistantMessage): {
	total: number;
	tools: number;
} {
	let total = 0;
	let tools = 0;
	for (const block of message.content ?? []) {
		if (typeof block !== "object" || block === null) continue;
		total += (block.thinking ?? "").length + (block.text ?? "").length;
		if (block.type === "tool_use") {
			tools += 1;
			try {
				total += JSON.stringify(block.input ?? {}).length;
			} catch {
				// 循環参照等で stringify できない input は文字量に数えない
			}
		}
	}
	return { total, tools };
}

function knownRequestIds(): Set<string | undefined> {
	const ids = new Set<string | undefined>();
	if (!existsSync(INCIDENTS_LOG)) return ids;
	for (const line of readFileSync(INCIDENTS_LOG, "utf8").split("\n")) {
		if (!line.trim()) continue;
		try {
			ids.add((JSON.parse(line) as Incident).requestId);
		} catch {
			// 壊れた行は無視
		}
	}
	return ids;
}

function scan(transcriptPath: string): Incident[] {
	const incidents: Incident[] = [];
	for (const line of readFileSync(transcriptPath, "utf8").split("\n")) {
		const m = PREFILTER.exec(line);
		if (!m) continue;
		if (
			m[1] &&
			Number(m[1]) < OUTPUT_TOKENS_MIN &&
			!line.includes('"max_tokens"')
		) {
			continue;
		}
		let entry: TranscriptEntry;
		try {
			entry = JSON.parse(line) as TranscriptEntry;
		} catch {
			continue;
		}
		if (entry.type !== "assistant" || !entry.message) continue;
		const msg = entry.message;
		const outTokens = msg.usage?.output_tokens ?? 0;
		const stopReason = msg.stop_reason;
		const { total, tools } = producedChars(msg);
		if (total >= PRODUCED_CHARS_MAX) continue;
		let kind: Incident["kind"];
		if (stopReason === "max_tokens") {
			kind = "A:max_tokens-exhausted";
		} else if (outTokens >= OUTPUT_TOKENS_MIN) {
			kind = "B:silent-burn";
		} else {
			continue;
		}
		incidents.push({
			detectedBy: "claude-code-spin-detector.ts",
			kind,
			turnTimestamp: entry.timestamp,
			model: msg.model,
			outputTokens: outTokens,
			stopReason,
			producedChars: total,
			toolUseCount: tools,
			requestId: entry.requestId,
			sessionId: entry.sessionId,
			cwd: entry.cwd,
			transcript: transcriptPath,
		});
	}
	return incidents;
}

function notify(): void {
	const commands = [
		["afplay", SOUND],
		[
			"osascript",
			"-e",
			'display notification "thinking空転を検出。セッションの自己申告を信用しないこと" with title "model-spin-detector"',
		],
	];
	for (const cmd of commands) {
		try {
			Bun.spawn(cmd, { stdout: "ignore", stderr: "ignore" });
		} catch {
			// 通知はベストエフォート（音・通知が出なくても stderr 警告は届く）
		}
	}
}

async function main(): Promise<number> {
	let transcriptPath: string;
	try {
		const hookInput = JSON.parse(await Bun.stdin.text()) as {
			transcript_path?: string;
		};
		transcriptPath = hookInput.transcript_path ?? "";
	} catch {
		return 0;
	}
	if (!transcriptPath || !existsSync(transcriptPath)) return 0;

	let found: Incident[];
	try {
		found = scan(transcriptPath);
	} catch {
		return 0;
	}
	const seen = knownRequestIds();
	const fresh = found.filter((i) => !seen.has(i.requestId));
	if (fresh.length === 0) return 0;

	appendFileSync(
		INCIDENTS_LOG,
		`${fresh.map((i) => JSON.stringify(i)).join("\n")}\n`,
	);
	notify();

	const lines = [
		"",
		"🚩 model-spin-detector: thinking空転ターンを検出（幻覚の病シグネチャ）",
		...fresh.map(
			(i) =>
				`  [${i.kind}] ${i.turnTimestamp} model=${i.model} ` +
				`output_tokens=${i.outputTokens} 可視出力=${i.producedChars}字 requestId=${i.requestId}`,
		),
		"  → 以降このセッションの『やった』系の自己申告は git/実ファイルで検証するまで信用しないこと。",
		"  → A型はまず /rewind で該当ターン直前へ。再発 or B型は /model で5系へ切替か損切り。",
		`  → 記録: ${INCIDENTS_LOG}（Anthropic 報告用に requestId が貯まる）`,
	];
	console.error(lines.join("\n"));
	return 1; // 非ブロッキングエラー: stderr をユーザーに表示（モデルには渡さない）
}

process.exit(await main());
