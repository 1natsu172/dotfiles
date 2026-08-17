/**
 * claude-japanese-style-nudge の 2 点を確かめる。
 *
 *   - 本文の取り出し: frontmatter と HTML コメントを落とす（Claude Code 自身がコンテキストへ
 *     載せる前に落とすものと揃えないと、起動時にロードされる本文と注入される本文がずれる）
 *   - 頻度の制御: 同一ターンの 2 回目が鳴らない。ここが壊れると書き込みごとに注入が積まれ、
 *     context を圧迫して compact を早める。並行起動でも 1 回に収まることまで見る
 *
 * end to end は子プロセスで実行する。状態の置き場は `CLAUDE_JA_NUDGE_STATE_DIR` で
 * 一時ディレクトリへ寄せ、共有 tmp を汚さず子プロセス側の重複排除も測れるようにする。
 */

import { afterAll, beforeAll, expect, test } from "bun:test";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	realpathSync,
	rmSync,
	utimesSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	claimInjection,
	extractRuleBody,
} from "./claude-japanese-style-nudge.ts";

const SCRIPT = join(import.meta.dir, "claude-japanese-style-nudge.ts");

let stateDir: string;

beforeAll(() => {
	stateDir = realpathSync(mkdtempSync(join(tmpdir(), "ja-nudge-")));
});

afterAll(() => {
	rmSync(stateDir, { recursive: true, force: true });
});

test("frontmatter と HTML コメントを落とす", () => {
	const raw = [
		"---",
		"paths:",
		'  - "**/*.md"',
		"---",
		"<!-- 置き場の理由をここに書く",
		"     複数行にまたがる -->",
		"",
		"# 見出し",
		"",
		"- 本文",
		"",
	].join("\n");

	expect(extractRuleBody(raw)).toBe("# 見出し\n\n- 本文");
});

test("frontmatter が無くても本文をそのまま返す", () => {
	expect(extractRuleBody("# 見出し\n\n- 本文\n")).toBe("# 見出し\n\n- 本文");
});

test("同一 prompt_id では 2 回目が鳴らない", () => {
	const input = { session_id: "s1", prompt_id: "p1" };
	expect(claimInjection(input, stateDir)).toBe(true);
	expect(claimInjection(input, stateDir)).toBe(false);
	expect(claimInjection(input, stateDir)).toBe(false);
});

test("prompt_id が変われば再び鳴る", () => {
	expect(claimInjection({ session_id: "s2", prompt_id: "p1" }, stateDir)).toBe(
		true,
	);
	expect(claimInjection({ session_id: "s2", prompt_id: "p2" }, stateDir)).toBe(
		true,
	);
	expect(claimInjection({ session_id: "s2", prompt_id: "p2" }, stateDir)).toBe(
		false,
	);
});

test("session が違えば互いに干渉しない", () => {
	expect(
		claimInjection({ session_id: "s3", prompt_id: "shared" }, stateDir),
	).toBe(true);
	expect(
		claimInjection({ session_id: "s4", prompt_id: "shared" }, stateDir),
	).toBe(true);
});

test("subagent は親と同じターンでも別枠を持つ", () => {
	const turn = { session_id: "s5", prompt_id: "p1" };
	expect(claimInjection({ ...turn, agent_id: "sub-a" }, stateDir)).toBe(true);
	expect(claimInjection(turn, stateDir)).toBe(true);
	expect(claimInjection({ ...turn, agent_id: "sub-a" }, stateDir)).toBe(false);
	expect(claimInjection(turn, stateDir)).toBe(false);
});

test("session_id が無い入力どうしは干渉しない前提を置かない", () => {
	const input = { prompt_id: "p1" };
	expect(claimInjection(input, stateDir)).toBe(true);
	expect(claimInjection(input, stateDir)).toBe(false);
});

test("旧実装の遺物が session のパスを塞いでいても回復する", () => {
	// 旧実装は session ごとに通常ファイルを書いていた。その遺物が残っていると
	// mkdir が EEXIST を投げる。これを「他が先に取った」と読むとセッション全体で沈黙する。
	writeFileSync(join(stateDir, "occupied"), "legacy");

	expect(
		claimInjection({ session_id: "occupied", prompt_id: "p1" }, stateDir),
	).toBe(true);
	expect(existsSync(join(stateDir, "occupied", "main-p1"))).toBe(true);
});

test("置き場ごと使えないときは注入しない", () => {
	// 重複排除が効かない状態で注入を続けると、並行する Edit/Write の全てが本文を積む。
	// 注入を落とすほうが害が小さい。
	const blocked = join(stateDir, "root-blocked");
	writeFileSync(blocked, "not a directory");

	expect(claimInjection({ session_id: "s", prompt_id: "p1" }, blocked)).toBe(
		false,
	);
});

test("前のターンの枠は掃除し、同じターンの枠は残す", () => {
	const dir = join(stateDir, "prune");
	expect(claimInjection({ session_id: "prune", prompt_id: "p1" }, dir)).toBe(
		true,
	);
	expect(
		claimInjection(
			{ session_id: "prune", prompt_id: "p1", agent_id: "sub" },
			dir,
		),
	).toBe(true);
	// 同一ターンでは親と subagent が同時に枠を持つ
	expect(existsSync(join(dir, "prune", "main-p1"))).toBe(true);
	expect(existsSync(join(dir, "prune", "sub-p1"))).toBe(true);

	expect(claimInjection({ session_id: "prune", prompt_id: "p2" }, dir)).toBe(
		true,
	);
	expect(existsSync(join(dir, "prune", "main-p2"))).toBe(true);
	expect(existsSync(join(dir, "prune", "main-p1"))).toBe(false);
	expect(existsSync(join(dir, "prune", "sub-p1"))).toBe(false);
});

test("古い session ディレクトリを掃除する", () => {
	const dir = join(stateDir, "ttl");
	const old = join(dir, "old-session");
	mkdirSync(old, { recursive: true });
	const twoDaysAgo = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
	utimesSync(old, twoDaysAgo, twoDaysAgo);

	expect(claimInjection({ session_id: "fresh", prompt_id: "p1" }, dir)).toBe(
		true,
	);
	expect(existsSync(old)).toBe(false);
	expect(existsSync(join(dir, "fresh"))).toBe(true);
});

test("session_id が .. でも state dir の外へ出ない", () => {
	expect(
		claimInjection({ session_id: "..", prompt_id: "dotdot" }, stateDir),
	).toBe(true);
	expect(existsSync(join(stateDir, "no-session", "main-dotdot"))).toBe(true);
});

async function run(
	input: unknown,
	dir: string,
): Promise<{ stdout: string; code: number }> {
	const proc = Bun.spawn(["bun", SCRIPT], {
		stdin: new TextEncoder().encode(JSON.stringify(input)),
		stdout: "pipe",
		stderr: "pipe",
		env: { ...process.env, CLAUDE_JA_NUDGE_STATE_DIR: dir },
	});
	const stdout = await new Response(proc.stdout).text();
	const code = await proc.exited;
	return { stdout, code };
}

test(".md への書き込みで rule 本文を注入する", async () => {
	const { stdout, code } = await run(
		{
			session_id: "e2e-inject",
			prompt_id: "p1",
			tool_input: { file_path: "/tmp/doc.md" },
		},
		stateDir,
	);
	expect(code).toBe(0);
	const parsed = JSON.parse(stdout);

	expect(parsed.hookSpecificOutput.hookEventName).toBe("PreToolUse");
	expect(parsed.hookSpecificOutput.additionalContext).toContain("日本語ルール");
	expect(parsed.hookSpecificOutput.additionalContext).not.toContain(
		"scope:global",
	);
});

test(".md 以外では何も出さない", async () => {
	const { stdout, code } = await run(
		{
			session_id: "e2e-ts",
			prompt_id: "p1",
			tool_input: { file_path: "/tmp/index.ts" },
		},
		stateDir,
	);
	// exit code も見る。stdout だけだと起動時に落ちるリグレッションでも pass する
	expect(code).toBe(0);
	expect(stdout).toBe("");
});

test("同一ターンで並行に起動しても注入は 1 回だけ", async () => {
	const input = {
		session_id: "e2e-parallel",
		prompt_id: "p1",
		tool_input: { file_path: "/tmp/doc.md" },
	};
	const results = await Promise.all(
		Array.from({ length: 8 }, () => run(input, stateDir)),
	);

	expect(results.every((r) => r.code === 0)).toBe(true);
	expect(results.filter((r) => r.stdout.length > 0)).toHaveLength(1);
});

test.each([
	["not json", "JSON として壊れている"],
	["null", "JSON としては妥当だが object ではない"],
	["[1,2]", "配列"],
])("%s でも黙って exit 0 する（%s）", async (payload) => {
	const proc = Bun.spawn(["bun", SCRIPT], {
		stdin: new TextEncoder().encode(payload),
		stdout: "pipe",
		stderr: "pipe",
		env: { ...process.env, CLAUDE_JA_NUDGE_STATE_DIR: stateDir },
	});
	const stdout = await new Response(proc.stdout).text();
	const stderr = await new Response(proc.stderr).text();
	expect(await proc.exited).toBe(0);
	expect(stdout).toBe("");
	expect(stderr).toBe("");
});
