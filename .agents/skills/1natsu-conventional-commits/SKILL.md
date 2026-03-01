---
name: 1natsu-conventional-commits
description: Conventional Commitsのフォーマット、タイプ、スコープ、破壊的変更、本文・フッターの書き方が必要なときに自動的に参照される内部リファレンス。コミットメッセージやPRタイトルの作成時に他のスキルから利用される。
user-invocable: false
license: MIT
metadata:
  author: 1natsu
  version: "1.0.0"
---

# Conventional Commits リファレンス

[Conventional Commits](https://www.conventionalcommits.org/) の包括的なリファレンス。

## いつ使うか

- コミットメッセージを書くとき
- PRタイトルを作成するとき
- 変更履歴の分類が必要なとき

## フォーマット

```
<type>(<scope>): <description>

[任意の本文]

[任意のフッター]
```

## タイプリファレンス

| タイプ | 用途 | 例 |
|--------|------|-----|
| `feat` | 新機能 | `feat(auth): add OAuth2 login` |
| `fix` | バグ修正 | `fix(api): resolve timeout error` |
| `docs` | ドキュメント | `docs(api): add endpoint examples` |
| `style` | フォーマット変更、ロジック変更なし | `style(components): fix indentation` |
| `refactor` | コード再構成、動作変更なし | `refactor(utils): simplify validation` |
| `perf` | パフォーマンス改善 | `perf(queries): optimize database calls` |
| `test` | テストの追加・更新 | `test(auth): add login flow tests` |
| `build` | ビルドシステムや依存関係 | `build(webpack): update config` |
| `ci` | CI/CD設定 | `ci(actions): add test workflow` |
| `chore` | メンテナンスタスク | `chore(deps): update dependencies` |
| `revert` | 以前のコミットの取り消し | `revert: feat(auth): add OAuth2` |

## description のルール

- 絵文字なし
- 命令形を使う："add"（"added" や "adds" ではなく）
- 先頭を大文字にしない
- 末尾にピリオドをつけない
- 可能なら50文字以内に収める

## スコープのガイドライン

スコープは任意。影響範囲を示す：

**モジュール別：** `feat(auth):`, `fix(payment):`, `docs(api):`

**コンポーネント別：** `feat(button):`, `fix(modal):`, `style(navbar):`

**レイヤー別：** `feat(frontend):`, `fix(backend):`, `refactor(database):`

**スコープなし**（グローバルな変更）：`chore: update all dependencies`

## 破壊的変更

タイプ/スコープの後に `!` を付けて示す：

```
feat(api)!: change endpoint response format

BREAKING CHANGE: API responses now use camelCase instead of snake_case
```

## 本文のガイドライン

descriptionだけでは不十分な場合、本文でコンテキストを補足する：

```
fix(parser): handle nested quotes in CSV fields

パーサーがクォート文字列内のカンマを含むすべてのカンマで分割していた。
クォートの深さを追跡するステートを追加し、フィールド境界を
正しく識別できるようにした。
```

- descriptionとは空行で区切る
- **何を** **なぜ** 変更したかを説明する（**どうやって**は不要）
- 1行72文字で折り返す

## フッター

破壊的変更やissue参照に使う：

```
feat(api): change authentication endpoint

BREAKING CHANGE: /auth/login now requires email instead of username

Refs: #123
```

## カテゴリ別の例

### 機能追加
```
feat(search): add fuzzy search capability
feat(export): support CSV export
feat(i18n): add Japanese localization
```

### バグ修正
```
fix(validation): prevent empty email submission
fix(cache): resolve race condition in cache updates
fix(auth): handle expired token gracefully
```

### パフォーマンス
```
perf(images): implement lazy loading
perf(queries): add database indexes
perf(bundle): reduce JavaScript bundle size
```

### リファクタリング
```
refactor(auth): extract validation logic
refactor(components): convert to TypeScript
refactor(api): consolidate duplicate code
```
