# data

初回版の固定データ。**数値・ID・文章の唯一の正はこのディレクトリのCSVとする。** 仕様文書に数値表を複写しない。

`content_version` は `0.1.0`。ID・数値テーブルを破壊的に変更した場合はこの値を更新する（SAV-5xx）。

## ファイル

| ファイル | 件数 | 内容 |
| --- | --- | --- |
| `jobs.csv` | 5 | 職業、レベル1基礎値、固定増加値、追加+1確率、初期装備・初期スキル |
| `skills.csv` | 25 | 味方スキルのメタ情報 |
| `skill_effects.csv` | 27 | スキルの効果。`order` 昇順に適用する |
| `equipment.csv` | 21 | 武器12・防具6・装飾品3 |
| `items.csv` | 9 | 消耗品5・素材4 |
| `item_effects.csv` | 5 | 消耗品の効果 |
| `enemies.csv` | 14 | 通常12・ボス2 |
| `enemy_modifiers.csv` | 24 | 属性倍率と状態異常耐性倍率。記載のないものは1.0 |
| `enemy_actions.csv` | 10 | 敵行動のメタ情報 |
| `enemy_action_effects.csv` | 11 | 敵行動の効果 |
| `enemy_action_weights.csv` | 23 | 重み付き行動表。敵ごとの重み合計は100 |
| `enemy_action_cycles.csv` | 9 | 固定巡回。`turn_index` の最大値が周期 |
| `floors.csv` | 6 | フロアのメタ情報と想定レベル |
| `encounters.csv` | 18 | フロアごとの3編成。すべて weight=1 |
| `floor_events.csv` | 44 | セルイベント。`event_id` は全体で一意 |
| `chest_rewards.csv` | 12 | 宝箱の中身。経験値は設定しない |
| `quests.csv` | 6 | クエストと解禁条件・報酬 |
| `shop_tiers.csv` | 3 | 商店の品揃え解禁条件 |
| `texts.csv` | 32 | 導入・ボス前後・エンディング・会話碑・システムメッセージ・エラーコードの表示文 |

## 記法

- 複数値は `|` で区切る（`mage|priest`、`slime|bat`）。
- 空欄は「なし」を表す。`buy_price` の `-1` は非売品。
- `texts.csv` の `{gold}` のような波括弧は、表示時に値を埋め込む箇所を表す。エラーコードの表示文のIDは `error_` + エラーコードの小文字とする（ARC-402）。
- 確率は0〜1の小数。`status_chance` は基礎成功率であり、実際の付与率はBTL-016で算出する。
- 向き（`facing`、`link_facing`）は 北0・東1・南2・西3。
- `unlock_from_x` / `unlock_from_y` は、そのセルから見た開通許可側の差分（南なら `0,1`）。

## 実装での扱い

段階B（データ）で、このCSVから `class_name` 付きResourceの `.tres` を生成するか、起動時に直接読み込む。いずれの場合も、生成物ではなくCSVを編集する。バリデータはDAT-9xxに従い、上表の件数・参照先ID・値域を起動時に検査する。

## 調整の記録

バランス調整でこのディレクトリの値を変更した場合、変更値と理由を `docs/decisions/log.md` に追記する。
