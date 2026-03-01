---
name: 1natsu-commit
description: gitコミットの作成、コミットメッセージの記述、変更のステージング時に使用する。Conventional Commitsやアトミックコミット、明確なコミットメッセージのベストプラクティスを提供する。
license: MIT
metadata:
  author: 1natsu
  version: "1.2.0"
---

# Git コミット ベストプラクティス

クリーンで意味のあるgitコミットを作成するためのガイドライン。

## いつ使うか

- gitコミットを作成するとき
- コミットメッセージを書く・レビューするとき
- 変更のステージングやグルーピングを決めるとき

## コミットメッセージのフォーマット

[Conventional Commits](https://www.conventionalcommits.org/) に従う。タイプ、description、スコープ、本文、フッターの詳細ルールは `1natsu-conventional-commits` スキルを参照。

```
<type>(<scope>): <description>

[任意の本文]

[任意のフッター]
```

## アトミックコミット

各コミットは**1つの論理的な変更**を表すべき：

- リファクタリングと機能追加を分離する
- フォーマット変更とロジック変更を分離する
- 依存関係の更新とコード変更を分離する
- 各コミットはコードベースを動作する状態に保つ

### ステージング戦略

- `git add .` や `git add -A` ではなく `git add <具体的なファイル>` を使う
- コミット前に `git diff --staged` でステージ済みの変更を確認する
- 生成ファイル、シークレット、環境ファイルのコミットを避ける

## よくある間違い

1. **曖昧なメッセージ**: "fix bug", "update code", "WIP"
2. **変更が多すぎる**: 無関係な変更を1コミットにまとめる
3. **シークレットのコミット**: `.env`、APIキー、認証情報
4. **巨大なコミット**: 多数のファイルにまたがる数百行の変更
5. **時制の誤り**: "fix" ではなく "fixed"、"add" ではなく "added"

## 例

**良いコミット：**

```
feat(auth): add two-factor authentication support
fix(cart): prevent duplicate items on rapid click
refactor(db): extract query builder into separate module
test(auth): add integration tests for password reset
docs(api): document rate limiting headers
chore(deps): update typescript to 5.4
```

**悪いコミット：**

```
update stuff
fix
WIP
asdf
Merge branch 'main' into feature（不必要なマージコミット）
```