# コーディングルール

## エラーハンドリング

- エラーハンドリングを省略しないこと
  - JavaScriptおよびTypeScriptの場合：エラーハンドリングは末端でエラーを握り潰さず、上位層へThrowし設計上のコード境界にて関心の分離を意識したエラーハンドリング関数で構造的にエラーハンドリングの実装をすること

## プライバシー

- シークレットキーや証明書・APIトークンといった秘匿情報は**絶対に**ハードコードしないこと
  - 環境変数や設定ファイルを使用して秘匿情報を管理すること
    - 設定ファイルにシックレット情報が含まれる場合は、`.gitignore`に追加してGitにコミットしないこと
  - 例文やコメントにおけるexampleは常に秘匿情報や特定情報に繋がらないように配慮すること
