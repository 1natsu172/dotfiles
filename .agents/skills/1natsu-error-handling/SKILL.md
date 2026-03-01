---
name: 1natsu-error-handling
description: エラーハンドリングの実装、try-catchブロックの記述、エラーハンドリング層の設計、エラー伝播のレビュー時に使用する。言語を考慮した構造的エラーハンドリングのガイドラインを提供する。
license: MIT
metadata:
  author: 1natsu
  version: "1.1.0"
---

# エラーハンドリング ガイドライン

サイレントな失敗を防ぎ、適切なエラー伝播を保証するための構造的エラーハンドリングパターン。

## いつ使うか

- 任意の言語でエラーハンドリングを実装するとき
- try-catch / try-except ブロックを書く・レビューするとき
- エラーハンドリング層やミドルウェアを設計するとき
- エラーの握りつぶしやハンドリング漏れをレビューするとき

## 原則

### エラーを握りつぶさない

エラーは意味のあるハンドリングをするか、呼び出し元に伝播させなければならない。空のcatchブロックは禁止。

### 末端ではなく境界でハンドリングする

末端の関数（ビジネスロジック、ユーティリティ）はエラーをthrow/raiseすべき。キャッチするのは**アーキテクチャの境界** — APIハンドラ、UIレイヤー、ジョブランナー、ミドルウェア — で構造的にハンドリングできる場所。

### レイヤーごとに関心を分離する

- **ドメイン層**: ドメイン固有のエラーをthrow
- **インフラ層**: インフラのエラーをドメインエラーに変換
- **プレゼンテーション層**: エラーをユーザー向けのレスポンスに変換

### 適切な粒度でキャッチする

大きなブロックを1つのtryで囲むのは避ける。tryブロックは小さく保ち、エラー発生箇所を明確にする。

### カスタムエラー型を使う

型/クラスでエラーの種類を区別し、ハンドラが適切に分岐できるようにする。

### ロギングとハンドリングを混同しない

ロギングはオブザーバビリティ。ハンドリングはアクション（リトライ、フォールバック、ユーザー通知）。両方とも境界のハンドラで行う — 各レイヤーで `console.log` してre-throwしない。

### リソースのクリーンアップを保証する

`finally` / `defer` / `with` / `using` を使い、エラーパスでのリソースリークを防ぐ。

## JavaScript / TypeScript

### 戦略

- **末端の関数**: エラーを検出して `throw` する。キャッチしない。
- **ミドルウェア / 境界**: 集約ハンドラでエラーを構造的にキャッチする。
- **非同期コード**: `async/await` のエラーは必ず上流で `try-catch` または `.catch()` でハンドリングする。

### アンチパターン

```typescript
// BAD: 空のcatch — エラーを握りつぶしている
try {
  await fetchData();
} catch (e) {}

// BAD: console.logだけ — 実際のハンドリングがない
try {
  await fetchData();
} catch (e) {
  console.log(e);
}

// BAD: 末端でキャッチしてデフォルト値を返す — 呼び出し元がDBエラーとデータ不在を区別できない
async function getUser(id: string) {
  try {
    return await db.users.findById(id);
  } catch {
    return null;
  }
}
```

### 推奨パターン

```typescript
// GOOD: 末端ではthrowし、エラーを伝播させる
async function getUser(id: string): Promise<User> {
  const user = await db.users.findById(id); // DBエラーは自然に伝播
  if (!user) {
    throw new NotFoundError(`User not found: ${id}`);
  }
  return user;
}

// GOOD: 境界で集約ハンドリング
app.use((err, req, res, next) => {
  if (err instanceof NotFoundError) {
    return res.status(404).json({ error: err.message });
  }
  logger.error(err);
  return res.status(500).json({ error: "Internal Server Error" });
});
```