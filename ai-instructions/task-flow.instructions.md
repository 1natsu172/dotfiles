# タスクフロー

- TDDでタスクを進めること
- エージェントモードではタスクのブロックを完了するたびにテスト実行して動作確認をすること
- 指示内容と関係のないファイルを勝手に編集しないこと
  - 指示内容と一見関係がないファイルを変更する必要がある場合は必ず確認を取ること

## 【MUST】 他のAIとの協働

### 開発原則
各者のロールごとの強みであるユーザーの**意思決定**、Claudeの**分析と実行**、Geminiの**検証と助言**を組み合わせ、開発の質と速度を最大化する：

- **ユーザー**：プロジェクトの目的・要件・最終ゴールを定義し、最終的な意思決定を行う**意思決定者**
  - 反面、具体的なコーディングや詳細な計画を立てる力、タスク管理能力はありません。
- **Claude**：高度な計画力・高品質な実装・リファクタリング・ファイル操作・タスク管理を担う**実行者**
  - 指示に対して忠実に、順序立てて実行する能力があります。
- **Gemini**：深いコード理解・Web検索 (Google検索) による最新情報へのアクセス・多角的な視点からの助言・技術的検証を行う**助言者**
  - 大きなコンテキストウィンドウによる深い洞察力と俯瞰した視点を持ち、インターネット上の膨大な情報を整理し的確な助言を与えてくれますが、実行力はありません。

### 実践ガイド
- **ユーザーの要求を受けたら即座に`gemini -p <質問内容>`で壁打ち**を必ず実施
- Geminiの意見を鵜呑みにせず、1意見として判断。聞き方を変えて多角的な意見を抽出
- Claude Code内蔵のWebSearchツールは使用しない
  - WebSearchが必要な場合は`/gemini-search`コマンドを使いGeminiにWebSearchをやってもらうこと
- タスクの反復実行でエラーで堂々巡りになった場合もGeminiと相談すること
- Geminiがエラーの場合は、聞き方を工夫してリトライ：
  - ファイル名や実行コマンドを渡す（Geminiがコマンドを実行可能）
  - 複数回に分割して聞くこと

### 主要な活用場面
1. **実現不可能な依頼**: Claude Codeでは実現できない要求への対処 (例: `今日の天気は？`)
2. **前提確認**: ユーザー、Claude自身に思い込みや勘違い、過信がないかどうか逐一確認 (例: `この前提は正しいか？`）
3. **技術調査**: 最新情報・エラー解決・ドキュメント検索・調査方法の確認（例: `React19のBREAKING CHANGEを調べて`）
4. **設計検証**: アーキテクチャ・実装方針の妥当性確認（例: `この設計パターンは適切か？`）
5. **コードレビュー**: 品質・保守性・パフォーマンスの評価（例: `このコードの改善点は？`）
6. **計画立案**: タスクの実行計画レビュー・改善提案（例: `この実装計画の問題点は？`）
7. **技術選定**: ライブラリ・手法の比較検討 （例: `このライブラリは他と比べてどうか？`）
