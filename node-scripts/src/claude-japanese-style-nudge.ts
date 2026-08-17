#!/usr/bin/env bun
/**
 * 日本語の規範（`.claude/rules/japanese-style.md`）を、作業の現在位置へ注入し直す。
 *
 * 起動時にロードされた規範は、コンテキストが伸びるほど遠ざかって効かなくなる。書き置いた
 * 規範は自律的には発火しない一方、同じ内容でも現在位置へ届けば効く。そこで `.md` を書く
 * ターンごとに本文を注入し直す。
 *
 * 違反の検出はしない。日本語の不自然さは語の列挙で覆えず、静的フィルタでは検出できない。
 * この hook がやるのは規範の再提示だけで、deny も input の書き換えもしない。
 *
 * 頻度の制御（設計上の主変数）:
 *   `additionalContext` は attachment として会話履歴へ永続的に積まれ、後続の全リクエストで
 *   再送される。prompt キャッシュが下げるのは再送の価格だけで、context window の占有量は
 *   減らない。素朴に書き込みごとへ鳴らすと占有が膨らんで compact が早まり、注入で守ろうと
 *   していたコンテキストを自分で壊す。そこで **`prompt_id`（ユーザーターンごとの UUID）と
 *   `agent_id` で重複排除**し、発火を「`.md` を書いたターンにつき、エージェントごとに
 *   最大 1 回」に抑える。
 *   実測（対象リポジトリの 146 セッション）では 1,678 回の `.md` 書き込みが 390 回の注入に
 *   落ち、context 占有の増分は平均 1.3%・最悪 4.6%。重複排除を外すと最悪 27.6% まで伸びる。
 *
 * 本文をこのスクリプトへ複製しないこと。rule ファイルを実行時に読むことで、起動時に
 * ロードされる本文と注入される本文が一致し続ける。
 *
 * 呼ばれ方:
 *   - PreToolUse hook（matcher `Edit|Write`、`if` は `.md` 限定で Edit 用と Write 用の 2 エントリ。
 *     `if` は tool 名の直接比較で、permission rule と違い `Edit(...)` が Write tool を捕まえない
 *     ため、片方だけだと新規作成で落ちる＝`docs/claude-code-security.md` の `D18`）。
 *     PreToolUse が鳴る時点で
 *     `tool_input` は確定済みなので、その書き込み自体は直せない。効くのは次の書き込み以降と
 *     それ以降の応答。狙いが「規範が遠ざかること」への対処なので、これで足りる。
 *   - 手動: `echo '{...}' | bun ./node-scripts/src/claude-japanese-style-nudge.ts`
 *
 * 失敗しても作業を止めない。入力が読めない・rule が無い等は黙って exit 0 する。
 */

import {
	mkdirSync,
	readdirSync,
	readFileSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** rule 本文の実体。symlink（`~/.claude`）を経由せず、スクリプト位置から辿る */
const RULE_PATH = join(
	import.meta.dir,
	"..",
	"..",
	".claude",
	"rules",
	"japanese-style.md",
);

/** 注入の冒頭に置く手順。「気をつける」ではなく、いつ何をするかを書く */
const DIRECTIVE =
	"これから書く日本語は、ファイル本文と応答の両方について、書き終えてから以下へ照らして読み直すこと。";

/** 重複排除の記録先。テストが隔離できるよう env で差し替えられる */
const STATE_DIR =
	process.env.CLAUDE_JA_NUDGE_STATE_DIR ??
	join(tmpdir(), "claude-japanese-style-nudge");

/** 注入対象の拡張子。日本語の本文量が最も多いのが `.md` */
const TARGET_EXT = ".md";

/** これを過ぎた session ディレクトリは掃除する。セッションの実寿命より十分長く取る */
const SESSION_DIR_TTL_MS = 24 * 60 * 60 * 1000;

interface HookInput {
	session_id?: string;
	prompt_id?: string;
	agent_id?: string;
	tool_input?: { file_path?: string };
}

/**
 * rule ファイルから注入する本文を取り出す。
 *
 * frontmatter と block level の HTML コメントは Claude Code 自身もコンテキストへ載せる前に
 * 落とすので、注入側でも同じように落として本文を一致させる。
 */
export function extractRuleBody(raw: string): string {
	return raw
		.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "")
		.replace(/<!--[\s\S]*?-->/g, "")
		.trim();
}

/** パス構成要素へ落とす。`.` と `..` は階層を指すので fallback へ倒す */
function sanitize(part: string, fallback: string): string {
	const cleaned = part.replace(/[^\w.-]/g, "_");
	return cleaned === "" || cleaned === "." || cleaned === ".."
		? fallback
		: cleaned;
}

/**
 * このターンの注入枠を取る。取れたら true、既に誰かが取っていたら false。
 *
 * Claude Code は 1 つの応答に含まれる複数の Edit/Write を並行に走らせ、PreToolUse hook も
 * 並行に起動する。read してから write する形だと、全プロセスが「まだ未注入」を読んでから
 * 書くので全員が注入してしまう。枠の確保は `wx`（存在したら失敗）での作成 1 回に閉じ、
 * EEXIST を負けたシグナルとして使う。
 *
 * subagent は親と `session_id` / `prompt_id` を共有するため、`agent_id` もキーに含める。
 * 含めないと、subagent が先に `.md` を書いたターンで親側の注入が消える。
 *
 * 置き場を用意できないときは **注入しない**。重複排除が効かないまま注入を続けると、
 * 並行する Edit/Write の全てが本文を積み、頻度の制御という設計の前提が消える。実測で
 * 最悪 27.6% の context を規範の再掲が占める状態になる。注入を落とすほうが害が小さい。
 */
export function claimInjection(
	input: Pick<HookInput, "session_id" | "prompt_id" | "agent_id">,
	stateDir: string,
): boolean {
	const dir = join(stateDir, sanitize(input.session_id ?? "", "no-session"));
	const promptPart = sanitize(input.prompt_id ?? "", "no-prompt-id");
	const name = `${sanitize(input.agent_id ?? "", "main")}-${promptPart}`;

	try {
		mkdirSync(dir, { recursive: true });
	} catch {
		// 旧実装は session ごとに通常ファイルを書いていた。その遺物が塞いでいるだけなら
		// 取り除いて作り直す。それでも駄目なら置き場が使えないので注入しない。
		try {
			rmSync(dir, { force: true });
			mkdirSync(dir, { recursive: true });
		} catch {
			return false;
		}
	}

	// EEXIST は他が先に取った、それ以外は枠を残せないということ。どちらも注入しない。
	try {
		writeFileSync(join(dir, name), "", { flag: "wx" });
	} catch {
		return false;
	}

	pruneStaleClaims(stateDir, dir, promptPart);
	return true;
}

/**
 * 死んだ枠ファイルを片づける。user レベルの hook なので全プロジェクトで動き、放っておくと
 * `$TMPDIR` が purge されるまで単調に増える。
 *
 * 同じターンの枠は消さない。親と subagent が同時に枠を持つので、prompt_id が一致するものを
 * 残して他を落とす。掃除に失敗しても枠の確保結果には影響させない。
 */
function pruneStaleClaims(
	stateDir: string,
	sessionDir: string,
	promptPart: string,
): void {
	try {
		for (const entry of readdirSync(sessionDir)) {
			if (!entry.endsWith(`-${promptPart}`)) {
				rmSync(join(sessionDir, entry), { force: true });
			}
		}

		const expiry = Date.now() - SESSION_DIR_TTL_MS;
		for (const entry of readdirSync(stateDir)) {
			const path = join(stateDir, entry);
			if (path !== sessionDir && statSync(path).mtimeMs < expiry) {
				rmSync(path, { recursive: true, force: true });
			}
		}
	} catch {
		// 掃除はあくまで付随処理
	}
}

async function main(): Promise<void> {
	let input: HookInput;
	try {
		input = JSON.parse(await Bun.stdin.text());
	} catch {
		return;
	}
	// `null` は JSON として妥当なので parse を抜ける。ここで弾かないと後続の参照が
	// 例外になり、「失敗しても黙って exit 0」という約束が破れる。
	if (typeof input !== "object" || input === null) return;

	const filePath = input.tool_input?.file_path;
	if (!filePath?.endsWith(TARGET_EXT)) return;

	// 枠を取る前に本文を読む。読めなかった場合に枠だけ消費すると、同じターンの後続の
	// 書き込みが二度と注入できなくなる。
	let body: string;
	try {
		body = extractRuleBody(readFileSync(RULE_PATH, "utf8"));
	} catch {
		return;
	}
	if (!body) return;

	if (!claimInjection(input, STATE_DIR)) return;

	process.stdout.write(
		JSON.stringify({
			hookSpecificOutput: {
				hookEventName: "PreToolUse",
				additionalContext: `${DIRECTIVE}\n\n${body}`,
			},
		}),
	);
}

if (import.meta.main) {
	await main();
}
