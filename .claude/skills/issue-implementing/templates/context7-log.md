# Context7の調査ログの型

メインエージェントが手順3で、`<scratchpad>/issue-<N>/context7-log.md` に**1件ずつ追記する。** `architecture-reviewer` はこのログと差分を照合し、確認なしに使われたAPIを探す。

---

```markdown
# Context7の調査ログ：Issue #<N>

ライブラリID：`/websites/godotengine_en_4_5`

| # | サイクル | 確認した事項 | 問い合わせ | 出典URL | 結論 | 使った箇所 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | <何を確かめたかったか> | <query-docs に渡した文> | <https://docs.godotengine.org/en/4.5/...> | <分かったこと。想定と違った場合はそれも書く> | <file:line> |
```

| 列 | 書き方 |
| --- | --- |
| 確認した事項 | 1件につき概念を1つにする（例：「Autoload の名前と同じ `class_name` を付けたときの扱い」） |
| 出典URL | `docs.godotengine.org/en/4.5/` 配下だけを書く。見つからなかった場合は「該当なし」 |
| 問い合わせ | Context7 に問い合わせた場合は、`query-docs` に渡した文。確認済みキャッシュから使った場合は「キャッシュ」と書く（`architecture-reviewer` は、キャッシュから使った記録を再び問い合わせない） |
| 結論 | 見つからなかった場合や、Context7が使えなかった場合は「未確認」と書き、どう扱ったか（テストで確かめた、PRに載せた）を添える |
| 使った箇所 | 結論に基づいて書いたコードの位置 |
