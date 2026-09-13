# Claude Code の命令ロード挙動

> **仕様の一次情報は公式 Docs**（[memory](https://code.claude.com/docs/en/memory) / [hooks](https://code.claude.com/docs/en/hooks)）。本書は**公式 Docs から確証が得られず実機で測った挙動**と、**dotfiles での判断**だけを書く。仕様の写経はしない（書くとドリフトする）。
>
> permission / sandbox の挙動は [claude-code-security.md](./claude-code-security.md)。本書は「命令ファイルがいつコンテキストへ載るか」だけを扱う。

## ロードの契機

`.claude/rules/*.md` は **`paths` frontmatter の有無だけ**で起動時ロードか遅延ロードかが決まる（公式 Docs 記載）。`paths` を持つ rule は、Claude が該当パターンのファイルを file tool で開いたときに初めて載る。Bash の `cat` / `head` では載らない。

## `paths` の解決規則

検証日 2026-08-01 / CC 2.1.220。dotfiles の外（`~/cc-rulecheck/proj-a`）を cwd にした別セッションで実測。

**glob は project root（起動時 cwd）基準で解決され、その配下に閉じる。** rule ファイルの置き場は基準にならず、`~/.claude/rules/` に置いた user-level rule でも project root 基準になる。

| `paths` の書式 | project 配下の `.claude/settings.json` | project root 直下のファイル | project root の外 |
|---|---|---|---|
| `**/.claude/settings.json` | 発火 | （対象外） | **発火しない** |
| `.claude/settings.json` | 発火 | （対象外） | **発火しない** |
| `**/settings.json` | 発火 | （対象外） | **発火しない** |
| `*.probe` | （対象外） | 発火 | 未測定 |
| `//**/.claude/settings.json` | **発火しない** | （対象外） | **発火しない** |
| `/Users/<user>/dotfiles/.claude/settings.json`（絶対） | （対象外） | （対象外） | **発火しない** |
| `~/.claude/settings.json`（チルダ） | （対象外） | （対象外） | **発火しない** |

「project root の外」の実測対象は `~/.claude/settings.json`（symlink 綴り）と `~/dotfiles/.claude/settings.json`（実体綴り）の 2 通り。どちらでも発火しないので、`D10` のような綴りの問題ではない。

ここから出る帰結は 2 つ。

- **permission の記法を持ち込まない。** `//**/X`（FS 全体アンカー）は permission の deny では必須だが（`claude-code-security.md` の `D11`）、`paths` では一度も発火しない。別方言として扱う。
- **project root の外は捕捉できない。** 絶対パスでも `~/` 綴りでも発火しないため、`paths` の書き方では届かせられない。届かせたいなら `paths` を外して常時ロードにするしかない。

## dotfiles の rules の内訳

| ファイル | ロード | 理由 |
|---|---|---|
| `claude-code-settings.md` | `paths` で遅延 | 「settings を変更する」契機がファイル編集そのものなので `paths` で捕捉できる |
| `git-push-upstream-sandbox.md` | 常時 | 「push する」契機はファイル編集を伴わず `paths` で捕捉できない |
| `fnox-sandbox-invocation.md` | 常時 | 「npm / yarn を打つ」契機も同様 |
| `japanese-style.md` | 常時 | 適用先が TUI 応答とファイル本文の両方で、契機がファイル編集に限られない。加えて PreToolUse hook の注入元を兼ねる（hook は現在無効。後述） |

**契機がファイル編集でないものは常時ロードにするしかない。** 常時ロードは全セッションのコンテキストを食うので数行に抑える（各ファイル冒頭のコメントに「`paths` を足さない」理由を書いてある）。

`japanese-style.md` だけは数行に収まらない。これは `.claude/CLAUDE.md` から移した節で、CLAUDE.md も起動時に全文ロードされるため起動時のトークン量は増減しない。移動の狙いは、規範の実体を 1 ファイルへ寄せて hook の注入元と一致させることにある。

`claude-code-settings.md` の `paths` が実際に効くことは cwd = dotfiles の素のセッションで確認済み（`dotfiles/.claude/settings.json` を Read して注入を観測）。ただし上記のとおり、**他 project から `~/.claude/settings.json` を触る場面は捕捉できない**。この場面が稀なので現状は `paths` のままにしている。

### `japanese-style.md` を hook で注入し直す（現在は無効）

**この hook は現在 `.claude/settings.json` から外し、経過観測している。** 観測しているのは、hook を使わず起動時ロードの rule だけで、長いセッションの後半まで規範が保たれるかどうか。観測開始は 2026-09-14、CC 2.1.270。Claude Code の更新で改善していれば hook は要らない。スクリプトとテストは残してあり、本節の以下の記述は hook を戻すときの設計としてそのまま有効。

- **戻す目安**: 長いセッションの後半で `.md` を書いたときに、ダッシュや英語の比喩を直訳した語が戻ってくる
- **外したまま確定するなら**: スクリプト、テスト、本節、`japanese-style.md` 冒頭コメントの理由 2 を片づける
- **戻し方**: `.claude/settings.json` の `hooks.PreToolUse` へ次のエントリを足す

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "bun ~/dotfiles/node-scripts/src/claude-japanese-style-nudge.ts",
      "if": "Edit(//**/*.md)",
      "timeout": 10
    },
    {
      "type": "command",
      "command": "bun ~/dotfiles/node-scripts/src/claude-japanese-style-nudge.ts",
      "if": "Write(//**/*.md)",
      "timeout": 10
    }
  ]
}
```

有効にすると、PreToolUse hook（`node-scripts/src/claude-japanese-style-nudge.ts`）が、起動時ロードとは別に `.md` への書き込み時にも本文を `additionalContext` として注入し直す。起動時にロードした規範はコンテキストが伸びるほど遠ざかって効かなくなるため、現在位置へ置き直す。

settings 側では `if` を `Edit(//**/*.md)` と `Write(//**/*.md)` の 2 エントリに分ける。`if` は tool 名の直接比較で、permission rule と違って `Edit(...)` が Write tool を捕まえないため、片方だけだと新規 `.md` 作成で注入が落ちる（`claude-code-security.md` の `D18`）。

hook は本文を複製せず rule ファイルを実行時に読む。これで起動時にロードされる本文と注入される本文がずれない。

**発火頻度が設計上の主変数。** `additionalContext` は attachment として履歴へ永続的に積まれ、後続の全リクエストで再送される。prompt キャッシュが下げるのは再送の価格だけで、context window の占有量は減らない（実測: 531 モデル呼び出しのセッションで `cache_read_input_tokens` は単調増加し、減少は 6 回ともキャッシュ失効による 0 へのリセットだった）。素朴に書き込みごとへ鳴らすと占有が膨らんで compact が早まり、注入で守ろうとしていたコンテキストを自分で壊す。

そこで hook 側で `prompt_id`（ユーザーターンごとの UUID）と `agent_id` による重複排除を行い、発火を「`.md` を書いたターンにつき、エージェントごとに最大 1 回」に抑えている。過去 146 セッションでの試算では、1,678 回の `.md` 書き込みが 390 回の注入に落ち、context 占有の増分は平均 1.3%・最悪 4.6%。重複排除を外すと最悪 27.6% まで伸びる。

枠を取れなかったときも、置き場そのものが使えなかったときも注入しない（fail closed）。重複排除が効かないまま注入を続けると並行する書き込みの全てが本文を積み、頻度を抑えるという前提が消えるため、注入を落とすほうが害が小さい。

重複排除は **`wx`（存在したら失敗）でのファイル作成 1 回**で行い、EEXIST を負けたシグナルとして使う。read してから write する形では守れない。Claude Code は 1 応答に含まれる複数の Edit/Write を並行に走らせ、PreToolUse hook も並行に起動するため、全プロセスが「未注入」を読んでから書いて全員が注入する。`agent_id` をキーへ含めるのは、subagent が親と `session_id` / `prompt_id` を共有するためで、含めないと subagent が先に `.md` を書いたターンで親側の注入が消える。

`additionalContext` に `@path` を書いても展開されない。`@` import は起動時のメモリファイル読み込み専用の経路で、hook の出力はそこを通らない。

## 検証のやり方

`paths` は cwd 依存なので、**dotfiles の外を cwd にした独立セッション**が要る（`~/.claude` は `~/dotfiles/.claude` への symlink なので、dotfiles を cwd にすると rule の置き場と cwd が同じツリーに重なる）。**subagent は代替にならない**（親と同一 cwd）。この前提の詳細は `claude-code-security.md` の「別セッションでの実地検証」と共通。

判定手段と落とし穴は permission の検証と別:

- **判定はログで取る。**「rule 本文がコンテキストに現れたか」の目視に頼らない。検証用 project の `.claude/settings.json` に `InstructionsLoaded` hook を仕込み、`load_reason`（`path_glob_match` / `session_start`）と `file_path` を追記させる。起動時の `session_start` 行が hook 自体の対照になり、「マッチしなかった」と「hook が動いていない」を区別できる。ログを取り損ねても **transcript の `nested_memory` attachment** に残る（`~/.claude/projects/<project>/<session>.jsonl`）
- **候補書式は使い捨て rule を並べて 1 セッションで同時に測る。** 本番の rule を書き換えて再起動を繰り返す必要はなく、書式ごとの probe rule を `~/.claude/rules/` へ置けば本番を触らずに済む
- **rule は 1 セッションにつき 1 回しかロードされない。** 既にロードされた rule は 2 回目以降ログに出ないので、増分ゼロを「マッチしなかった」と読むと誤る。同じ書式を複数の綴り・複数の場所で踏ませる検証は、**踏ませたい順に並べるかセッションを分ける**
- **同一セッションで本文をコンテキストへ載せた rule は再注入されない。** rule ファイル自体を Read した、あるいは Write で作ったセッションでは判定しない

## 関連

- 公式 Docs（仕様の一次情報）: [memory](https://code.claude.com/docs/en/memory) / [hooks](https://code.claude.com/docs/en/hooks)
- [docs/claude-code-security.md](./claude-code-security.md): permission / sandbox の設計と検証済み delta
- `.claude/rules/`: rule の実体
