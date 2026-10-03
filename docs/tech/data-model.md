# データ型・状態モデル

固定データの型、可変状態のモデル、バリデータを定義する。

**この文書が扱わない範囲**

| 関心事 | 所在 |
| --- | --- |
| 数値そのもの | `data/`（`data/README.md` を参照） |
| 装備の `stat_bonus` のHP・SPの扱い | `spec/35-inventory.md`（INV-309） |
| セーブファイルの形式と保存手順 | `spec/70-save.md` |
| サービスの責務 | `tech/architecture.md` |

---

## 1. 方針（DAT-0xx）

| ID | 規則 |
| --- | --- |
| DAT-000 | 固定データは `class_name` 付きの `Resource` 型として扱う。`data/` のCSVを唯一の正とし、そこから `.tres` を生成するか起動時に読み込む。 |
| DAT-001 | すべてのIDを一意の `StringName` とする（GLS-4xx）。 |
| DAT-002 | `Resource` は固定の定義として扱う。戦闘中のHPや宝箱の開封状態を `Resource` 自体へ書き込まない。 |
| DAT-003 | 可変の値は `RefCounted` の状態モデルに置く。 |
| DAT-004 | 生成物ではなく `data/` のCSVを編集する。 |

---

## 2. 共通型（DAT-1xx）

| ID | 型 | 必須フィールド |
| --- | --- | --- |
| DAT-100 | StatBlock | hp, sp, str, vit, tec, agi, luc : int |
| DAT-101 | StatChance | hp, sp, str, vit, tec, agi, luc : float（0〜1） |
| DAT-102 | ItemStackDef | item_id : StringName, quantity : int（1以上） |
| DAT-103 | RewardDef | exp : int, gold : int, items : Array[ItemStackDef] |
| DAT-104 | RngSnapshot | seed_decimal : String, state_decimal : String |
| DAT-105 | ActionEffect | kind, damage_model, element, power:int, multiplier:float, defense_ratio:float, status_id, status_chance:float, restore_ratio:float, restore_flat:int, duration_steps:int, requires_previous_hit:bool |

### 2.1 ActionEffect

| ID | 規則 |
| --- | --- |
| DAT-110 | `kind` は DAMAGE、HEAL、RESTORE_SP、REVIVE、CURE_POISON、APPLY_STATUS、COVER、SUPPRESS_ENCOUNTERS、RETURN_TOWN、NO_OP のいずれかとする。 |
| DAT-111 | `damage_model` は PHYSICAL、MAGICAL、NONE のいずれかとする。 |
| DAT-112 | `element` は physical、fire、ice、lightning、none のいずれかとする。 |
| DAT-113 | 使用しない数値は0、倍率の既定値は1とする。 |
| DAT-114 | `requires_previous_hit` の既定値をfalseとする。効果は配列順に適用する（BTL-211, BTL-212）。 |
| DAT-115 | `duration_steps` は探索効果にのみ用いる。戦闘の状態異常の期間はBTL-4xxの共通規則に従う。 |
| DAT-116 | `target` は SELF、LIVING_ALLY、DEAD_ALLY、OTHER_LIVING_ALLY、ALL_LIVING_ALLIES、LIVING_ENEMY、ALL_LIVING_ENEMIES、PARTY のいずれかとする。ALLYはプレイヤー側、ENEMYは敵側を指す。行動者が敵であっても視点を変えない（敵行動の LIVING_ALLY はプレイヤー側の生存者を指す）。 |
| DAT-117 | `contexts` は town、exploration、battle の組み合わせとする。 |
| DAT-118 | 通常攻撃と防御は固定のコマンドとして `BattleRules` が保持する。データとして定義しない。 |
| DAT-119 | `status_id` は poison、paralysis、sleep のいずれかとする。 |
| DAT-120 | 敵の `action_mode` は weighted（`enemy_action_weights.csv` を用いる）または cycle（`enemy_action_cycles.csv` を用いる）とする。 |
| DAT-121 | `enemy_modifiers.csv` の `kind` は element または status とする。`key` は element では DAT-112 のうち none 以外、status では DAT-119 の値とする。 |
| DAT-122 | 商店の品揃え `shop_tier` は A、B、C の列挙値とする。IDではないため GLS-400 を適用しない。 |
| DAT-123 | セルイベントの `kind` は town_exit、stairs、link、door、shortcut、chest、inscription、boss、warp のいずれかとする。 |
| DAT-124 | 所持品・宝箱・報酬・ドロップの `item_id` は、`items.csv` と `equipment.csv` の和集合を参照する。両者の間でIDを重複させない。 |

---

## 3. 定義Resource（DAT-2xx）

| ID | 型 | フィールド |
| --- | --- | --- |
| DAT-200 | JobDef | id, name, base_stats:StatBlock, growth_fixed:StatBlock, growth_extra_chance:StatChance, starting_weapon_id, starting_armor_id, initial_skill_id, weapon_category, learnable_skill_ids（導出）, armor_ids（導出） |
| DAT-201 | SkillDef | id, name, job_id, required_level:int, learn_cost:int, sp_cost:int, target, contexts, priority:int, always_hit:bool, effects:Array[ActionEffect] |
| DAT-202 | EquipmentDef | id, name, slot:weapon/armor/accessory, category, allowed_jobs, attack:int, defense:int, stat_bonus:StatBlock, buy_price:int, sell_price:int, shop_tier, icon:Texture2D（DAT-228） |
| DAT-203 | ItemDef | id, name, kind:consumable/material, max_stack:int=9, buy_price:int（-1は非売品）, sell_price:int, shop_tier, target, contexts, effects, icon:Texture2D（DAT-228） |
| DAT-204 | EnemyDef | id, name, hp, attack, defense, tec, agi, luc, element_multipliers:Dictionary, status_multipliers:Dictionary, exp, gold, drop_item_id, drop_chance:float, action_mode, action_weights:Array[WeightedAction], action_cycle:Array[StringName], portrait:Texture2D（DAT-228）, is_boss:bool |
| DAT-205 | EnemyActionDef | id, name, target, priority:int, always_hit:bool, effects。SPを消費しない |
| DAT-206 | WeightedAction | action_id:StringName, weight:int（1以上） |
| DAT-207 | QuestDef | id, title, description（DAT-230）, unlock:ConditionDef, kind:kill/deliver, target_id, target_count:int, reward:RewardDef |
| DAT-208 | ConditionDef | kind:always/floor_visited/boss_first_defeated/warp_unlocked, target_id |
| DAT-209 | EncounterDef | enemy_ids:Array[StringName], weight:int |
| DAT-210 | FloorDef | id, display_name, dungeon, order:int, expected_level_min:int, expected_level_max:int, authoring_scene:PackedScene（DAT-229）, encounters:Array[EncounterDef], events:Array[CellEventDef], default_spawn:Vector2i, default_facing:int |
| DAT-211 | CellEventDef | id, cell:Vector2i, kind, link_floor_id, link_cell:Vector2i, link_facing:int, reward:RewardDef, enemy_id, unlock_from:Vector2i, warp_id, text_id |

| ID | 規則 |
| --- | --- |
| DAT-221 | `growth_fixed` に装備補正を含めない。 |
| DAT-222 | `priority` は防御とかばうを100、その他を0とする（BTL-113）。 |
| DAT-223 | 初期スキルの `learn_cost` を0とする。購入不可ではなく、作成時から習得済みとして重複を防ぐ（PTY-403）。 |
| DAT-224 | `StatBlock` における装備の加算値は、未指定であれば0とする。 |
| DAT-225 | `CellEventDef` は `kind` ごとに必要なフィールドが異なる。次の表に従って必須欄を検証し、表にない欄は空とする。 |
| DAT-226 | 商店の品揃えの解禁条件は `ConditionDef` で表し、tierからの対応表を `GameDatabase` が保持する（TWN-236）。 |
| DAT-227 | `JobDef.learnable_skill_ids` は `skills.csv` の `job_id`、`armor_ids` は `equipment.csv` の `allowed_jobs` から読込時に導出する。CSVに列を設けない。 |
| DAT-228 | 装備とアイテムの `icon` は `res://assets/icons/{id}.png`、敵の `portrait` は `res://assets/enemies/{id}.png`、冒険者の顔は `res://assets/portraits/{portrait_id}.png` から解決する。ファイルが存在しない場合は仮の図形を表示し、検証エラーとしない（PRS-601, 602）。 |
| DAT-229 | `FloorDef.authoring_scene` は `res://scenes/floors/{id}.tscn` から解決する。シーンの存在と内容の検証はマップのコンパイル（D02, D04）で行い、データベースの読込（D01）では行わない。 |
| DAT-230 | `QuestDef.description` は `data/texts.csv` の `quest_{id}` から解決する。 |
| DAT-231 | ボスの文章は `data/texts.csv` の `boss_{敵ID}_pre`（全ボス）、`boss_{敵ID}_first` と `boss_{敵ID}_repeat`（最終ボス以外）から解決する。CSVに参照列を設けない。 |

`kind` ごとの必須欄（DAT-225）。

| kind | 必須欄 | 備考 |
| --- | --- | --- |
| town_exit | なし | |
| stairs, link | link_floor_id, link_cell, link_facing | 到着先との相互リンクが成立すること（MAP-125） |
| door | なし | |
| shortcut | unlock_from | 単位ベクトルであること（MAP-127） |
| chest | なし | `chest_rewards.csv` にちょうど1行あること |
| inscription | text_id | `data/texts.csv` に存在すること |
| boss | enemy_id | `is_boss` の敵であること |
| warp | warp_id, link_facing | `link_facing` は街から魔法陣へ到着したときの向き |

---

## 4. 可変状態モデル（DAT-5xx）

### 4.1 GameSession（DAT-500）

```text
session_id: String（ニューゲームごとに一意）
day: int = 1
gold: int
next_character_id: int = 1
characters: Array[CharacterState]
party_ids: Array[String]（順序が意味を持つ）
inventory: Array[ItemStackState]（装備はquantity=1、消耗品は1〜9）
important_items: Dictionary[String, int]
floors: Dictionary[String, FloorState]
quests: Dictionary[String, QuestState]
first_defeated_boss_ids: Array[String]
boss_last_defeated_day: Dictionary[String, int]
unlocked_warp_ids: Array[String]
cleared: bool
rng: encounter / battle / loot / creation の4系列
exploration: ExplorationState（街ではnull）
last_visited_floor_id: String（未訪問は空文字）
dirty: bool（保存対象外。立てる条件はFLW-304）
```

### 4.2 各状態（DAT-510〜DAT-514）

| ID | 型 | フィールド |
| --- | --- | --- |
| DAT-510 | CharacterState | id, name, job_id, portrait_id, level, total_exp, base_stats, current_hp, current_sp, poison:bool, equipment:{weapon, armor, accessory}（空欄は空文字）, learned_skill_ids, growth_rng |
| DAT-511 | FloorState | visited_cells:Array[Vector2i], known_wall_cells:Array[Vector2i], discovered_event_ids, opened_chest_ids, opened_door_ids（近道を含む）, visited:bool |
| DAT-512 | QuestState | id, status, kill_count。納品数は在庫から算出し、固定のカウンターを保存しない（QST-205） |
| DAT-513 | ExplorationState | floor_id, cell, facing, encounter_remaining, silent_steps_remaining, arrival_event_suppressed |
| DAT-514 | BattleSession | encounter_id, turn_index, actors, planned_actions, item_reservations, action_queue, log, result, reward_claimed。actorごとに hp/sp, poison, paralysis_remaining, sleep_remaining, guard, cover_target を持つ |
| DAT-515 | ItemStackState | item_id, quantity。装備はquantity=1、消耗品と素材は1〜max_stack |

| ID | 規則 |
| --- | --- |
| DAT-520 | `FloorState` のイベントIDは全体で一意であるため、重複を検査する（GLS-401）。 |
| DAT-521 | `ExplorationState` は戦闘中に探索位置を保持する。街へ戻る際に破棄する。保存しないことはSAV-203に従う。 |
| DAT-522 | `portrait_id` は `portrait_01` 〜 `portrait_10` とする。 |
| DAT-523 | 初期装備の防具は全職業で `cloth` とする。 |

---

## 5. バリデータ（DAT-9xx）

| ID | 規則 |
| --- | --- |
| DAT-900 | 起動時に必ず実行する。失敗した場合は開始不可のエラー画面を表示する（ARC-300）。 |
| DAT-901 | 各CSVの行数が `data/manifest.csv` の件数と一致することを検査する。`content_version` も `data/manifest.csv` から読む。 |
| DAT-902 | すべての参照先IDが存在することを検査する。 |
| DAT-903 | 料金が非負であること、HPが0より大きいこと、確率が0〜1であることを検査する。 |
| DAT-904 | 装備とスキルが職業に対応していることを検査する。 |
| DAT-905 | 各スキル・アイテム・敵行動の対象と使用場面の組み合わせが、下表に従っていることを検査する。素材は対象と使用場面をいずれも空とする。 |
| DAT-906 | 敵の行動参照、重みの合計、固定巡回の連番を検査する。 |
| DAT-907 | クエストの対象IDと報酬のIDを検査する。 |
| DAT-908 | 開発版では、問題のあるIDとファイル名をログへ出力する。 |
| DAT-909 | `data/texts.csv` について、IDの一意性と本文が空でないこと、コードが固定IDで参照する文章（各画面文書の「文言」節とDAT-230, 231の命名による文章）とARC-401の全コードの `error_*` が存在すること、波括弧の名前が `data/README.md` に定める名前に限られることを検査する。 |

対象と使用場面の組み合わせ（DAT-905）。

| target | 許される使用場面 |
| --- | --- |
| LIVING_ENEMY, ALL_LIVING_ENEMIES, OTHER_LIVING_ALLY, SELF | battle のみ |
| LIVING_ALLY, ALL_LIVING_ALLIES, DEAD_ALLY | battle、town、exploration の任意の組み合わせ |
| PARTY | town、exploration の任意の組み合わせ（battle を含まない） |

### 受け入れ条件

| ID | 前提・操作 | 合格条件 | 根拠 |
| --- | --- | --- | --- |
| D01 | データベースをロードする | 全CSVの件数が `data/manifest.csv` と一致し、すべての参照が有効である | DAT-901, 902 |
| D03 | 参照切れのID、負の料金、範囲外の確率、重み合計が100でない行動表、`manifest.csv` と一致しない件数、必須の文章IDの欠落を注入する | いずれもロードを失敗させ、問題のIDをログへ出力する | DAT-902, 903, 906, 908 |
