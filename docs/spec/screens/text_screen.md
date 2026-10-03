# 文章画面（NEW_GAME / GAME_OVER / ENDING）

文章を表示し、決定で次へ進む共通の画面。3つの状態で同じ画面を用いる。

---

## 1. 遷移

| 状態 | 遷移元 | 遷移先 | 根拠 |
| --- | --- | --- | --- |
| NEW_GAME | TITLEの「はじめから」 | TOWN | FLW-002 |
| GAME_OVER | BATTLE（全滅） | TITLE | FLW-011, FLW-106 |
| ENDING | REWARD（最終ボス撃破） | TOWN | FLW-012, FLW-401, FLW-402 |

---

## 2. 表示

| 状態 | 表示する文章 | 根拠 |
| --- | --- | --- |
| NEW_GAME | `intro` | FLW-002 |
| GAME_OVER | `game_over` | FLW-011 |
| ENDING | `ending`、続いて次のページで `clear_notice`。`clear_notice` で決定するとTOWNへ戻る | FLW-401, FLW-403 |

NEW_GAMEでは、文章の表示前にセッションを初期化する（FLW-002, TWN-0xx）。

---

## 3. 操作

| 操作 | 結果 | 根拠 |
| --- | --- | --- |
| 決定（Enter / 左クリック） | 次の文章へ進む。最後の文章で遷移先へ進む | PRS-503 |

---

## 4. 文言

`intro`、`game_over`、`ending`、`clear_notice`

---

## 5. 未決事項

なし。

---

## 6. 手動確認

| ID | 手順 | 合格条件 | 根拠 |
| --- | --- | --- | --- |
| U08 | TITLEで「はじめから」を選ぶ | 導入文が表示され、決定でTOWNへ進む | FLW-002 |
| U09 | 戦闘で全滅する | 全滅の文章が表示され、決定でTITLEへ戻る | FLW-011, 106 |
| U10 | 最終ボスに勝利し、報酬を閉じる | エンディング文、クリアの案内の順に表示され、決定でTOWNへ戻る | FLW-401〜403 |
