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
│  └─ パッケージ内 .claude/rules/（paths 付き）
│
├─ パッケージの概要・前提が変わったか？
│  └─ パッケージ直下 CLAUDE.md を更新（200行以下、@参照で詳細へ）
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
| パッケージの概要と重要な前提 | `packages/xxx/CLAUDE.md` | `@` 参照でインデックス |
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
- 4行以上の説明が必要 → 別ファイルにして `@` 参照
