class_name GameSession
extends RefCounted
## 1回のゲームの可変状態（DAT-500）。ニューゲームとロードの単位で置き換える（ARC-202）。
## `GameFlow` が所有し、画面へ渡す。画面はコピーを持たず、このセッションを参照する（ARC-204）。
##
## 状態を変えるのはサービスで、操作が成功したあとに `notify_changed()` を呼ぶ。
## UIは `changed` を受けて表示を更新し、直接書き換えない（ARC-205）。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。

const Rules := preload("res://scripts/rules/inventory_rules.gd")
const Character := preload("res://scripts/models/character_state.gd")
const StackState := preload("res://scripts/models/inventory_state.gd")
const Rng := preload("res://scripts/services/rng_service.gd")

## `session_id` に使う乱数のバイト数。16進にすると、この2倍の文字数になる
const SESSION_ID_BYTES := 16

## 保存対象の状態が変わったときに送る。`kind` は何が変わったかの区別（空でもよい）。
## 失敗した操作では送らない（FLW-304）。
signal changed(kind: StringName)

## ニューゲームごとに一意
var session_id := ""
var day := 1
var gold := 0
## 次に冒険者へ割り当てる整数（GLS-403）
var next_character_id := 1
var characters: Array[Character] = []
## 冒険者のID。順序が意味を持つ（GLS-304）
var party_ids: Array[int] = []
## 装備は quantity=1、消耗品は1〜9（DAT-515）
var inventory: Array[StackState] = []
var important_items: Dictionary[String, int] = {}
## フロアID -> FloorState。FloorState は探索の実装で作る。空は未探索
var floors: Dictionary = {}
## クエストID -> QuestState。QuestState はクエストの実装で作る。空は未着手
var quests: Dictionary = {}
var first_defeated_boss_ids: Array[String] = []
var boss_last_defeated_day: Dictionary[String, int] = {}
var unlocked_warp_ids: Array[String] = []
var cleared := false
## encounter / battle / loot / creation の4系列（GLS-200）
var rng: Rng
## 探索中の状態。ExplorationState は探索の実装で作る。街では null（SAV-203）
var exploration: RefCounted = null
## 未訪問は空文字
var last_visited_floor_id := ""
## 未保存フラグ。保存対象外。立てる条件は FLW-304、解除は SAV-306
var dirty := false


## ニューゲームの初期状態を作る（TWN-001, TWN-002, TWN-003, TWN-004, TWN-005, TWN-006）。
## 初期の所持金と所持品は、`db`（`GameDatabase`）が `data/new_game.csv` から読んだ値を使う。
## 所持品の追加は `InventoryRules` の取引で行い、追加できない場合（容量の超過など）は何も作らず null を返す（INV-201）。
## 戻り値は `GameSession` か null。`class_name` の登録に頼らないため、戻り値の型は書かない。
## `rng_service` は乱数系列を持つ `RngService`。このセッションが保持する。作成で系列から値を引かない（GLS-203）。
static func create_new(db, rng_service):
	var session := new()
	session.session_id = _generate_session_id()
	session.gold = db.new_game_gold
	var plan: Dictionary = Rules.plan_transaction(db, session.inventory, db.new_game_items, [])
	if not Rules.apply(plan, session.inventory):
		push_error("Failed to grant the new game items (%s)" % plan.error_code)
		return null
	session.rng = rng_service
	return session


## 保存対象の状態が変わったことを知らせる。操作が成功したときにだけ呼ぶ（FLW-304）。
## 未保存フラグを立ててから、`changed` を送る。
func notify_changed(kind: StringName = &"") -> void:
	dirty = true
	changed.emit(kind)


## ゲームの乱数系列とは別の乱数で作る。系列を消費しない（GLS-203）。
static func _generate_session_id() -> String:
	return Crypto.new().generate_random_bytes(SESSION_ID_BYTES).hex_encode()
