class_name GameValidator
extends RefCounted
## 固定データの値と組み合わせの検査（DAT-900, DAT-903, DAT-904, DAT-905, DAT-906, DAT-907, DAT-908, DAT-909, DAT-225）。
##
## `GameDatabase.load_and_validate()` が、定義の構築と参照の検査（DAT-901, DAT-902）のあとに呼ぶ。
## 問題を見つけても止めず、すべて集めて返す。ログへ出すのは呼び出し側で、問題1件ごとに
## ファイル名とIDを含める（DAT-908）。
##
## この検査は、データを書き換えない。重複した文章IDは、定義を作る時点で `GameDatabase` が検出する（DAT-909）。

## DAT-906, `data/README.md`: 重み付きの行動表の、敵ごとの重みの合計
const WEIGHT_TOTAL := 100

## DAT-909, `data/README.md`: `texts.csv` の波括弧に使える名前
const PARAMETER_NAMES: Array[String] = ["gold", "name", "level", "skill", "min", "max"]

## ARC-401: エラーコード。`texts.csv` に `error_` + 小文字のIDで表示文が要る（ARC-402, DAT-909）
const ERROR_CODES: Array[String] = [
	"NO_GOLD", "NO_SPACE", "INVALID_TARGET", "PARTY_EMPTY", "PARTY_FULL", "ROSTER_FULL", "INVALID_NAME",
	"NO_LIVING_MEMBER", "ALREADY_LEARNED", "LOCKED", "INVALID_SAVE",
]

## DAT-909: コードが固定IDで参照する文章。画面文書（`docs/spec/screens/`）の「文言」節ごとに並べる。
## 画面文書が新しい文章を挙げたら、ここへ足す。
##
## 載せないもの（検査の対象外）:
## - `quest_{クエストID}`（DAT-230）は、段階Gで本文を `texts.csv` に追加するまで検査しない。
##   追加したら、すべてのクエストについて存在を検査する形に改める。
## - `error_*` は `ERROR_CODES` から作る。ボスの `boss_{敵ID}_pre` は敵の表から作る（DAT-231）。
const REQUIRED_TEXTS := {
	"text_screen.md": ["intro", "game_over", "ending", "clear_notice"],
	"town.md": ["town_need_register", "unsaved_warning"],
	"menu.md": ["unsaved_warning"],
	"exploration.md": [
		"insc_ruins_f1", "insc_ruins_f2", "insc_ruins_f3", "insc_depths_f1", "insc_depths_f2", "insc_depths_f3",
		"boss_gatekeeper_pre", "boss_labyrinth_lord_pre", "boss_gatekeeper_first", "boss_gatekeeper_repeat",
	],
	"guild.md": ["guild_register_confirm", "guild_delete_confirm", "guild_train_confirm"],
	"inn.md": ["rescue_confirm"],
	"temple.md": ["rescue_confirm"],
	"save_slots.md": [
		"save_slot_empty", "save_slot_unreadable", "save_backup_available", "save_incompatible", "save_done",
		"save_failed",
	],
	"boot_error.md": ["boot_error"],
}

## DAT-905: 対象が戦闘だけで使えるもの。それ以外のうち PARTY は戦闘で使えない
const BATTLE_ONLY_TARGETS: Array[StringName] = [
	&"LIVING_ENEMY", &"ALL_LIVING_ENEMIES", &"OTHER_LIVING_ALLY", &"SELF",
]
const PARTY_TARGET := &"PARTY"
const BATTLE_CONTEXT := &"battle"

## 向き。北0・東1・南2・西3（`data/README.md`）
const FACING_MIN := 0
const FACING_MAX := 3

## DAT-225: セルイベントの kind ごとの必須欄。表にない欄は空でなければならない
const EVENT_REQUIRED := {
	&"town_exit": [],
	&"stairs": ["link_floor_id", "link_cell", "link_facing"],
	&"link": ["link_floor_id", "link_cell", "link_facing"],
	&"door": [],
	&"shortcut": ["unlock_from"],
	&"chest": [],
	&"inscription": ["text_id"],
	&"boss": ["enemy_id"],
	&"warp": ["warp_id", "link_facing"],
}
## DAT-225: 空かどうかを見る欄。報酬（`reward`）は `chest_rewards.csv` の行数で見る
const EVENT_FIELDS: Array[String] = [
	"link_floor_id", "link_cell", "link_facing", "unlock_from", "enemy_id", "warp_id", "text_id",
]

## `GameDatabase`（Autoload）。`class_name` を持たないため、型を付けずに受け取る
var _db
## CSVの表。ファイル名 → 行の配列
var _tables: Dictionary = {}
## 見つけた問題。{file, id, message}
var _problems: Array[Dictionary] = []


## 読み込み済みの `db` と、CSVの表 `tables`（ファイル名 → {列名: 値} の配列）を検査し、問題を返す。
## 問題がなければ空。読込に失敗した表があっても、空の表として扱い、検査を続ける。
static func validate(db, tables: Dictionary) -> Array[Dictionary]:
	var validator := GameValidator.new()
	validator._db = db
	validator._tables = tables
	validator._check_ranges()
	validator._check_job_correspondence()
	validator._check_target_contexts()
	validator._check_enemy_actions()
	validator._check_quests()
	validator._check_cell_events()
	validator._check_texts()
	return validator._problems


func _add(file: String, id: Variant, rule: String, message: String) -> void:
	_problems.append({"file": file, "id": String(id), "message": "%s: %s" % [rule, message]})


func _rows(file: String) -> Array:
	return _tables.get(file, [])


## `floor_events.csv` の行に対応するセルイベント。フロアが不明な行も含める
func _events() -> Array[CellEventDef]:
	var events: Array[CellEventDef] = []
	var seen := {}
	for row: Dictionary in _rows("floor_events.csv"):
		var event: CellEventDef = _db.cell_event(StringName(row["event_id"]))
		if event != null and not seen.has(event.id):
			seen[event.id] = true
			events.append(event)
	return events


# --- 値域（DAT-903） -----------------------------------------------------------

func _check_ranges() -> void:
	const RULE := "DAT-903"
	for equipment_def: EquipmentDef in _db.equipment_list():
		_check_fee("equipment.csv", equipment_def.id, "buy_price", equipment_def.buy_price)
		_check_fee("equipment.csv", equipment_def.id, "sell_price", equipment_def.sell_price)
	for item_def: ItemDef in _db.items():
		if item_def.buy_price != ItemDef.NOT_FOR_SALE:
			_check_fee("items.csv", item_def.id, "buy_price", item_def.buy_price)
		_check_fee("items.csv", item_def.id, "sell_price", item_def.sell_price)
		_check_effect_chances("item_effects.csv", item_def.id, item_def.effects)
	for skill_def: SkillDef in _db.skills():
		_check_fee("skills.csv", skill_def.id, "learn_cost", skill_def.learn_cost)
		_check_effect_chances("skill_effects.csv", skill_def.id, skill_def.effects)
	for action_def: EnemyActionDef in _db.enemy_actions():
		_check_effect_chances("enemy_action_effects.csv", action_def.id, action_def.effects)
	for enemy_def: EnemyDef in _db.enemies():
		if enemy_def.hp <= 0:
			_add("enemies.csv", enemy_def.id, RULE, "hp が0以下です: %d" % enemy_def.hp)
		_check_fee("enemies.csv", enemy_def.id, "gold", enemy_def.gold)
		_check_probability("enemies.csv", enemy_def.id, "drop_chance", enemy_def.drop_chance)
	for job_def: JobDef in _db.jobs():
		if job_def.base_stats.hp <= 0:
			_add("jobs.csv", job_def.id, RULE, "base_hp が0以下です: %d" % job_def.base_stats.hp)
		for stat in ["hp", "sp", "str", "vit", "tec", "agi", "luc"]:
			_check_probability("jobs.csv", job_def.id, "chance_" + stat, job_def.growth_extra_chance.get(stat))
	for quest_def: QuestDef in _db.quests():
		_check_fee("quests.csv", quest_def.id, "reward_gold", quest_def.reward.gold)
	for event in _events():
		if event.reward != null:
			_check_fee("chest_rewards.csv", event.id, "gold", event.reward.gold)
	for row: Dictionary in _rows("new_game.csv"):
		if row["kind"] == "gold" and row["amount"].is_valid_int():
			_check_fee("new_game.csv", row["id"], "amount", row["amount"].to_int())


## 料金・お金は 0 以上（DAT-903）
func _check_fee(file: String, id: Variant, column: String, value: int) -> void:
	if value < 0:
		_add(file, id, "DAT-903", "%s が負です: %d" % [column, value])


## 確率は 0〜1（DAT-903）
func _check_probability(file: String, id: Variant, column: String, value: float) -> void:
	if value < 0.0 or value > 1.0:
		_add(file, id, "DAT-903", "%s が0〜1の範囲外です: %s" % [column, value])


func _check_effect_chances(file: String, owner_id: Variant, effects: Array[ActionEffect]) -> void:
	for effect in effects:
		_check_probability(file, owner_id, "status_chance", effect.status_chance)


# --- 職業との対応（DAT-904） ---------------------------------------------------

func _check_job_correspondence() -> void:
	const RULE := "DAT-904"
	for job_def: JobDef in _db.jobs():
		var weapon: EquipmentDef = _db.equipment(job_def.starting_weapon_id)
		if weapon != null:
			if weapon.slot != &"weapon":
				_add("jobs.csv", job_def.id, RULE, "starting_weapon_id が武器ではありません: %s" % weapon.id)
			elif not weapon.allowed_jobs.has(job_def.id):
				_add("jobs.csv", job_def.id, RULE, "starting_weapon_id を装備できません: %s" % weapon.id)
			elif weapon.category != job_def.weapon_category:
				_add("jobs.csv", job_def.id, RULE, "starting_weapon_id の種別が weapon_category と違います: %s" % weapon.id)
		var armor: EquipmentDef = _db.equipment(job_def.starting_armor_id)
		if armor != null:
			if armor.slot != &"armor":
				_add("jobs.csv", job_def.id, RULE, "starting_armor_id が防具ではありません: %s" % armor.id)
			elif not armor.allowed_jobs.has(job_def.id):
				_add("jobs.csv", job_def.id, RULE, "starting_armor_id を装備できません: %s" % armor.id)
		var skill_def: SkillDef = _db.skill(job_def.initial_skill_id)
		if skill_def != null and skill_def.job_id != job_def.id:
			_add("jobs.csv", job_def.id, RULE, "initial_skill_id が別の職業のスキルです: %s" % skill_def.id)
	for equipment_def: EquipmentDef in _db.equipment_list():
		if equipment_def.allowed_jobs.is_empty():
			_add("equipment.csv", equipment_def.id, RULE, "allowed_jobs が空です")
		if equipment_def.slot != &"weapon":
			continue
		for job_id in equipment_def.allowed_jobs:
			var job_def: JobDef = _db.job(job_id)
			if job_def != null and job_def.weapon_category != equipment_def.category:
				_add("equipment.csv", equipment_def.id, RULE,
						"category が職業 %s の weapon_category と違います" % job_id)


# --- 対象と使用場面（DAT-905） -------------------------------------------------

func _check_target_contexts() -> void:
	for skill_def: SkillDef in _db.skills():
		_check_use("skills.csv", skill_def.id, skill_def.target, skill_def.contexts)
	for item_def: ItemDef in _db.items():
		match item_def.kind:
			&"consumable":
				_check_use("items.csv", item_def.id, item_def.target, item_def.contexts)
			&"material":
				if item_def.target != &"":
					_add("items.csv", item_def.id, "DAT-905", "素材の target が空ではありません: %s" % item_def.target)
				if not item_def.contexts.is_empty():
					_add("items.csv", item_def.id, "DAT-905", "素材の contexts が空ではありません: %s" % [item_def.contexts])
			_:
				_add("items.csv", item_def.id, "DAT-905", "kind が consumable / material ではありません: %s" % item_def.kind)
	# 敵行動は使用場面の列を持たず、戦闘で使う。対象は戦闘で使える値に限る
	var battle_only: Array[StringName] = [BATTLE_CONTEXT]
	for action_def: EnemyActionDef in _db.enemy_actions():
		_check_use("enemy_actions.csv", action_def.id, action_def.target, battle_only)


## 対象と使用場面の組み合わせが表（DAT-905）に従う。使用場面が空のスキル・消耗品は、使えないため問題とする
func _check_use(file: String, id: Variant, target: StringName, contexts: Array[StringName]) -> void:
	const RULE := "DAT-905"
	if not SkillDef.TARGETS.has(target):
		_add(file, id, RULE, "target が DAT-116 の値ではありません: %s" % target)
		return
	if contexts.is_empty():
		_add(file, id, RULE, "contexts が空です")
		return
	for context in contexts:
		if not SkillDef.CONTEXTS.has(context):
			_add(file, id, RULE, "contexts が DAT-117 の値ではありません: %s" % context)
			return
	if BATTLE_ONLY_TARGETS.has(target):
		for context in contexts:
			if context != BATTLE_CONTEXT:
				_add(file, id, RULE, "%s は battle のみで使えます（contexts に %s）" % [target, context])
				return
	elif target == PARTY_TARGET and contexts.has(BATTLE_CONTEXT):
		_add(file, id, RULE, "%s は battle で使えません" % target)


# --- 敵の行動（DAT-906） -------------------------------------------------------

## 行動の参照先の存在は、DAT-902 として `GameDatabase` が検査する
func _check_enemy_actions() -> void:
	const RULE := "DAT-906"
	var turn_indexes := {}
	for row: Dictionary in _rows("enemy_action_cycles.csv"):
		if not turn_indexes.has(row["enemy_id"]):
			turn_indexes[row["enemy_id"]] = []
		if row["turn_index"].is_valid_int():
			turn_indexes[row["enemy_id"]].append(row["turn_index"].to_int())

	for enemy_def: EnemyDef in _db.enemies():
		match enemy_def.action_mode:
			&"weighted":
				_check_weights(enemy_def)
			&"cycle":
				var indexes: Array = turn_indexes.get(String(enemy_def.id), [])
				indexes.sort()
				if indexes.is_empty():
					_add("enemy_action_cycles.csv", enemy_def.id, RULE, "固定巡回の行がありません")
				for i in indexes.size():
					if indexes[i] != i + 1:
						_add("enemy_action_cycles.csv", enemy_def.id, RULE,
								"turn_index が1からの連番ではありません: %s" % [indexes])
						break
			_:
				_add("enemies.csv", enemy_def.id, RULE, "action_mode が weighted / cycle ではありません: %s" % enemy_def.action_mode)


func _check_weights(enemy_def: EnemyDef) -> void:
	const RULE := "DAT-906"
	var total := 0
	for weighted in enemy_def.action_weights:
		if weighted.weight < 1:
			_add("enemy_action_weights.csv", enemy_def.id, RULE,
					"weight が1未満です: %s の %d" % [weighted.action_id, weighted.weight])
		total += weighted.weight
	if total != WEIGHT_TOTAL:
		_add("enemy_action_weights.csv", enemy_def.id, RULE,
				"重みの合計が%dではありません: %d" % [WEIGHT_TOTAL, total])


# --- クエスト（DAT-907） -------------------------------------------------------

## 対象IDと報酬のアイテムIDの存在は、DAT-902 として `GameDatabase` が検査する。
## ここでは、数の欄を検査する（ItemStackDef の数量は1以上。DAT-102）
func _check_quests() -> void:
	const RULE := "DAT-907"
	for quest_def: QuestDef in _db.quests():
		if quest_def.target_count < 1:
			_add("quests.csv", quest_def.id, RULE, "target_count が1未満です: %d" % quest_def.target_count)
		if quest_def.reward.exp < 0:
			_add("quests.csv", quest_def.id, RULE, "reward_exp が負です: %d" % quest_def.reward.exp)
		for stack in quest_def.reward.items:
			if stack.quantity < 1:
				_add("quests.csv", quest_def.id, RULE, "reward_item_quantity が1未満です: %d" % stack.quantity)


# --- セルイベントの必須欄（DAT-225） -------------------------------------------

## 到着先との相互リンクの成立（MAP-125）は、マップのコンパイル（D02, D04）が検査する。
## 参照先の存在は、DAT-902 として `GameDatabase` が検査する
func _check_cell_events() -> void:
	const RULE := "DAT-225"
	const FILE := "floor_events.csv"
	var reward_rows := {}
	for row: Dictionary in _rows("chest_rewards.csv"):
		reward_rows[row["event_id"]] = reward_rows.get(row["event_id"], 0) + 1

	for event in _events():
		if not EVENT_REQUIRED.has(event.kind):
			_add(FILE, event.id, RULE, "kind が DAT-123 の値ではありません: %s" % event.kind)
			continue
		var required: Array = EVENT_REQUIRED[event.kind]
		for field in EVENT_FIELDS:
			var is_set := _event_field_is_set(event, field)
			if required.has(field) and not is_set:
				_add(FILE, event.id, RULE, "%s には %s が必要です" % [event.kind, field])
			elif not required.has(field) and is_set:
				_add(FILE, event.id, RULE, "%s の表にない欄 %s が空ではありません" % [event.kind, field])

		if required.has("link_facing") and event.link_facing != CellEventDef.UNSET_FACING \
				and (event.link_facing < FACING_MIN or event.link_facing > FACING_MAX):
			_add(FILE, event.id, RULE, "link_facing が %d〜%d ではありません: %d" % [FACING_MIN, FACING_MAX, event.link_facing])
		if event.kind == &"shortcut" and event.unlock_from != CellEventDef.UNSET_CELL \
				and absi(event.unlock_from.x) + absi(event.unlock_from.y) != 1:
			_add(FILE, event.id, RULE, "unlock_from が単位ベクトルではありません（MAP-127）: %s" % event.unlock_from)
		if event.kind == &"boss" and event.enemy_id != &"":
			var enemy_def: EnemyDef = _db.enemy(event.enemy_id)
			if enemy_def != null and not enemy_def.is_boss:
				_add(FILE, event.id, RULE, "enemy_id が is_boss の敵ではありません: %s" % event.enemy_id)

		var count: int = reward_rows.get(String(event.id), 0)
		if event.kind == &"chest":
			if count == 0:
				_add(FILE, event.id, RULE, "chest_rewards.csv に行がありません")
			elif count > 1:
				_add("chest_rewards.csv", event.id, RULE, "chest_rewards.csv の行が%d個あります（1行のみ）" % count)
		elif count > 0:
			_add("chest_rewards.csv", event.id, RULE, "chest ではない %s に報酬の行があります" % event.kind)

		if event.reward != null:
			for stack in event.reward.items:
				if stack.quantity < 1:
					_add("chest_rewards.csv", event.id, "DAT-102", "quantity が1未満です: %d" % stack.quantity)


func _event_field_is_set(event: CellEventDef, field: String) -> bool:
	match field:
		"link_floor_id":
			return event.link_floor_id != &""
		"link_cell":
			return event.link_cell != CellEventDef.UNSET_CELL
		"link_facing":
			return event.link_facing != CellEventDef.UNSET_FACING
		"unlock_from":
			return event.unlock_from != CellEventDef.UNSET_CELL
		"enemy_id":
			return event.enemy_id != &""
		"warp_id":
			return event.warp_id != &""
		"text_id":
			return event.text_id != &""
	return false


# --- 文章（DAT-909） -----------------------------------------------------------

func _check_texts() -> void:
	const RULE := "DAT-909"
	const FILE := "texts.csv"
	var braces := RegEx.new()
	braces.compile("\\{([^{}]*)\\}")
	for row: Dictionary in _rows("texts.csv"):
		var id: String = row["id"]
		var body: String = row["text"]
		if body == "":
			_add(FILE, id, RULE, "本文が空です")
			continue
		for found in braces.search_all(body):
			if not PARAMETER_NAMES.has(found.get_string(1)):
				_add(FILE, id, RULE, "波括弧の名前 {%s} は、使える名前（%s）ではありません"
						% [found.get_string(1), ", ".join(PARAMETER_NAMES)])
		var rest := braces.sub(body, "", true)
		if rest.contains("{") or rest.contains("}"):
			_add(FILE, id, RULE, "対応しない波括弧があります")

	var sources := {}
	for doc: String in REQUIRED_TEXTS:
		for id: String in REQUIRED_TEXTS[doc]:
			if not sources.has(id):
				sources[id] = "%s の文言" % doc
	for code in ERROR_CODES:
		sources["error_" + code.to_lower()] = "ARC-401 のエラーコード %s" % code
	for enemy_def: EnemyDef in _db.enemies():
		if enemy_def.is_boss:
			sources["boss_%s_pre" % enemy_def.id] = "DAT-231 のボス %s" % enemy_def.id
	for id: String in sources:
		if not _db.has_text(StringName(id)):
			_add(FILE, id, RULE, "コードが固定IDで参照する文章がありません（%s）" % sources[id])
