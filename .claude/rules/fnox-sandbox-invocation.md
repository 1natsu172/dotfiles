# sandbox 内での fnox ラッパー呼び出し

<!-- eager ロード（paths トリガなし）: 「npm/yarn を打つ」契機はファイル編集を伴わず paths で捕捉できないため、実行前に効かせるべく常時ロードする。数行に抑える。 -->

sandbox 有効時、**token を要する** npm / yarn / pnpm / bun 操作（本リポジトリは既定 registry が公開セキュリティプロキシ `npm.flatt.tech`〈Takumi Guard〉で、`.npmrc` が個人 token を参照＝未注入だと 401）は、素のラッパー（`npm install`）ではなく **`fnox exec -- <pm> …` の形で明示的に打つ**。

- 素のラッパーは Claude の submit 文字列が `npm …` で `excludedCommands: ["fnox *"]` に当たらず sandbox 内に残る → op（Go 製）が Seatbelt 下で TLS 検証に失敗して token 未解決 → 401。
- `fnox exec -- <pm> …` は `fnox *` に当たり sandbox 外で実行され op が解決できる（その install のみ unsandbox になる＝`npm */yarn *` の全除外より狭い、を許容）。
- token 不要のコマンドは素のラッパー（sandbox 内）のままでよい（`npm --version` 等は WARN が出ても無害）。

理由・切り分けの実機ログ: `docs/fnox-token-management.md` §sandbox / permission、`docs/claude-code-security.md` §fnox。
