---
name: 1natsu-entire-context
description: entireが導入されているリポジトリで、セッション履歴や作業経緯、意思決定の背景、過去の会話内容を参照したい場合に使用する。entire CLIの正しいアクセス方法と制約を提供する。
license: MIT
metadata:
  author: 1natsu
  version: "0.1.0"
---

# entire コンテキスト参照

entire CLI を使ってセッション履歴・チェックポイントにアクセスするためのリファレンス。

## 前提条件

最初に `entire status` を実行する。正常に出力されれば entire は有効。コマンドが見つからない、または未初期化の場合は entire は使えないため、git 履歴（`git log`, `git diff` 等）で代替する。

## コマンド

### セッション説明（段階的に深掘りする）

トークン消費を抑えるため、短い要約から始める：

```bash
entire explain -s          # 1. 短い要約（まずこれ）
entire explain             # 2. デフォルト（不十分な場合）
entire explain --full      # 3. 完全な詳細（最後の手段）
```

### 特定のコミット・セッション

```bash
entire explain -c <commit-hash>        # 特定コミットのコンテキスト
entire explain --session <session-id>  # 特定セッションのコンテキスト
```

### チェックポイント一覧

```bash
entire rewind --list    # JSON形式でチェックポイント一覧
```

コマンドの全フラグは [references/entire-commands.md](references/entire-commands.md) を参照。

## 制約

- `.entire/metadata/**` を直接読み取らない（deny ルールあり）。必ず `entire` CLI を経由する
- `--full` は大量のトークンを消費する。`-s` から始めること
- `entire explain --generate` は LLM 呼び出しを伴う。キャッシュ済みの説明で十分な場合は使わない
