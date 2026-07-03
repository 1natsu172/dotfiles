# entire CLI コマンドリファレンス

## entire status

リポジトリの entire 状態を確認する。

```bash
entire status
```

entire が初期化されているか、現在のセッション情報、チェックポイント数などを表示する。

## entire explain

セッションやコミットの説明を取得する。

```bash
# デフォルトの説明
entire explain

# 短い要約
entire explain -s
entire explain --short

# 完全な詳細
entire explain --full

# LLMで説明を生成（キャッシュがない場合や再生成したい場合）
entire explain --generate

# 特定コミットの説明
entire explain -c <commit-hash>
entire explain --commit <commit-hash>

# 特定セッションの説明
entire explain --session <session-id>
```

### フラグの組み合わせ

```bash
# 特定コミットの短い要約
entire explain -c <commit-hash> -s

# 特定セッションの完全な詳細
entire explain --session <session-id> --full

# 特定コミットの説明を再生成
entire explain -c <commit-hash> --generate
```

## entire rewind

チェックポイントの一覧と管理。

```bash
# チェックポイント一覧（JSON形式）
entire rewind --list
```

出力にはチェックポイントID、タイムスタンプ、関連コミットなどが含まれる。

## よく使うコマンドパターン

### コンテキスト回復（段階的）

```bash
# 1. 状態確認
entire status

# 2. 短い要約で概要を把握
entire explain -s

# 3. 必要に応じて詳細を取得
entire explain
entire explain --full
```

### PR作成の準備

```bash
# 1. チェックポイント一覧で対象期間を確認
entire rewind --list

# 2. 作業経緯の要約を取得
entire explain -s

# 3. 特定コミットの背景を確認（必要に応じて）
entire explain -c <commit-hash>
```

### 複数セッションの調査

```bash
# 1. チェックポイント一覧でセッションIDを特定
entire rewind --list

# 2. 各セッションの要約を順に確認
entire explain --session <session-id-1> -s
entire explain --session <session-id-2> -s

# 3. 関連するセッションの詳細を取得
entire explain --session <session-id> --full
```
