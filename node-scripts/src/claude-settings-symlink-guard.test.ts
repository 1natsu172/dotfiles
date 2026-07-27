/**
 * claude-settings-symlink-guard の検査ロジックを、machine の symlink 構成に依存せず確かめる。
 * 一時ディレクトリに `link -> real` を作り、settings.json 相当を食わせて子プロセスで実行する。
 *
 * root は realpath で開いておく（macOS の `/var` は `/private/var` への symlink なので、
 * 開かないと全ケースが検出扱いになりテストが意味を失う）。
 */

import { afterAll, beforeAll, expect, test } from "bun:test";
import {
	chmodSync,
	mkdirSync,
	mkdtempSync,
	realpathSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const GUARD = join(import.meta.dir, "claude-settings-symlink-guard.ts");

let root: string;

beforeAll(() => {
	root = realpathSync(mkdtempSync(join(tmpdir(), "symlink-guard-")));
	mkdirSync(join(root, "real", "nested"), { recursive: true });
	writeFileSync(join(root, "real", "file.txt"), "");
	symlinkSync(join(root, "real"), join(root, "link"));
	symlinkSync(join(root, "real", "file.txt"), join(root, "file-link.txt"));
});

afterAll(() => {
	rmSync(root, { recursive: true, force: true });
});

interface Result {
	code: number;
	stdout: string;
	stderr: string;
}

async function collect(proc: Bun.Subprocess): Promise<Result> {
	const [stdout, stderr, code] = await Promise.all([
		new Response(proc.stdout as ReadableStream).text(),
		new Response(proc.stderr as ReadableStream).text(),
		proc.exited,
	]);
	return { code, stdout, stderr };
}

/** 手動実行と同じ経路（引数でファイルを渡す） */
async function runCli(settings: unknown, name?: string): Promise<Result> {
	const file = join(root, name ?? `settings-${Bun.randomUUIDv7()}.json`);
	writeFileSync(file, JSON.stringify(settings));
	return collect(
		Bun.spawn(["bun", GUARD, file], { stdout: "pipe", stderr: "pipe" }),
	);
}

/** hook 経路（PostToolUse の入力を stdin に流し、編集されたファイルを読ませる） */
async function runHook(settings: unknown, name: string): Promise<Result> {
	const file = join(root, `${name}.json`);
	writeFileSync(file, JSON.stringify(settings));
	return collect(
		Bun.spawn(["bun", GUARD], {
			stdin: new TextEncoder().encode(
				JSON.stringify({
					hook_event_name: "PostToolUse",
					tool_name: "Edit",
					tool_input: { file_path: file },
				}),
			),
			stdout: "pipe",
			stderr: "pipe",
		}),
	);
}

test("deny のパスが symlink を経由していたら失敗し、実体パスを示す", async () => {
	const { code, stderr } = await runCli({
		permissions: { deny: [`Edit(//${root.slice(1)}/link/nested/**)`] },
	});
	expect(code).toBe(1);
	expect(stderr).toContain("[NG]");
	expect(stderr).toContain(`${root}/link`);
	expect(stderr).toContain(`${root}/real/nested/**`);
});

// user 向けの hook 通知は 200 文字（`[command]: ` 接頭辞込み）で打ち切られるため、
// 1 行目だけで用が足りること・短く収まることを縛る（docs の `D15`）
test("1 行目だけで、対象ファイル・該当記述・直し方が分かる", async () => {
	const { stderr } = await runCli({
		sandbox: {
			filesystem: {
				denyWrite: [join(root, "file-link.txt")], // error → 1 行目に出る
				allowWrite: [join(root, "link", "nested")], // warn → 件数だけ
			},
		},
	});
	const first = stderr.split("\n")[0] ?? "";
	expect(first).toMatch(/^⚠️ NG settings-.*\.json:/); // 深刻度と対象ファイル
	expect(first).toContain(join(root, "file-link.txt")); // 該当記述
	expect(first).toContain(join(root, "real", "file.txt")); // 直した形
	expect(first).toContain("ほか1件"); // 残りの件数
});

test("1 行目は接頭辞込みでも打ち切り上限に収まる", async () => {
	const { stderr } = await runCli(
		{
			permissions: {
				deny: [
					"Read(~/.config/1Password/**)", // 実運用でいちばん長い部類
					"Read(~/.config/gh/**)",
					"Read(~/.config/op/**)",
				],
			},
		},
		"settings.local.json", // 実運用のファイル名で測る
	);
	const first = stderr.split("\n")[0] ?? "";
	// hook の command 文字列（接頭辞）に 70 文字ぶんの余裕を見て、本文は 120 文字以内
	expect(first.length).toBeLessThanOrEqual(120);
});

test("ファイル単体の symlink も検出する", async () => {
	const { code, stderr } = await runCli({
		sandbox: { filesystem: { denyWrite: [join(root, "file-link.txt")] } },
	});
	expect(code).toBe(1);
	expect(stderr).toContain(`${root}/real/file.txt`);
});

test("辿れないパス（deny 済みで stat が落ちる相当）でも symlink は検出する", async () => {
	// 実機では、既に deny を掛けた `~/.config/gh` 等は自プロセスからも lstat が EPERM になる。
	// 一括 realpath で実装すると、この「最も守りたい行」だけ例外で黙って落ちる
	const blocked = join(root, "real", "blocked");
	mkdirSync(join(blocked, "inner"), { recursive: true });
	chmodSync(blocked, 0o000);
	try {
		const { code, stderr } = await runCli({
			permissions: { deny: [`Read(//${root.slice(1)}/link/blocked/inner/**)`] },
		});
		expect(code).toBe(1);
		expect(stderr).toContain(`${root}/real/blocked/inner/**`);
	} finally {
		chmodSync(blocked, 0o755);
	}
});

test("実体パスで書かれていれば通る", async () => {
	const { code, stdout, stderr } = await runCli({
		permissions: { deny: [`Read(//${root.slice(1)}/real/nested/**)`] },
		sandbox: { filesystem: { denyRead: [join(root, "real")] } },
	});
	expect(code).toBe(0);
	expect(stdout).toBe("");
	expect(stderr).toBe("");
});

test("実体を特定できない指定（glob 始まり・相対・パス以外の rule）は対象外", async () => {
	const { code, stdout, stderr } = await runCli({
		permissions: {
			deny: [
				"Read(//**/*.pem)",
				"Edit(**/secrets/**)",
				"Edit(/project-relative.json)",
				"Bash(sudo *)",
				"WebFetch(domain:example.com)",
			],
		},
	});
	expect(code).toBe(0);
	expect(stdout).toBe("");
	expect(stderr).toBe("");
});

test("allow 側は warn 止まり（hook では systemMessage で通知するだけ）", async () => {
	const allowWrite = {
		sandbox: { filesystem: { allowWrite: [join(root, "link", "nested")] } },
	};

	const cli = await runCli(allowWrite);
	expect(cli.code).toBe(0);
	expect(cli.stderr).toContain("[WARN]");

	const hook = await runHook(allowWrite, "warn-hook");
	expect(hook.code).toBe(0);
	expect(hook.stdout).toContain("systemMessage");
	expect(hook.stdout).toContain("[WARN]");
});

test("hook では NG で exit 2（stderr がモデルに返る）", async () => {
	const { code, stderr } = await runHook(
		{ sandbox: { filesystem: { denyRead: [join(root, "link", "nested")] } } },
		"deny-hook",
	);
	expect(code).toBe(2);
	expect(stderr).toContain("[NG]");
});

test("指定したファイルが読めなければ失敗として報告する", async () => {
	const { code, stderr } = await collect(
		Bun.spawn(["bun", GUARD, join(root, "no-such-file.json")], {
			stdout: "pipe",
			stderr: "pipe",
		}),
	);
	expect(code).toBe(1);
	expect(stderr).toContain("見つかりません");
});
