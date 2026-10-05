# 画面

画面ごとの構成を定義する。画面を実装するIssueは、該当する画面文書から読み始める。

---

## 1. この文書群の約束

| 項目 | 内容 |
| --- | --- |
| 扱うもの | 遷移元と遷移先、表示項目、操作とキー、選択できない条件、表示する文言、手動確認 |
| 扱わないもの | ゲームの規則。規則は `spec/` の各文書に置き、本文書群からは規則IDで参照するのみとする |
| 規則ID | 画面固有の配置規則は `PRS-2xx` とし、該当する画面文書に置く（GLS-001）。それ以外の新しい規則IDを本文書群で採番しない |
| 文言 | 文章は `data/texts.csv` のIDで指定する（PRS-702）。ボタン名などの短いラベルは各画面文書に記載する |
| 手動確認 | Godotで起動して確認する条件を `U` で始まる受入IDとして各画面文書に置く（TST-200） |
| 未決事項 | 規則から一意に決まらない点は「未決事項」に案とともに記載する。承認されるまで実装で確定させない（SCP-402） |

---

## 2. 一覧

| 文書 | 画面（状態） | 手動確認 |
| --- | --- | --- |
| [components.md](components.md) | 共通UI部品 | U01, U02, U34 |
| [title.md](title.md) | タイトル（TITLE） | U03, U04, U38 |
| [settings.md](settings.md) | 設定（SETTINGS） | U05, U06 |
| [boot_error.md](boot_error.md) | 起動不可のエラー | U07 |
| [text_screen.md](text_screen.md) | 導入（NEW_GAME）・全滅（GAME_OVER）・エンディング（ENDING） | U08〜U10 |
| [town.md](town.md) | 街（TOWN） | U11, U12 |
| [guild.md](guild.md) | ギルド（FACILITY） | U13〜U16 |
| [inn.md](inn.md) | 宿屋（FACILITY） | U17 |
| [temple.md](temple.md) | 教会（FACILITY）と救済 | U18, U19 |
| [shop.md](shop.md) | 商店（FACILITY） | U20 |
| [tavern.md](tavern.md) | 酒場（FACILITY） | U21 |
| [departure.md](departure.md) | 出発先の選択（DEPARTURE） | U22 |
| [save_slots.md](save_slots.md) | セーブ（SAVE）・ロード（LOAD） | U23, U24 |
| [menu.md](menu.md) | メニュー（MENU）・能力・スキル | U25, U35 |
| [inventory.md](inventory.md) | 所持品 | U26 |
| [equipment.md](equipment.md) | 装備 | U27 |
| [map.md](map.md) | 地図 | U28 |
| [exploration.md](exploration.md) | 探索（EXPLORATION / EVENT） | U29〜U31 |
| [battle.md](battle.md) | 戦闘（BATTLE） | U32 |
| [reward.md](reward.md) | 報酬（REWARD） | U33 |

全画面に共通する解像度・キー・演出・素材は `tech/presentation.md` に置く。

---

## 3. 開発中の仮画面

| ID | 規則 |
| --- | --- |
| PRS-208 | 遷移先の画面が未実装の操作は、見出し「準備中」と戻るボタンだけの仮画面へ遷移する。戻る / Escで遷移元へ戻る。項目を選べるかどうかは本来の規則に従い、未実装を理由に選択不可にしない。段階Hの完了時点で仮画面への遷移が残っていてはならない。 |

---

## 4. 画面文書の書式

各画面文書は次の節をこの順で持つ。該当がない節は「なし」と書く。

1. **遷移** — 遷移元と遷移先（FLW-0xx）
2. **表示** — 表示する項目と根拠の規則ID
3. **操作** — 操作、結果、選択できない条件、根拠の規則ID
4. **文言** — 使用する `data/texts.csv` のID
5. **未決事項**
6. **手動確認** — `U` の受入ID。手順と合格条件を書く
