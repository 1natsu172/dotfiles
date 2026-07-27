#!/usr/bin/env bun
/**
 * Claude Code の settings.json に書かれたパスが symlink を経由していないかを検査する。
 *
 * dotfiles は `~/.config`・`~/.codex`・`~/.claude` 等を repo 配下への symlink として配る。
 * この綴りのまま deny を書くと **file tool にしか効かず Bash と OS 層は無言で素通りする**
 * （docs/claude-code-security.md の `D10`）。sandbox の filesystem 判定も symlink 解決後の
 * 実体パスで行われるため、allow 側は symlink 綴りだと単に効かない（同 `D6`）。
 * どちらも設定した側からは成功と区別がつかないので、綴りを機械的に縛る。
 *
 * 判定は「literal な接頭辞の各構成要素に symlink があるか」の一点。実体が home にある
 * `~/.ssh` 等は素通りし、接頭辞が glob で始まる指定（FS 全体アンカーの秘密鍵パターン等）は
 * 実体を特定できないので対象外。
 *
 * 深刻度:
 *   - error: deny 系（permissions の Read/Edit/Write deny・sandbox の denyRead/denyWrite）
 *     ＝防御が効かないまま効いたつもりになる
 *   - warn : allow / ask 系（sandbox の allowRead/allowWrite/allowUnixSockets 等）
 *     ＝許可が効かず動かなくなるだけで、穴にはならない
 *
 * 呼ばれ方（配線と実測は docs/claude-code-security.md「settings のパス綴りを hook で検査する」）:
 *   - PostToolUse hook: settings を編集した直後に、その編集されたファイルを検査する。error なら
 *     exit 2 で **stderr がモデルに返る**（その場で直させる経路）
 *   - SessionStart hook: 既定のターゲット（user settings）を検査する。既に入り込んでいる綴りと、
 *     構成変更による陳腐化を起動時に拾う
 *   - 手動: `bun ./node-scripts/src/claude-settings-symlink-guard.ts [settings.json ...]`
 */

import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

const HOME = homedir();
const GLOB_CHARS = /[*?[\]{}]/;
const PERMISSION_RULE = /^(Read|Edit|Write)\((.+)\)$/;
const DOC_REF =
	"docs/claude-code-security.md の `D10`（deny）/ `D6`（sandbox allow）";

type Severity = "error" | "warn";

/** settings.json 上の 1 エントリと、そこから取り出した検査対象パス */
interface PathSpec {
	/** 表示用のキー（例: `permissions.deny`） */
	key: string;
	/** 元の記述そのもの（例: `Read(~/.config/gh/**)`） */
	entry: string;
	/** entry から取り出したパス指定（例: `~/.config/gh/**`） */
	spec: string;
	severity: Severity;
	/** パス書式の解釈。permission rule は `/x` が project root 相対、sandbox は絶対 */
	kind: "permission" | "sandbox";
}

interface Finding extends PathSpec {
	/** 最初に見つかった symlink（表示用に `~/` 短縮済み） */
	symlink: string;
	/** 実体パスに直した綴り（元の anchor 形式を保つ） */
	suggestion: string;
	/** entry ごと直した形（`Read(~/dotfiles/.config/gh/**)`） */
	suggestedEntry: string;
}

interface FileReport {
	file: string;
	findings: Finding[];
	/** 読めなかった理由（存在しない・JSON が壊れている） */
	unreadable?: string;
}

function asRecord(value: unknown): Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: {};
}

function asStrings(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((v): v is string => typeof v === "string")
		: [];
}

/** permissions の Read/Edit/Write rule からパス部分を取り出す（Bash・WebFetch 等は対象外） */
function permissionSpecs(
	list: unknown,
	key: string,
	severity: Severity,
): PathSpec[] {
	const specs: PathSpec[] = [];
	for (const entry of asStrings(list)) {
		const matched = PERMISSION_RULE.exec(entry);
		const spec = matched?.[2];
		if (!spec) continue;
		specs.push({ key, entry, spec, severity, kind: "permission" });
	}
	return specs;
}

function sandboxSpecs(
	list: unknown,
	key: string,
	severity: Severity,
): PathSpec[] {
	return asStrings(list).map((entry) => ({
		key,
		entry,
		spec: entry,
		severity,
		kind: "sandbox" as const,
	}));
}

function collectSpecs(settings: unknown): PathSpec[] {
	const root = asRecord(settings);
	const permissions = asRecord(root.permissions);
	const sandbox = asRecord(root.sandbox);
	const filesystem = asRecord(sandbox.filesystem);
	const network = asRecord(sandbox.network);

	return [
		...permissionSpecs(permissions.deny, "permissions.deny", "error"),
		...permissionSpecs(permissions.ask, "permissions.ask", "warn"),
		...permissionSpecs(permissions.allow, "permissions.allow", "warn"),
		...sandboxSpecs(
			filesystem.denyRead,
			"sandbox.filesystem.denyRead",
			"error",
		),
		...sandboxSpecs(
			filesystem.denyWrite,
			"sandbox.filesystem.denyWrite",
			"error",
		),
		...sandboxSpecs(
			filesystem.allowRead,
			"sandbox.filesystem.allowRead",
			"warn",
		),
		...sandboxSpecs(
			filesystem.allowWrite,
			"sandbox.filesystem.allowWrite",
			"warn",
		),
		...sandboxSpecs(
			network.allowUnixSockets,
			"sandbox.network.allowUnixSockets",
			"warn",
		),
	];
}

/**
 * パス指定を絶対パスに開く。実体を特定できない書式（相対 anchor、permission rule の
 * project root 相対）は null を返して検査対象から外す。
 */
function toAbsolute(spec: string, kind: PathSpec["kind"]): string | null {
	if (spec.startsWith("~/")) return join(HOME, spec.slice(2));
	if (spec.startsWith("//")) return `/${spec.slice(2)}`;
	if (spec.startsWith("/")) return kind === "sandbox" ? spec : null;
	return null;
}

/** 絶対パスを「glob を含まない接頭辞」と「残り」に分ける */
function splitAtGlob(absolute: string): { literal: string; rest: string } {
	const parts = absolute.split("/");
	const index = parts.findIndex((part) => GLOB_CHARS.test(part));
	if (index === -1) return { literal: absolute, rest: "" };
	return {
		literal: parts.slice(0, index).join("/"),
		rest: parts.slice(index).join("/"),
	};
}

/**
 * 接頭辞を root から 1 要素ずつ辿り、最初の symlink とその解決後のパスを返す。
 *
 * 途中で解決を打ち切って残りを連結するのは、**保護対象そのものが辿れない**ため。
 * `~/.config/gh` のように既に deny を掛けたパスは lstat / realpath が EPERM で落ちる
 * （sandbox の denyRead は自プロセスにも効く）。一括 realpath だと、最も重要な行だけ
 * 例外で黙って落ちる。symlink の解決は「見つかった要素ごと」に済ませれば足りる。
 */
function resolveSymlink(
	literal: string,
): { symlink: string; real: string } | null {
	const parts = literal.split("/").filter(Boolean);
	let spelled = ""; // 設定に書かれた綴り側
	let real = ""; // symlink を解決した側
	let symlink: string | null = null;

	// 辿れなくなった時点で残りを綴りのまま連結する（そこから先に symlink があっても、
	// 見つかった分だけ直せば実体パスに近づく）
	const giveUp = (index: number): string =>
		real +
		parts
			.slice(index + 1)
			.map((rest) => `/${rest}`)
			.join("");

	for (const [index, part] of parts.entries()) {
		spelled += `/${part}`;
		real += `/${part}`;
		let stat: ReturnType<typeof lstatSync>;
		try {
			stat = lstatSync(real);
		} catch {
			// 存在しない、または deny で辿れない
			real = giveUp(index);
			break;
		}
		if (stat.isSymbolicLink()) {
			symlink ??= spelled;
			try {
				real = realpathSync(real);
			} catch {
				real = giveUp(index); // リンク切れ等。解決できた分だけで打ち切る
				break;
			}
		}
	}
	if (!symlink || real === literal) return null;
	return { symlink, real };
}

/** 表示用に home を `~/` へ短縮する */
function abbreviate(path: string): string {
	return path.startsWith(`${HOME}/`)
		? `~/${path.slice(HOME.length + 1)}`
		: path;
}

/** 実体パスを元の書式（`~/` / `//` / 絶対）に戻す */
function respell(
	absolute: string,
	spec: string,
	kind: PathSpec["kind"],
): string {
	if (spec.startsWith("~/") && absolute.startsWith(`${HOME}/`)) {
		return `~/${absolute.slice(HOME.length + 1)}`;
	}
	if (spec.startsWith("//")) return `/${absolute}`;
	if (kind === "sandbox" && absolute.startsWith(`${HOME}/`)) {
		return `~/${absolute.slice(HOME.length + 1)}`;
	}
	return absolute;
}

function inspect(spec: PathSpec): Finding | null {
	const absolute = toAbsolute(spec.spec, spec.kind);
	if (!absolute) return null;
	const { literal, rest } = splitAtGlob(absolute);
	if (!literal) return null;
	const resolved = resolveSymlink(literal);
	if (!resolved) return null;

	const suggestion = respell(
		rest ? `${resolved.real}/${rest}` : resolved.real,
		spec.spec,
		spec.kind,
	);
	return {
		...spec,
		symlink: abbreviate(resolved.symlink),
		suggestion,
		// permission rule なら `Read(...)` ごと差し替えた形で見せる（そのまま貼り替えられる）
		suggestedEntry: spec.entry.replace(spec.spec, suggestion),
	};
}

function scanFile(file: string): FileReport {
	let settings: unknown;
	try {
		settings = JSON.parse(readFileSync(file, "utf8"));
	} catch (error) {
		// hook では黙って見送る（未作成の settings.local.json は普通。壊れた JSON は
		// Claude Code 自身が報告する）。手動実行では読めなかった事実を出す
		return { file, findings: [], unreadable: String(error) };
	}
	const findings = collectSpecs(settings)
		.map(inspect)
		.filter((f): f is Finding => f !== null);
	return { file, findings };
}

/**
 * 1 行目だけで用が足りる形にする。**user 向けの hook 通知は 200 文字で打ち切られる**
 * （`[<hook の command>]: ` の接頭辞込み。docs/claude-code-security.md の `D15`）ため、
 * 「どのファイルの・どの記述を・どう直すか」をこの順で詰める。後ろから削られるので、
 * 最も derive しやすい「直した形」を末尾に置く。
 */
function headline(reports: FileReport[]): string {
	const all = reports.flatMap((r) =>
		r.findings.map((f) => ({ finding: f, file: basename(r.file) })),
	);
	const top = all.find((a) => a.finding.severity === "error") ?? all[0];
	if (!top) return "";
	const rest = all.length - 1;
	const more = rest > 0 ? `（ほか${rest}件）` : "";
	const mark = top.finding.severity === "error" ? "NG" : "WARN";
	return `⚠️ ${mark} ${top.file}: symlink 綴りの ${top.finding.entry} → ${top.finding.suggestedEntry}${more}`;
}

function formatReport(reports: FileReport[]): string {
	const lines: string[] = [headline(reports)];
	for (const report of reports) {
		lines.push(`  ${abbreviate(report.file)}`);
		for (const f of report.findings) {
			const mark = f.severity === "error" ? "NG" : "WARN";
			lines.push(
				`    [${mark}] ${f.key}: ${f.entry}`,
				`           → ${f.suggestedEntry}（${f.symlink} が symlink）`,
			);
		}
	}
	const severities = new Set(
		reports.flatMap((r) => r.findings.map((f) => f.severity)),
	);
	if (severities.has("error")) {
		lines.push(
			"  ※ [NG] symlink 綴りの deny は file tool にしか効かず、Bash と OS 層は無言で素通りします。",
		);
	}
	if (severities.has("warn")) {
		lines.push(
			"  ※ [WARN] 許可側は実体パスでないと効かない層があります（sandbox は symlink 解決後の実体パスで判定）。",
		);
	}
	lines.push(`  ※ 根拠と実測: ${DOC_REF}`);
	return lines.join("\n");
}

function defaultTargets(): string[] {
	return [
		join(HOME, ".claude", "settings.json"),
		join(HOME, ".claude", "settings.local.json"),
	];
}

async function readHookInput(): Promise<Record<string, unknown> | null> {
	try {
		const raw = await Bun.stdin.text();
		if (!raw.trim()) return null;
		return asRecord(JSON.parse(raw));
	} catch {
		return null;
	}
}

async function main(): Promise<number> {
	const args = process.argv.slice(2);
	const explicit = args.length > 0;
	const hook = explicit ? null : await readHookInput();

	let targets: string[];
	if (explicit) {
		targets = args;
	} else if (hook && hook.hook_event_name === "PostToolUse") {
		const edited = asRecord(hook.tool_input).file_path;
		targets = typeof edited === "string" ? [edited] : [];
	} else {
		targets = defaultTargets();
	}

	const scanned = targets.filter(existsSync).map(scanFile);

	if (!hook) {
		// 手動実行では読めなかったこと自体を失敗として出す（黙って 0 を返すと
		// パスを打ち間違えたときに「問題なし」と区別がつかない）。
		// ただし未指定時の既定ターゲットは、存在しないのが普通なので数えない
		const unreadable = [
			...(explicit ? targets.filter((file) => !existsSync(file)) : []).map(
				(file) => `${file}: 見つかりません`,
			),
			...scanned
				.filter((r) => r.unreadable)
				.map((r) => `${r.file}: ${r.unreadable}`),
		];
		if (unreadable.length > 0) {
			console.error(`検査できませんでした\n  ${unreadable.join("\n  ")}`);
			return 1;
		}
	}

	const reports = scanned.filter((r) => r.findings.length > 0);
	if (reports.length === 0) return 0;

	const report = formatReport(reports);
	const hasError = reports.some((r) =>
		r.findings.some((f) => f.severity === "error"),
	);

	if (!hook) {
		console.error(report);
		return hasError ? 1 : 0;
	}
	if (!hasError) {
		// warn だけ: 設定の反映は止めず、user にだけ知らせる
		console.log(JSON.stringify({ systemMessage: report }));
		return 0;
	}
	console.error(report);
	return 2;
}

process.exit(await main());
