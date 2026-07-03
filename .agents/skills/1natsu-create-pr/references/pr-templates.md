# PR description テンプレート

## 機能追加 (en)

```markdown
## Summary
- Add [feature name] to improve [benefit]
- Implement [technical approach]

## Test plan
- [ ] Test happy path scenario
- [ ] Test edge cases
- [ ] Verify no regressions
```

## 機能追加 (ja)

```markdown
## 概要
- [機能名]を追加して[利点]を改善
- [技術的アプローチ]を実装

## テスト計画
- [ ] 正常系シナリオのテスト
- [ ] エッジケースのテスト
- [ ] リグレッションがないことを確認
```

## バグ修正 (en)

```markdown
## Summary
- Fix [issue description]
- Root cause was [explanation]

## Test plan
- [ ] Reproduce original issue
- [ ] Verify fix resolves issue
- [ ] Test related functionality
- [ ] Add regression test
```

## バグ修正 (ja)

```markdown
## 概要
- [問題の説明]を修正
- 根本原因は[説明]

## テスト計画
- [ ] 元の問題を再現
- [ ] 修正が問題を解決することを確認
- [ ] 関連機能をテスト
- [ ] リグレッションテストを追加
```

## リファクタリング (en)

```markdown
## Summary
- Refactor [component/module] for better [maintainability/performance]
- No functional changes

## Test plan
- [ ] All existing tests pass
- [ ] No behavioral changes
- [ ] Code coverage maintained or improved
```

## リファクタリング (ja)

```markdown
## 概要
- [コンポーネント/モジュール]をリファクタリングして[保守性/パフォーマンス]を向上
- 機能的な変更なし

## テスト計画
- [ ] 既存のテストがすべてパス
- [ ] 動作の変更がないことを確認
- [ ] コードカバレッジの維持または改善
```

## 破壊的変更 (en)

```markdown
## Summary
- [High-level description of changes]
- [Key improvement or benefit]

## Breaking Changes
- [What changed and how it affects consumers]

## Migration Guide
1. [Step 1]
2. [Step 2]

## Test plan
- [ ] New API endpoints function correctly
- [ ] Migration script tested on staging
- [ ] Documentation reflects all breaking changes
```

## 破壊的変更 (ja)

```markdown
## 概要
- [変更の概要]
- [主な改善または利点]

## 破壊的変更
- [何が変更され、利用者にどう影響するか]

## マイグレーションガイド
1. [手順1]
2. [手順2]

## テスト計画
- [ ] 新しいAPIエンドポイントが正しく機能
- [ ] ステージング環境でマイグレーションスクリプトをテスト
- [ ] ドキュメントがすべての破壊的変更を反映
```

## 複雑な変更 (en)

```markdown
## Summary
- [High-level description]
- [Key improvement]

## Background
[Context or motivation for this change]

## Implementation Details
- [Approach taken]
- [Key design decisions]

## Test plan
- [ ] Unit tests for new functionality
- [ ] Integration tests for workflows
- [ ] Performance benchmarks
```

## 複雑な変更 (ja)

```markdown
## 概要
- [変更の概要]
- [主な改善]

## 背景
[この変更のコンテキストまたは動機]

## 実装の詳細
- [採用したアプローチ]
- [主要な設計決定]

## テスト計画
- [ ] 新機能の単体テスト
- [ ] ワークフローの統合テスト
- [ ] パフォーマンスベンチマーク
```

## 言語クイックリファレンス

| English | Japanese |
|---------|----------|
| Summary | 概要 |
| Test plan | テスト計画 |
| Background | 背景 |
| Implementation Details | 実装の詳細 |
| Breaking Changes | 破壊的変更 |
| Migration Guide | マイグレーションガイド |