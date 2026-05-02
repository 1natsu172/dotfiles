# pair-resolve への引き継ぎプロンプト

`1natsu-auto-resolve-conflicts` が bail-out したとき、`1natsu-pair-resolve-conflicts` に作業を引き継ぐためのプロンプトテンプレート集。bail-out 理由 × 操作種別 × 進捗状況の組み合わせで使い分ける。

## 出力時のフォーマット原則

- **Markdown のコードブロック内に引き継ぎプロンプト本文を提示する**（ユーザーがコピーしてそのまま貼り付けられるように）
- bail-out 理由は構造化リスト（箇条書き）で明示する
- 「適用済み」「未着手」のファイルを区別して列挙する
- pair モードに入った時点で再度 `git status` を実行することを促す（状態の自己把握を優先するため）

## テンプレート 1: 全体 bail-out（何も適用していない）

Phase 0 の早期チェックや Phase 1 のトリアージで Auto-No が見つかり、何もファイルを変更しなかった場合。

```text
コンフリクト解消をペアモードで続行してください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: 全体 bail-out
**理由**: <bail-out 理由を Auto-No ルール参照で 1〜3 件箇条書き>

**現状**: 自動解消は何も適用していません。コンフリクト状態は元のまま保持されています。

`1natsu-pair-resolve-conflicts` の Phase 0 から開始してください。最初に `git status` で現状を確認することをお勧めします。
```

## テンプレート 2: 混合 bail-out（Auto-OK は適用済み）

Phase 1 で Auto-OK と Auto-No/Risky が混在し、独立して解消できる Auto-OK のみ適用した場合。

```text
コンフリクト解消をペアモードで続行してください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: 混合 bail-out（Auto-OK は適用、残りを引き継ぎ）
**理由**: <Auto-No に該当した条件 1〜3 件箇条書き>

**自動解消が完了したファイル**（ワーキングツリーで解消済み、ステージング前）:
- <path/to/file1> — <ours採用|統合|theirs採用> — <一行根拠>
- <path/to/file2> — <ours採用|統合|theirs採用> — <一行根拠>

**ペアモードで対応してほしいファイル**（未解消、コンフリクトマーカーが残っている）:
- <path/to/file3> — bail-out 理由: <Auto-No ルール参照>
- <path/to/file4> — bail-out 理由: <Auto-No ルール参照>

`1natsu-pair-resolve-conflicts` の Phase 0 から開始してください。`git status` で現状を確認すると、解消済みファイルと未解消ファイルが混在していることが見えます。**自動解消済みファイルの内容も念のため目視で確認してから先に進むことを推奨します**（自動解消の取り消し意思があれば、そのファイルだけ `git checkout --merge <file>` で再衝突状態に戻せます）。
```

## テンプレート 3: Phase 2 途中での bail-out（局所検証失敗）

Phase 2 のループ中に局所構文チェックが失敗し、それまで適用したファイルは残して中断した場合。

```text
コンフリクト解消をペアモードで続行してください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: Phase 2 途中で bail-out（局所検証失敗）
**理由**: ファイル `<path>` の解消後、構文チェック（`<command>`）が失敗。
**失敗の詳細**:
```
<エラー出力（末尾20行）>
```

**自動解消が完了したファイル**（ワーキングツリーで解消済み、ステージング前）:
- <path/to/file1> — <ours採用|統合|theirs採用> — <一行根拠>

**未解消ファイル**:
- <path/to/file_failed> — 局所検証で構文エラー、解消は適用されていない（再衝突状態）
- <path/to/file_remaining> — 未着手

`1natsu-pair-resolve-conflicts` の Phase 0 から開始してください。**自動解消済みファイルが残っているため、ペアモードでは解消済み内容を確認のうえ、未解消ファイルから順に対応してください**。
```

## テンプレート 4: Phase 3 検証失敗での bail-out

Phase 3 の検証コマンド実行で typecheck / lint / test / build のいずれかが失敗した場合。**全コンフリクトは解消済み・ステージング前**の状態。

```text
コンフリクト解消の検証で失敗しました。ペアモードに切り替えて方針を再検討してください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: Phase 3 検証失敗で bail-out
**全コンフリクト解消ステータス**: 適用済み・ステージング前

**失敗した検証**:
- カテゴリ: <typecheck | lint | test | build>
- コマンド: `<command>`
- 終了コード: <code>
- 出力（末尾30行）:
```
<output>
```

**自動解消が完了したファイル**:
- <path/to/file1> — <ours採用|統合|theirs採用> — <一行根拠>
- <path/to/file2> — <ours採用|統合|theirs採用> — <一行根拠>

**選択肢**:
1. 解消結果の見直し — `1natsu-pair-resolve-conflicts` で各ファイルの解消方針を再検討
2. 完全リセット — `git checkout --merge -- <files>` で再衝突状態に戻してペアでやり直し
3. 既存問題の切り分け — マージ前から検証が失敗していた可能性がある場合、`git stash` で解消結果を退避して片側コミットで検証実行

どの選択肢を取るかはコンフリクト解消の品質と、既存コードの健全性をペアモードで確認しながら判断してください。
```

## テンプレート 5: 規模超過での bail-out

Phase 0 / Phase 1 でコンフリクトファイル数や 1ファイル内ハンク数が閾値を超えた場合。

```text
コンフリクトの規模が大きいため自動解消を見送り、ペアモードで進めてください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: 規模超過で bail-out
**規模**:
- コンフリクトファイル数: <N>
- 最大ハンク数（1ファイル内）: <H>（ファイル: <path>）

**現状**: 自動解消は何も適用していません。

`1natsu-pair-resolve-conflicts` の Phase 0 から開始し、Phase 1 の俯瞰で **解消順序を依存関係から決めること** を推奨します。規模が大きいときほど依存元から解消すると判断ミスが減ります。
```

## テンプレート 7: Auto-Regenerate 失敗での bail-out

lockfile 等の再生成（`<pm> install` 等）またはその frozen 検証（`<pm> install --frozen-lockfile` / `npm ci` / `cargo build --locked` 等）が失敗した場合。

```text
コンフリクト解消をペアモードで続行してください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**自動モードの判定**: Auto-Regenerate 失敗で bail-out
**理由**: lockfile の再生成または frozen 検証に失敗。
- 対象 lockfile: <path/to/lockfile>
- 対応 manifest の状態: <変更なし | 解消済み | 未解消>
- 実行コマンド: `<pm> install` / `<pm> install --frozen-lockfile`
- 終了コード: <code>
- 出力（末尾30行）:
```
<output>
```

**自動解消が完了したファイル**（manifest など、lockfile より前に解消されたもの）:
- <path/to/file1> — <ours採用|統合|theirs採用> — <一行根拠>

**未処理ファイル**:
- <path/to/lockfile> — 再生成失敗。コンフリクトマーカー残置 / または lockfile 削除済み（要再生成）
- <path/to/file2> — 未着手

`1natsu-pair-resolve-conflicts` の Phase 0 から開始してください。lockfile の手動マージはせず、ペアで manifest の整合を再確認したうえで `<pm> install` を再試行する方針が安全です。再生成不可の場合はバージョン固定や依存削除など別の方針を相談してください。
```

## テンプレート 6: 検証コマンド未検出時のユーザー選択待ち

Phase 3 で検証コマンドが見つからず、ユーザーが「pair に渡す」を選択した場合。

```text
コンフリクト解消は完了しましたが、検証コマンドが自動検出できませんでした。検証ステップを安全に進めるため、ペアモードに切り替えてください。

**操作種別**: <merge | rebase | cherry-pick | stash pop>
**全コンフリクト解消ステータス**: 適用済み・ステージング前

**自動解消が完了したファイル**:
- <path/to/file1> — <ours採用|統合|theirs採用> — <一行根拠>
- <path/to/file2> — <ours採用|統合|theirs採用> — <一行根拠>

`1natsu-pair-resolve-conflicts` の Phase 3（全体確認とステージング）から開始し、人間と一緒に：
- 解消結果の妥当性を IDE の Diff ビューで確認
- 必要な検証手段（テスト・ビルド・手動動作確認）を相談
- ステージングとコミットの是非を判断

を進めてください。
```

## テンプレート選択フロー

```
bail-out が発動した時、以下の順で当てはまるテンプレートを選ぶ：

1. 何も適用していない & 規模超過が原因 → テンプレート 5
2. 何も適用していない & その他の Auto-No → テンプレート 1
3. Auto-OK は適用済み & Phase 1 で混合判定 → テンプレート 2
4. Phase 2 途中で局所検証失敗 → テンプレート 3
5. Phase 2 で lockfile 再生成 / frozen 検証失敗 → テンプレート 7
6. Phase 3 で検証コマンド失敗 → テンプレート 4
7. 検証コマンド未検出 & ユーザーが pair 選択 → テンプレート 6
```

## 共通の留意点

- **bail-out 理由は具体的に**: 「Auto-No に該当」だけでなく、`references/bailout-rules.md` のどのルールに該当したかを示す
- **ファイルパスは絶対パスでなく相対パスで**: pair モードはワーキングツリーで作業するため
- **「ペアでよろしくお願いします」は不要**: 操作の意図と現状を正確に伝えれば pair 側は自走できる
- **ロールバックを強制しない**: 「適用済みは残す」が本スキルの方針。pair 側でユーザーが取り消したい場合のみ対応すれば十分
