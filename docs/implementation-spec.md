# 技術設計・検証条件

初回版の実装契約とする。コード・Godotシーン・実行ファイルを納品した文書ではない。

## 1. 技術基盤

- Godot **4.5.1 Standard**、GDScript、同バージョンのExport Templatesに固定する。最新版という意味ではなく、確認できた安定版とAPIを基準に再現性を持たせる選択。
- Windows Desktop x86_64、Compatibilityレンダラー、EXEと外部PCKで配布。外部のゲーム用ライブラリは必須にしない。
- エントリーシーンは`res://scenes/main.tscn`。ゲームロジックは3DノードやUIから分離し、ヘッドレスでも検証可能にする。
- 制作上「TileMap」と呼んでいた地図には、Godot 4.5の`TileMapLayer`を使う。独自GDScriptで2Dセル情報を3Dへ変換する。

公式根拠：

- [Godot 4.5.1配布アーカイブ](https://godotengine.org/download/archive/4.5.1-stable/)
- [TileMapLayer API](https://docs.godotengine.org/en/4.5/classes/class_tilemaplayer.html)
- [TileSetのcustom data](https://docs.godotengine.org/en/4.5/tutorials/2d/using_tilesets.html#assigning-custom-metadata-to-the-tileset-s-tiles)
- [ResourceSaver](https://docs.godotengine.org/en/4.5/classes/class_resourcesaver.html)
- [Saving games](https://docs.godotengine.org/en/4.5/tutorials/io/saving_games.html)
- [RandomNumberGenerator](https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html)
- [JSON](https://docs.godotengine.org/en/4.5/classes/class_json.html)
- [Windows export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_windows.html)

以下の構成や数値は公式仕様ではなく、本ゲームで承認された設計上の選択である。

## 2. ディレクトリとシーン構成

```text
project.godot
export_presets.cfg
scenes/
  main.tscn
  ui/{title,town,guild,temple,shop,inn,tavern,menu,save_slots}.tscn
  ui/{battle,reward,game_over,ending,confirm_dialog}.tscn
  dungeon/{dungeon_view,minimap}.tscn
  floors/{ruins_f1,ruins_f2,ruins_f3,depths_f1,depths_f2,depths_f3}.tscn
scripts/
  core/{game_flow,game_session,game_database,game_validator}.gd
  models/{character_state,inventory_state,quest_state,floor_state}.gd
  services/{save_service,rng_service,facility_service,quest_service}.gd
  rules/{battle_rules,battle_session,growth_rules,inventory_rules,exploration_rules}.gd
  dungeon/{floor_authoring,floor_compiler,dungeon_builder,dungeon_controller}.gd
  ui/（各画面のpresenter）
  definitions/（下記Resource型）
data/
  database.tres
  jobs/ skills/ equipment/ items/ enemies/ enemy_actions/ quests/ floors/
assets/
  portraits/ enemies/ backgrounds/ tiles/ audio/ fonts/
tests/
  run_all.gd
  test_growth.gd test_battle.gd test_inventory.gd test_save.gd test_maps.gd
docs/
  game-design.md gameplay-spec.md content-spec.md implementation-spec.md
  map-authoring.md（実装完了時に実画面と操作手順を追記）
THIRD_PARTY_NOTICES.md
README.md
```

`main.tscn`のルートはNode。GameFlow、ScreenHost(Control)、DungeonHost(Node3D)、ModalHost(CanvasLayer)、AudioHostを子に持つ。AutoloadはGameDatabaseとSaveServiceに限定する。GameSessionはニューゲーム・ロード単位で置換するRefCounted、GameFlowが所有し画面へ渡す。TITLEへ戻ったら旧セッションを破棄する。

画面は状態のコピーを勝手に保持して保存せず、セッションを参照してサービスにコマンドを送る。UIは更新通知を受けて表示する。移動中・行動解決中など入力できない状態をGameFlowとBattleSessionで明示する。

| 責務 | 公開操作・結果 |
| --- | --- |
| GameDatabase | `load_and_validate()`、ID→読み取り専用定義。失敗は開始不可のエラー画面 |
| GameFlow | `new_game()`、`load_slot(n)`、`go_town()`、`enter_floor(id,cell,facing)`、`start_battle(encounter)`、`return_title()` |
| FacilityService | 登録・削除・編成・訓練・宿泊・治療・救済・購入・売却。条件確認と更新を1操作で行う |
| InventoryRules | 追加・削除・交換の差分を試算し、成功時だけ適用。報酬トランザクションに利用 |
| QuestService | 解禁条件評価、受注、勝利カウント、報告の試算と確定 |
| ExplorationRules | 通行判定、成功歩の処理、踏破記録、遭遇残数、イベント発火。描画を持たない |
| BattleSession | 入力予約、実行確定、ターン解決、戦闘結果を生成。実行確定後の入力を拒否 |
| BattleRules | 命中・ダメージ・異常・順序・逃走・終了判定。乱数を引数で受け取る |
| GrowthRules | 経験値配分、レベル判定、個別成長乱数、成長ログ |
| FloorCompiler | TileMapLayerとイベントResourceを読み、FloorGridへ変換・検証 |
| DungeonBuilder | FloorGridと永続状態からMeshInstance3D等を生成。セッションを変更しない |
| SaveService | DTO化・検証・ファイル書込み・スロット一覧・復元。UIを持たない |

サービス結果は`{ok: bool, error_code: StringName, changes: Dictionary}`。代表エラーはNO_GOLD、NO_SPACE、INVALID_TARGET、PARTY_EMPTY、NO_LIVING_MEMBER、ALREADY_LEARNED、LOCKED、INVALID_SAVE。UI側で日本語へ翻訳し、失敗時に副作用を残さない。

## 3. 固定データの契約

Godotの`class_name`付きResource型と`.tres`を使う。全IDは一意なStringName。Resourceは固定定義として扱い、戦闘HPや開封状態をResource自体へ書き込まない。可変値はRefCountedの状態モデルに置く。

### 3.1 共通型

| 型 | 必須フィールド |
| --- | --- |
| StatBlock | hp, sp, str, vit, tec, agi, luc : int |
| StatChance | hp, sp, str, vit, tec, agi, luc : float（0〜1） |
| ItemStackDef | item_id : StringName, quantity : int（1以上） |
| RewardDef | exp : int, gold : int, items : Array[ItemStackDef] |
| RngSnapshot | seed_decimal : String, state_decimal : String |
| ActionEffect | kind : enum、damage_model、element、power:int、multiplier:float、defense_ratio:float、status_id、status_chance:float、restore_ratio:float、restore_flat:int、duration_steps:int |

ActionEffectのkindはDAMAGE、HEAL、RESTORE_SP、REVIVE、CURE_POISON、APPLY_STATUS、COVER、SUPPRESS_ENCOUNTERS、RETURN_TOWN、NO_OP。damage_modelはPHYSICAL/MAGICAL/NONE。elementはphysical/fire/ice/lightning/none。使わない数値は0、倍率の既定値は1。`requires_previous_hit:bool`を追加フィールドとして持ち（既定false）、効果を配列順に適用し、毒刃等の2つ目の効果はtrueにして直前命中に依存させる。ダメージ不成立・対象死亡後に異常は付与しない。duration_stepsは探索効果用、戦闘状態異常の期間はgameplay-specの共通規則を使う。

### 3.2 定義Resource

| 型 | フィールド |
| --- | --- |
| JobDef | id, name, base_stats:StatBlock, growth_fixed:StatBlock, growth_extra_chance:StatChance, starting_weapon_id, starting_armor_id, initial_skill_id, learnable_skill_ids:Array[StringName], weapon_categories:Array[StringName], armor_ids:Array[StringName] |
| SkillDef | id, name, job_id, required_level:int, learn_cost:int, sp_cost:int, target:enum, contexts:Array[StringName], priority:int, always_hit:bool, effects:Array[ActionEffect] |
| EquipmentDef | id, name, slot:weapon/armor/accessory, category, allowed_jobs:Array[StringName], attack:int, defense:int, stat_bonus:StatBlock, buy_price:int, sell_price:int, shop_tier:A/B/C, icon:Texture2D |
| ItemDef | id, name, kind:consumable/material, max_stack:int=9, buy_price:int（-1なら非売品）, sell_price:int, shop_tier, target, contexts, effects:Array[ActionEffect], icon |
| EnemyDef | id, name, hp:int, attack:int, defense:int, tec:int, agi:int, luc:int, element_multipliers:Dictionary, status_multipliers:Dictionary, exp:int, gold:int, drop_item_id, drop_chance:float, action_weights:Array[WeightedAction], action_cycle:Array[StringName], portrait:Texture2D, is_boss:bool |
| EnemyActionDef | id, name, target, priority:int, always_hit:bool, effects:Array[ActionEffect]。消費SPなし |
| WeightedAction | action_id:StringName, weight:int>0 |
| QuestDef | id, title, description, unlock:ConditionDef, kind:kill/deliver, target_id, target_count:int, reward:RewardDef |
| ConditionDef | kind:always/floor_visited/boss_first_defeated/warp_unlocked、target_id |
| EncounterDef | enemy_ids:Array[StringName]、weight:int。初回版の各フロアは3件すべてweight=1 |
| FloorDef | id, display_name, authoring_scene:PackedScene, encounters:Array[EncounterDef], events:Array[CellEventDef], default_spawn:Vector2i, default_facing:int |
| CellEventDef | id, cell:Vector2i, kind、link_floor_id、link_cell:Vector2i、link_facing:int、reward:RewardDef、enemy_id、unlock_from:Vector2i、warp_id、text:String。kindごとに必要欄を検証 |

targetはSELF、LIVING_ALLY、DEAD_ALLY、OTHER_LIVING_ALLY、ALL_LIVING_ALLIES、LIVING_ENEMY、ALL_LIVING_ENEMIES、PARTY。contextsはtown/exploration/battle。通常攻撃・防御は固定コマンドとしてBattleRulesが保持する。

stat_bonusのhp/spは最大値への加算。growth_fixedには装備補正を入れない。敵・味方共通の計算入力はBattleActorに正規化し、両者で別の計算式を作らない。

priorityは防御・かばう100、その他0。初期スキルのlearn_costは0、購入不可扱いではなく作成時から習得済みとして重複を防ぐ。HP/SP等のStatBlockにおける装備加算値は未指定なら0。初期装備は全員cloth、portrait_idはportrait_01〜portrait_10。

確率の乱数は常に判定箇所でのみ引き、対象の列挙順は味方パーティ順・敵出現順。battle系列は敵行動選択→敵単体対象→味方速度→敵速度→実行順の行動不能・命中・ダメージ倍率・異常判定の順。命中しなければダメージ倍率や付随異常の乱数は引かない。敵固定巡回は選択乱数を引かない。loot系列は勝利時に敵出現順で抽選し、ドロップ100%は抽選なしで確定。growth系列は各レベルにつきHP,SP,STR,VIT,TEC,AGI,LUCの順。encounter系列は残り歩数と出現編成の抽選だけに使う。

バリデータは表の件数、参照先ID、非負料金、職業対応、HP>0、確率0〜1、各スキルの対象と使用場面、敵の行動参照、クエスト対象、報酬のIDを検査する。常に起動時に実行し、開発版は問題IDとファイルをログ出力する。

## 4. TileMapLayerの編集規約と3D化

### 4.1 編集用シーン

各`scenes/floors/*.tscn`は`FloorAuthoring(Node2D)`をルートにし、`Terrain(TileMapLayer)`を1枚置く。2Dタイルは32×32px、共通TileSetを参照する。座標0〜29の900セルを明示的に埋める。空セル、外周の通行セル、範囲外セルは検証エラーとする。

TileSetのcustom dataには`tile_kind:String`だけを置く。タイル種別から通行性を決定する。custom dataはタイル定義で共有されるので、宝箱IDや階段の接続先を入れてはいけない。

| tile_kind | 通行と表示 | 個別イベント |
| --- | --- | --- |
| wall | 不可、壁立方体 | なし |
| floor | 可、床 | なし |
| door | 開くまで不可、扉 | door |
| shortcut | 開通まで不可、扉、指定側から初回開通 | shortcut |
| chest | 不可、床＋宝箱 | chest |
| inscription | 不可、床＋石碑 | inscription |
| stairs_up / stairs_down | 可、床＋階段の図形 | stairs |
| town_exit | 可、床＋出口表示 | town_exit |
| link | 可、床＋接続通路表示 | link |
| warp | 可、床上の魔法陣 | warp |
| boss | 可、床上の敵シンボル。侵入で戦闘 | boss |

個別イベントはFloorDefのevents配列にCellEventDefとして登録する。床1セルにつきイベント1個。地形上の特殊タイルとイベント種別を対応させる。タイルを移動したらeventsのcellも更新する。専用エディタプラグインは必須にせず、標準のタイルペイントとResourceインスペクターで編集する。

階段・linkには移動先floor_id/cell/facingを登録する。到着先は通行可能で、相互リンクが成立しなければ検証エラー。town_exitは街、warpは全体IDwarp_depths、bossは敵IDを指定する。shortcutのunlock_fromはセルから見た許可側の差分（南ならVector2i(0,1)）。宝箱のrewardに経験値は設定しない。

### 4.2 コンパイルと検証

`get_used_cells()`、`get_cell_tile_data(cell)`、`TileData.get_custom_data("tile_kind")`で読み取る。走査順はy昇順→x昇順に固定。コンパイル結果FloorGridは30×30のセル配列と座標→イベント辞書であり、3D生成と移動とミニマップが同じ結果を参照する。

検査項目：900セル、ID重複なし、タイル種別、イベント座標・種別一致、出入口の相互対応、ボス/魔法陣配置、宝箱に有効報酬、出現表参照、未開の近道を通らず開始からボスへ到達可能、通常扉を開ける前提で階段へ到達可能。第1ボス未撃破状態で第2ダンジョンへ行く迂回路がないことも全体グラフで検証する。

制作時はペイント→イベント設定→検証スクリプト実行→ゲーム再起動で確認。ホットリロードと実行中のマップ変更は初回版では扱わない。

### 4.3 3D生成

- セル寸法2m、壁高3m。セル(x,y)の中心を`Vector3(2*x,0,2*y)`とする。北は-Z、東+X。カメラは中心から高さ1.5m、FOV70度、near0.05、far60m。
- floor等の通行セルには2m四方の床メッシュ、wallには2×3×2mのBoxMeshを置く。扉・宝箱・石碑・魔法陣・階段は簡単なプリミティブで識別できる表示にする。天井は初回版では設けず背景を暗色にする。
- 扉を開けたら扉メッシュを非表示にし、床は残す。宝箱は開封色へ変える。ボスシンボルは生存状態でのみ表示。マップ再読込時も状態から再構築する。
- カメラはNode3Dの子。移動の正否はFloorGridで判定し、物理エンジンによる滑り・押し戻しを移動仕様に使わない。CollisionShapeは必須ではない。
- 現在フロアだけ生成し、移動時に旧フロアを解放する。Mesh/Materialは共通資源を共有。900セル規模ではまず単純なMeshInstance3Dで実装し、計測なしで複雑な最適化を導入しない。
- 光源はAmbientとDirectionalLight3D、リアルタイム影なし。壁・床はダンジョンごとの2組のMaterialを参照し、差し替え可能にする。

## 5. 可変状態モデル

### GameSession

```text
session_id: String（ニューゲームごとに一意）
day: int = 1
gold: int
next_character_id: int = 1
characters: Array[CharacterState]
party_ids: Array[String]（順序が意味を持つ）
inventory: Array[ItemStackState]（装備quantity=1、消耗品1〜9）
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
dirty: bool（保存対象外）
```

CharacterState：id、name、job_id、portrait_id、level、total_exp、base_stats、current_hp、current_sp、poison:bool、equipment:{weapon,armor,accessory}（空欄は空文字）、learned_skill_ids、growth_rng。

FloorState：visited_cells:Array[Vector2i]、known_wall_cells:Array[Vector2i]、discovered_event_ids、opened_chest_ids、opened_door_ids（近道含む）、visited:bool。イベント状態のIDは全体で一意なので検査する。

QuestState：id、status、kill_count。納品数は在庫から計算し固定カウンターを保存しない。

ExplorationState：floor_id、cell、facing、encounter_remaining、silent_steps_remaining、arrival_event_suppressed。戦闘時に探索位置を保持する。街に戻る際は破棄する。街でしかセーブしないためファイルには保存しない。

BattleSession：encounter_id、turn_index、actors、planned_actions、item_reservations、action_queue、log、result、reward_claimed。actorごとにhp/sp、poison/paralysis_remaining/sleep_remaining、guard、cover_targetを持つ。味方HP/SPは戦闘解決時にCharacterStateへ反映する。戦闘中断・全滅時はセッションを破棄するので保存されない。

味方の永久値と戦闘コピーは二重に直接書き換えない。行動結果をBattleSessionへ適用し、戦闘終了時に生存・死亡・毒・HP/SPを一度同期する。報酬の経験値計算は同期後に実行する。

## 6. セーブ形式と障害対応

### 6.1 ファイル

`user://saves/slot_01.json`〜`slot_05.json`。同フォルダーに`.tmp`と`.bak`を一時・バックアップ用として使う。設定は`user://settings.cfg`に別保存。書込み先を`res://`にしない。

JSON外枠：

```json
{
  "schema_version": 1,
  "content_version": "0.1.0",
  "engine_version": "4.5.1",
  "saved_at_utc": "ISO-8601 UTC",
  "scene": "town",
  "session": {}
}
```

sessionは上記GameSessionの永続フィールド全部。Vector2iは`[x,y]`、StringNameは文字列、Resource参照はIDにする。HP0を死亡の唯一の根拠とし、別のdead boolは保存しない。JSONの整数は読込時に整数値・範囲を検証する。

乱数のseed/stateは64bit精度喪失を避け、数値でなく**10進文字列**として保存。復元はseedを先に設定し、その後stateを設定する。stateはRNGから取得した値のみ保存する。ニューゲーム時に各系列を初期化し、冒険者作成時はcreation系列からseedを引いて個人のgrowth_rngを作る。UIの開閉・一覧ソート・セーブは乱数を引かない。

保存時刻はスロットの表示だけに使い、30日の復活判定に使わない。スロット表示用の別マニフェストは作らず本体から読む。

### 6.2 保存手順

1. TOWNでモーダル取引・戦闘・探索がないことを検証。上書き確認後に状態を不変DTOへコピーする。
2. DTO検証→`.tmp`へJSON書込み→flush/close→読戻しパース・検証。
3. 既存本体がある場合は有効性を確認して`.bak`へ退避する（既存バックアップ置換の各エラーを検査）。無効本体の上書きをユーザーが選んだ場合、無効データで有効バックアップを置き換えない。
4. `.tmp`を本体へrenameする。失敗時はバックアップから本体への復元を試み、失敗内容を表示する。メモリ上の進行は保持し、dirtyは立ったまま。
5. 書込みと置換が成功した場合だけ「保存しました」を表示しdirtyを解除する。初回保存失敗でバックアップがなくても、再試行できるメモリ上の進行を保持する。

OS/ファイルシステムのすべての障害で完全な原子性を保証したと表現しない。各段階の失敗をテストし、有効な旧データまたはバックアップから復帰可能にする。

### 6.3 読込

本体をパース・検証してから新しいGameSessionを組み立て、完全成功後だけ現在セッションと置換する。書式不正、未知ID、参照切れ、重複キャラ、無効なパーティ、level/exp不一致、範囲外座標、HP/SP不正、日数不正は拒否する。schema_version/content_versionが異なる場合は互換性なしを表示し、自動変換しない。

本体が欠落・破損し、同スロットの`.bak`が有効なら「バックアップから再開可能」を表示してユーザーに選ばせる。自動で別スロットを読み込まない。`.tmp`を自動ロードしない。有効なデータがないスロットは「空」または「読込不可」で区別する。ロード失敗時もファイルを削除しない。

ロード後は街の通常画面。マップ・クエスト・冒険者・魔法陣・ボス撃破日・乱数をすべて復元する。起動時に現実の経過時間で日数を加算しない。

初回版で開発中にIDや数値テーブルを破壊的変更する場合はcontent_versionを更新する。仮マップ地形の変更も座標の意味が変わるため同様に扱い、旧セーブ互換を暗黙に保証しない。

## 7. UI・入力・音・表示

基準解像度1280×720、最小960×540。ウィンドウ/フルスクリーン切替。UIはアンカーとContainerで画面内に収め、文字を画像へ焼き込まない。日本語標準文字サイズは基準24px、注記20px。拡大で文字が切れないことを確認する。

| 操作 | キー・マウス |
| --- | --- |
| 前進 / 後退 | W / S |
| 左平行 / 右平行 | A / D |
| 左旋回 / 右旋回 | Q / E |
| 調べる | F、画面の「調べる」ボタン |
| 決定 / キャンセル | Enter / Esc、左クリック / 画面の戻るボタン |
| メニュー | Esc（探索中）、メニューボタン |
| 地図 | M（探索中）、メニュー内地図 |
| UI項目移動 | 矢印キー、Tab / Shift+Tab |
| 全画面切替 | F11、設定画面 |

入力リマップは初回版には含めない。探索にも前後左右・旋回の小ボタンを用意し、マウスだけでも主要操作が可能。マウスの移動は視点に影響しない。確認ダイアログの初期選択は取消。ゲームパッドは対象外。

探索画面：左〜中央に3D視界、右上240×240pxにミニマップ、上部に階層名と危険度、下部にパーティ4枠（顔・名前・HP/SP・死亡/毒）、右下に操作ボタン。0〜3人編成時は空き枠を明示する。

戦闘画面：中央上に敵最大3体の画像・名称・HPバー、下部にパーティとコマンド、最上部に直近の行動ログ。敵の数値HPは非表示、弱点は初回版では戦闘中の敵詳細から表示可。攻撃対象を画像またはリストで選択する。色だけで状態を区別せず文字・アイコンを併記する。

施設は共通の見出し・所持金・一覧・詳細・戻るを使う。購入・習得・宿泊・治療で変更される項目と費用を確定前に表示。装備比較はATK/DEF/能力差を表示する。

設定はマスター音量0〜100（初期70）、フルスクリーンON/OFF（初期OFF）。設定保存は即時で、5つのゲームスロットと共有。ボタンにはフォーカス表示を付け、長い一覧はスクロール可能にする。

演出は移動0.15秒・旋回0.12秒、戦闘1行動0.3秒の短い表示を基準にする。報酬・会話は決定入力で進む。演出速度が判定乱数や処理結果に影響しないよう、計算結果と表示イベント列を分ける。

## 8. 実装順序と引き渡し成果物

1. 定義Resourceと全データ、バリデータ、GameSessionモデルを作成し、ID参照・数値を検証する。
2. タイトル→ニューゲーム→ギルド登録→街→保存→タイトル→ロードまで通す。
3. 所持品、装備、商店、宿屋、教会、救済、訓練を実装し、取引失敗時の不変性を検証する。
4. 6フロアのTileMapLayerとFloorCompiler/Builderを実装し、移動・ミニマップ・階段・魔法陣・近道を通す。
5. 通常戦のコマンド・数式・異常・逃走・勝利・全滅・成長・報酬を実装する。
6. ボス、30日復活、クエスト、エンディングを結合する。
7. 仮素材・日本語UI・音を整え、Windowsエクスポートと開始からクリアまでの手動試験を行う。

各工程で新しい依存先を勝手に追加せず、以下の受け入れ条件を進める。納品物はGodotプロジェクト一式、6フロアの編集可能シーン、全データ、Windows EXE/PCK、起動・操作・マップ編集説明、テスト結果、ライセンス一覧。プロジェクト内で秘密情報や絶対ローカルパスに依存しない。

## 9. 受け入れ条件

ルールの境界はヘッドレスのGDScriptテストで確認し、描画・入力・配布はWindows実機で確認する。`godot --headless --path . --script tests/run_all.gd`をテスト入口にする。テスト用seed・固定ダメージ倍率・模擬保存障害はテスト用注入点から与え、本番にチートUIは設けない。

### 自動検証

| ID | 前提・操作 | 合格条件 |
| --- | --- | --- |
| D01 | データベースをロード | 5職、25スキル、21装備、9アイテム、14敵、6クエスト、6フロア。全参照有効 |
| D02 | 6マップをコンパイル | 各900セル、範囲内、階段相互接続、ボス迂回不可、魔法陣は第2の1Fのみ |
| G01 | 20人登録後に21人目を試す | 失敗、所持金・装備・ID状態を変更しない |
| G02 | 全職を1人ずつ作る | 正しい武器・布の服・初期スキル・初期能力。装備は所持品枠外 |
| G03 | 所持金不足の訓練・購入、枠不足の削除 | どのデータも部分更新しない |
| I01 | 同消耗品8個へ3個追加 | 9個＋2個の2枠になる |
| I02 | 30枠で装備交換・取り外し | 差分で収まる交換は可、31枠になる取り外しは不可 |
| I03 | 満杯で宝箱・クエスト報告 | 開封/完了/料金/納品/EXPを進めない。整理後に一度だけ取得可 |
| I04 | 2個の薬草を味方3人で予約 | 3人目の予約不可、キャンセルで枠が戻る |
| E01 | 壁衝突・旋回・横移動を行う | 衝突/旋回は0歩、成功横移動は1歩。座標と見た目が一致 |
| E02 | HP1の毒キャラで1歩歩く | HP1のまま、ゲームオーバーなし |
| E03 | 遭遇残り1で階段へ入る | 階段イベント優先、ランダム戦なし、残り1を維持 |
| E04 | 未起動魔法陣で拒否→再訪→起動 | 拒否中は街から選択不可。起動後は選択可。到着直後に帰還ループなし |
| E05 | 忍び足20で通常床を21歩移動 | 最初の20歩は遭遇減少なし、21歩目から通常。毒は毎歩処理 |
| B01 | content-specの紙上例を固定倍率1.0で計算 | 27、40、55、40、18など表の値と一致 |
| B02 | 攻撃対象が先行行動で死亡 | 別の生存敵へ再照準。無効な回復は消費せず不発 |
| B03 | 毒と直接攻撃で睡眠を解除判定 | 毒は起こさない、直接ダメージは起こす |
| B04 | 両陣営の最後の1人がターン末毒で死亡 | GAME_OVER、報酬なし |
| B05 | 行動途中に最後の敵を倒す | 即勝利、ターン末毒なし、報酬二重受領なし |
| B06 | 通常逃走成功・失敗・ボス逃走 | 成功は報酬/討伐加算なし、失敗は敵のみ行動、ボス不可 |
| B07 | かばう対象へ単体/全体攻撃 | 単体のみ騎士に移る、全体には作用しない、連鎖しない |
| L01 | EXP60・480・7980の境界 | Lv2・5・20。複数成長を順に処理、上限超過分破棄 |
| L02 | 成長前保存→成長→ロード→同じ成長 | 基礎能力の結果一致、装備着脱で成長を再抽選しない |
| L03 | 死亡・待機・上限者を含む報酬配分 | 生存参加者で均等、死亡/待機へなし、上限者分は再配分なし |
| F01 | 全員満タンで有料宿泊 | 通常料金を払い1日進む。救済は利用不可 |
| F02 | 救済料金Cの境界、所持金C-1/C | C-1は利用可、Cは不可、救済では日数不変 |
| F03 | 3日目に門番撃破後、32日/33日 | 32日目は不在、33日目は復活。魔法陣・初回フラグ維持 |
| F04 | 再撃破・宝箱・クエスト | ボス報酬は再取得可、宝箱/クエストは再取得不可 |
| S01 | 5スロットへ異なる進行を保存 | 独立してロードでき、名前・日数・探索・乱数まで復元 |
| S02 | JSON切断、未知ID、旧version | 拒否してファイルを保持、有効bakがあれば選択可 |
| S03 | tmp書込み/退避/renameに失敗を注入 | 保存成功を表示しない、メモリ進行と復元可能な旧データを保持 |
| S04 | 全滅・終了・ニューゲーム | 自動保存なし。既存5スロットを変更しない |

### Windows実機・手動検証

| ID | 合格条件 |
| --- | --- |
| W01 | Windows 11上でEXEから起動し、エディターなしで日本語フォント・素材・音が表示される |
| W02 | キーボードだけ、マウスだけで登録・施設・出発・戦闘・保存・ロードが完結する |
| W03 | 1280×720、960×540、フルスクリーンで文字・ダイアログ・4人表示・敵3体が切れない |
| W04 | 横移動、旋回、壁衝突、階段、魔法陣到着で視点がずれず、操作の二重受付がない |
| W05 | 通常の4人パーティで新規開始から第1ボス・魔法陣・最終ボス・エンディング・クリア後セーブまで到達できる |
| W06 | 少人数出発・死亡者を含む編成・帰還アイテム・救済・所持品満杯・全滅が仕様どおり |
| W07 | ユーザー用手順に従ってTileMapを1か所編集し、再起動後に3D・衝突・地図が同じ形に変わる |
| W08 | タイトル復帰や閉じる操作の未保存確認、破損スロット表示、バックアップ復旧表示が理解できる日本語 |

通常プレイのバランス試験では編成・遭遇数・帰還回数・各フロア到達Lv・ボス戦ターン数・購入履歴を記録する。自動テストに合格しても面白さが確認済みとはしない。試験結果と既知の問題をREADMEへ記載して引き渡す。