# ドキュメント配置ガイド

## 配置判断フローチャート

```
変更内容を分析
│
├─ 横断的な規約・指示か？
│  ├─ 全パッケージ共通 → ルート .claude/rules/（paths なし）
│  └─ 特定ファイルパターン → ルート .claude/rules/（paths 付き）
│
├─ パッケージ固有の指示か？
│  ├─ パッケージ全体に適用 → パッケージ内 .claude/rules/（paths なし）
│  └─ 特定ファイルパターン → パッケージ内 .claude/rules/（paths 付き）
│
├─ パッケージの概要・前提が変わったか？
│  └─ パッケージ直下 CLAUDE.md を更新（200行以下、詳細はポインタで）
│
├─ 設計背景・アーキテクチャの知識か？
│  ├─ 特定パッケージに閉じた知識 → packages/xxx/docs/
│  └─ リポジトリ全体に関する知識 → ルート docs/
│
└─ 機能固有の仕様・データフローか？
   └─ feature ディレクトリ直下の README.md
```

## 配置先の早見表

| 書きたいこと | 配置先 | ファイル形式 |
|-------------|--------|------------|
| 全パッケージ共通のコードスタイル | `.claude/rules/code-style.md` | paths なし |
| 特定ファイルパターンの規約 | `.claude/rules/xxx.md` | `paths: ["pattern"]` |
| パッケージ固有の禁止事項 | `packages/xxx/.claude/rules/xxx.md` | `paths: ["src/**"]` |
| パッケージの概要と重要な前提 | `packages/xxx/CLAUDE.md` | ポインタでインデックス |
| パッケージ固有の設計背景 | `packages/xxx/docs/architecture.md` | 通常の markdown |
| パッケージ固有の外部依存・バッチ処理 | `packages/xxx/docs/xxx.md` | 通常の markdown |
| パッケージ固有の状態遷移 | `packages/xxx/docs/xxx-lifecycle.md` | 通常の markdown |
| リポジトリ全体のアーキテクチャ | `docs/architecture.md` | 通常の markdown |
| 横断的な設計方針・ADR | `docs/adr/NNNN-title.md` | ADR テンプレート |
| 機能のデータフロー | `src/features/xxx/README.md` | 通常の markdown |
| 機能のレイヤー間依存 | `src/features/xxx/README.md` | 通常の markdown |
| 機能の非自明な設計判断 | `src/features/xxx/README.md` | 通常の markdown |

## 判断に迷った時

### rules/ vs docs/ で迷う

- **「〜すること」「〜してはならない」** と書けるなら → `rules/`
- **「〜という背景で」「〜の理由で」** と書くなら → `docs/`
- 両方必要なら、`rules/` に指示を書き、`docs/` に理由の詳細を書く

### ルート docs/ vs パッケージ docs/ で迷う（monorepo）

- その知識が特定パッケージなしでは意味をなさない → `packages/xxx/docs/`
- 複数パッケージやリポジトリ全体に関係する → ルート `docs/`
- 迷ったらパッケージ `docs/` に置く。必要に応じてルートに昇格させる

### docs/ vs feature README で迷う

- 複数機能にまたがる知識 → `docs/`
- 1つの機能に閉じた知識 → feature `README.md`
- 迷ったら feature README に書いてから、必要に応じて docs/ に昇格させる

### CLAUDE.md に書くか別ファイルに分けるか迷う

- 3行以内で伝わる → CLAUDE.md に直接書く
- 4行以上の説明が必要 → 別ファイルに分ける。参照方法でロード挙動が変わる:
  - **常時必要** → `@path` インポート（起動時フルロード。コンテキストは節約されず整理目的）。eager 意図のマーカーを添える
  - **必要時だけでよい** → プレーンポインタ（「詳細は `docs/xxx.md`」と書くだけ。Claude が必要時に Read）。コンテキスト節約はこちら

## ロードタイミング早見表（eager / lazy）

| 手段 | 形式 | いつロードされるか | 既定 |
|---|---|---|---|
| CLAUDE.md 本体 | — | 起動時（cwd ＋祖先）。subtree は配下ファイル Read 時に on-demand | eager |
| rule（paths なし） | `paths:` なし | 起動時（cwd ＋祖先）。subtree は配下ファイル Read 時に on-demand | eager |
| rule（paths あり） | `paths: [...]` | パターンにマッチするファイルを触った時だけ | lazy |
| `@path` インポート | `@` | 起動時にフルロード（節約不可・整理目的） | eager |
| docs プレーンポインタ | `@` なし | Claude が必要時に Read | lazy |
| skill | SKILL.md | 関連時に on-demand | lazy |

既定は lazy に倒し、eager にする時はその場に意図マーカーを残す（→ SKILL.md「コンテキスト経済: eager / lazy と意図の明示」）。

> 注: `@path` は CLAUDE.md 本文に書いただけで import が発火する。パスを「説明として言及」したいだけならバックティックで囲む（例 `` `@README` ``）。import 解析は Markdown のコードスパン／フェンス内をスキップするため、囲めば literal のまま残る。

## ネスト rules と glob 解決（monorepo・実測準拠）

ネストした `packages/xxx/.claude/rules/` は正式にロードされる（`paths` なしなら配下ファイルを Read した時に on-demand、`paths` ありならマッチ時）。

`paths` の glob は **その rule ファイルのあるディレクトリ基準**で解決される（repo root 基準ではない）:

- ルート `.claude/rules/api.md` の `paths: ["packages/api/src/**"]` → repo root 起点でマッチ
- パッケージ `packages/api/.claude/rules/api.md` の `paths: ["src/**"]` → **パッケージ起点**で `packages/api/src/**` にマッチ

→ パッケージ内 rule の `paths` はパッケージ相対で短く書く（`src/**`）のが正しい。

`paths` のマッチは、v2.1.198 以降 **symlink 経由でプロジェクトディレクトリへ到達したパスにも効く**（symlinked checkout 等）。これは上流ドキュメント記載の仕様で、本節の他項目（実測準拠）とは異なり未実測。

> 注: プロジェクト `.claude/settings.json` は**起動ディレクトリのものだけ**読まれ、祖先からは継承されない（CLAUDE.md/rules の継承挙動とは別）。
