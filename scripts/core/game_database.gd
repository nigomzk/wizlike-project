extends Node
## 固定データの読込と、IDからの定義の解決（ARC-201, ARC-300, DAT-000）。
##
## `data/` のCSVを唯一の正とし、起動時に定義Resource（`scripts/definitions/`）へ読み込む。
## Autoload として登録するため、`class_name` を付けない（Autoload名と衝突する）。
## 定義は固定の値として扱い、戦闘中のHPなどの可変の値は書き込まない（DAT-002）。
##
## ここで検査するのは、各CSVの件数（DAT-901）と参照先IDの存在（DAT-902）、および定義を作るために必要な
## 列と数値の書式まで。料金・確率・組み合わせなどの検査（DAT-903, DAT-904, DAT-905, DAT-906, DAT-907, DAT-909, DAT-225）は
## game_validator.gd が行い、`load_and_validate()` から呼ぶ。問題のログ出力は、どちらの検査も `_fail()` に集める（DAT-908）。

const DEFAULT_DATA_DIR := "res://data"
const MANIFEST_FILE := "manifest.csv"
const CONTENT_VERSION_KEY := "content_version"

## DAT-228
const ICON_DIR := "res://assets/icons"
const ENEMY_DIR := "res://assets/enemies"
const PORTRAIT_DIR := "res://assets/portraits"
## DAT-229
const FLOOR_SCENE_DIR := "res://scenes/floors"
## DAT-230
const QUEST_TEXT_PREFIX := "quest_"

const LIST_DELIMITER := "|"

## 各CSVの列。定義を作るのに必要な列が欠けていれば、読込を失敗させる
const COLUMNS := {
	"jobs.csv": [
		"id", "name", "base_hp", "base_sp", "base_str", "base_vit", "base_tec", "base_agi", "base_luc",
		"fixed_hp", "fixed_sp", "fixed_str", "fixed_vit", "fixed_tec", "fixed_agi", "fixed_luc",
		"chance_hp", "chance_sp", "chance_str", "chance_vit", "chance_tec", "chance_agi", "chance_luc",
		"starting_weapon_id", "starting_armor_id", "initial_skill_id", "weapon_category",
	],
	"skills.csv": [
		"id", "name", "job_id", "required_level", "learn_cost", "sp_cost", "target", "contexts",
		"always_hit", "priority",
	],
	"skill_effects.csv": ["skill_id", "order", "kind", "damage_model", "element", "power", "multiplier",
		"defense_ratio", "status_id", "status_chance", "restore_ratio", "restore_flat", "duration_steps",
		"requires_previous_hit"],
	"equipment.csv": [
		"id", "name", "slot", "category", "allowed_jobs", "attack", "defense", "bonus_hp", "bonus_sp",
		"bonus_str", "bonus_vit", "bonus_tec", "bonus_agi", "bonus_luc", "buy_price", "sell_price", "shop_tier",
	],
	"items.csv": ["id", "name", "kind", "max_stack", "buy_price", "sell_price", "shop_tier", "target", "contexts"],
	"item_effects.csv": ["item_id", "order", "kind", "damage_model", "element", "power", "multiplier",
		"defense_ratio", "status_id", "status_chance", "restore_ratio", "restore_flat", "duration_steps",
		"requires_previous_hit"],
	"enemies.csv": [
		"id", "name", "hp", "attack", "defense", "tec", "agi", "luc", "exp", "gold", "drop_item_id",
		"drop_chance", "action_mode", "is_boss",
	],
	"enemy_modifiers.csv": ["enemy_id", "kind", "key", "multiplier"],
	"enemy_actions.csv": ["id", "name", "target", "priority", "always_hit"],
	"enemy_action_effects.csv": ["action_id", "order", "kind", "damage_model", "element", "power", "multiplier",
		"defense_ratio", "status_id", "status_chance", "restore_ratio", "restore_flat", "duration_steps",
		"requires_previous_hit"],
	"enemy_action_weights.csv": ["enemy_id", "action_id", "weight"],
	"enemy_action_cycles.csv": ["enemy_id", "turn_index", "action_id"],
	"floors.csv": [
		"id", "display_name", "dungeon", "order", "expected_level_min", "expected_level_max",
		"default_spawn_x", "default_spawn_y", "default_facing",
	],
	"encounters.csv": ["floor_id", "encounter_index", "enemy_ids", "weight"],
	"floor_events.csv": [
		"event_id", "floor_id", "cell_x", "cell_y", "kind", "link_floor_id", "link_cell_x", "link_cell_y",
		"link_facing", "enemy_id", "warp_id", "unlock_from_x", "unlock_from_y", "text_id",
	],
	"chest_rewards.csv": ["event_id", "gold", "item_id", "quantity"],
	"quests.csv": [
		"id", "title", "unlock_kind", "unlock_target_id", "kind", "target_id", "target_count",
		"reward_exp", "reward_gold", "reward_item_id", "reward_item_quantity",
	],
	"shop_tiers.csv": ["tier", "unlock_kind", "unlock_target_id"],
	"texts.csv": ["id", "text"],
	"new_game.csv": ["kind", "id", "amount"],
}

## `content_version`（GLS-501）。`manifest.csv` から読む（DAT-901）
var content_version := ""
## CSVのファイル名 → 読んだ行数
var row_counts: Dictionary = {}
## 直近の `load_and_validate()` で見つかった問題。空なら成功
var errors: PackedStringArray = []
## ニューゲームで支給する所持金とアイテム（`new_game.csv`。TWN-002, TWN-003）
var new_game_gold := 0
var new_game_items: Array[ItemStackDef] = []

var _loaded := false
var _data_dir := DEFAULT_DATA_DIR
var _log_sink := Callable()
## `manifest.csv` の件数。ファイル名 → 件数
var _manifest_counts: Dictionary = {}

var _jobs: Array[JobDef] = []
var _skills: Array[SkillDef] = []
var _equipment: Array[EquipmentDef] = []
var _items: Array[ItemDef] = []
var _enemies: Array[EnemyDef] = []
var _enemy_actions: Array[EnemyActionDef] = []
var _quests: Array[QuestDef] = []
var _floors: Array[FloorDef] = []
var _job_by_id: Dictionary = {}
var _skill_by_id: Dictionary = {}
var _equipment_by_id: Dictionary = {}
var _item_by_id: Dictionary = {}
var _enemy_by_id: Dictionary = {}
var _enemy_action_by_id: Dictionary = {}
var _quest_by_id: Dictionary = {}
var _floor_by_id: Dictionary = {}
var _event_by_id: Dictionary = {}
## 品揃え（tier） → 解禁条件（DAT-226）
var _shop_tier_conditions: Dictionary = {}
var _texts: Dictionary = {}
## ID → 読込済みのテクスチャ（なければ null）
var _texture_cache: Dictionary = {}


## 全CSVを読み込み、件数・参照・値・組み合わせ・文章を検査する（DAT-901, DAT-902, DAT-903, DAT-904, DAT-905, DAT-906, DAT-907, DAT-908, DAT-909）。成功すれば true。
## `data_dir` は読込元（TST-108）。`log_sink` は問題1件ごとに `Callable(line: String)` で呼ばれる。
## 指定がなければ `push_error` へ出力する（DAT-908）。
func load_and_validate(data_dir := DEFAULT_DATA_DIR, log_sink := Callable()) -> bool:
	_reset()
	_data_dir = data_dir
	_log_sink = log_sink

	var tables := {}
	_read_manifest()
	for file in COLUMNS:
		tables[file] = _read_table(file)
	_check_counts()

	_build_definitions(tables)
	_derive_fields()
	_check_references(tables)
	for problem in GameValidator.validate(self, tables):
		_fail(problem["file"], problem["id"], problem["message"])

	_loaded = errors.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


# --- 定義の取得（読み取り専用として扱う） ------------------------------------

func jobs() -> Array[JobDef]:
	return _jobs.duplicate()


func job(id: StringName) -> JobDef:
	return _job_by_id.get(id)


func skills() -> Array[SkillDef]:
	return _skills.duplicate()


func skill(id: StringName) -> SkillDef:
	return _skill_by_id.get(id)


func equipment_list() -> Array[EquipmentDef]:
	return _equipment.duplicate()


func equipment(id: StringName) -> EquipmentDef:
	return _equipment_by_id.get(id)


func items() -> Array[ItemDef]:
	return _items.duplicate()


func item(id: StringName) -> ItemDef:
	return _item_by_id.get(id)


## 所持品・宝箱・報酬・ドロップの `item_id` は、アイテムと装備の和集合を参照する（DAT-124）。
## `ItemDef` か `EquipmentDef` を返す。どちらでもなければ null
func item_or_equipment(id: StringName) -> Resource:
	if _item_by_id.has(id):
		return _item_by_id[id]
	return _equipment_by_id.get(id)


func enemies() -> Array[EnemyDef]:
	return _enemies.duplicate()


func enemy(id: StringName) -> EnemyDef:
	return _enemy_by_id.get(id)


func enemy_actions() -> Array[EnemyActionDef]:
	return _enemy_actions.duplicate()


func enemy_action(id: StringName) -> EnemyActionDef:
	return _enemy_action_by_id.get(id)


func quests() -> Array[QuestDef]:
	return _quests.duplicate()


func quest(id: StringName) -> QuestDef:
	return _quest_by_id.get(id)


func floors() -> Array[FloorDef]:
	return _floors.duplicate()


func floor_def(id: StringName) -> FloorDef:
	return _floor_by_id.get(id)


## セルイベントのIDはフロアをまたいで一意（GLS-401）
func cell_event(id: StringName) -> CellEventDef:
	return _event_by_id.get(id)


## 品揃え（A, B, C）ごとの解禁条件（DAT-226）
func shop_tier_conditions() -> Dictionary:
	return _shop_tier_conditions.duplicate()


# --- 文章（PRS-702） -----------------------------------------------------------

func has_text(id: StringName) -> bool:
	return _texts.has(id)


func text_count() -> int:
	return _texts.size()


## `texts.csv` の文章を返す。`params` の名前に対応する `{名前}` を値に置換する。
## 渡されなかった名前は、そのまま残す。IDがなければ、IDそのものを返す。
func text(id: StringName, params := {}) -> String:
	if not _texts.has(id):
		push_error("GameDatabase: texts.csv に存在しない文章ID: %s" % id)
		return String(id)
	var result: String = _texts[id]
	for key in params:
		result = result.replace("{%s}" % key, str(params[key]))
	return result


# --- 素材のパス解決（DAT-228） -------------------------------------------------

func icon_path(id: StringName) -> String:
	return "%s/%s.png" % [ICON_DIR, id]


func enemy_portrait_path(id: StringName) -> String:
	return "%s/%s.png" % [ENEMY_DIR, id]


## `portrait_id` は `portrait_01` 〜 `portrait_10`（DAT-522）
func portrait_path(portrait_id: String) -> String:
	return "%s/%s.png" % [PORTRAIT_DIR, portrait_id]


## 装備・アイテムのアイコン。ファイルがなければ null（画面が仮の図形を出す。検証エラーにしない）
func icon_texture(id: StringName) -> Texture2D:
	return _texture(icon_path(id))


func enemy_portrait_texture(id: StringName) -> Texture2D:
	return _texture(enemy_portrait_path(id))


## 冒険者の顔。ファイルがなければ null
func portrait_texture(portrait_id: String) -> Texture2D:
	return _texture(portrait_path(portrait_id))


# --- 読込 ----------------------------------------------------------------------

func _reset() -> void:
	_loaded = false
	content_version = ""
	row_counts = {}
	errors = []
	new_game_gold = 0
	new_game_items = []
	_manifest_counts = {}
	_jobs = []
	_skills = []
	_equipment = []
	_items = []
	_enemies = []
	_enemy_actions = []
	_quests = []
	_floors = []
	_job_by_id = {}
	_skill_by_id = {}
	_equipment_by_id = {}
	_item_by_id = {}
	_enemy_by_id = {}
	_enemy_action_by_id = {}
	_quest_by_id = {}
	_floor_by_id = {}
	_event_by_id = {}
	_shop_tier_conditions = {}
	_texts = {}
	_texture_cache = {}


## 問題を記録し、ログの出力先へ送る。問題のあるファイルとIDを含める（DAT-908）
func _fail(file: String, id: String, message: String) -> void:
	var line := "[GameDatabase] %s id=%s: %s" % [file, id if id != "" else "-", message]
	errors.append(line)
	if _log_sink.is_valid():
		_log_sink.call(line)
	else:
		push_error(line)


## CSVを読み、1行を {列名: 値} にして返す。ファイルがない、または必要な列が欠けていれば、問題を記録して空を返す。
## `row_counts` に読んだ行数を記録する
func _read_table(file: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var path := "%s/%s" % [_data_dir, file]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail(file, "", "ファイルを開けません（%s）" % error_string(FileAccess.get_open_error()))
		return rows
	var header := f.get_csv_line()
	if header.size() > 0:
		header[0] = header[0].trim_prefix("﻿")
	var missing := _missing_columns(header, COLUMNS.get(file, []))
	for column in missing:
		_fail(file, "", "列 %s がありません" % column)
	if not missing.is_empty():
		return rows

	var line_number := 1
	while not f.eof_reached():
		var cells := f.get_csv_line()
		line_number += 1
		if cells.size() == 1 and cells[0] == "":
			continue
		if cells.size() != header.size():
			_fail(file, "", "%d行目の列数が見出しと一致しません（%d列と%d列）" % [line_number, cells.size(), header.size()])
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cells[i]
		rows.append(row)
	row_counts[file] = rows.size()
	return rows


func _missing_columns(header: PackedStringArray, required: Array) -> Array:
	return required.filter(func(column) -> bool: return not header.has(column))


## `manifest.csv` を読む。`content_version` と各CSVの件数（DAT-901）
func _read_manifest() -> void:
	var path := "%s/%s" % [_data_dir, MANIFEST_FILE]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail(MANIFEST_FILE, "", "ファイルを開けません（%s）" % error_string(FileAccess.get_open_error()))
		return
	var header := f.get_csv_line()
	if header.size() < 2 or header[0].trim_prefix("﻿") != "key" or header[1] != "value":
		_fail(MANIFEST_FILE, "", "見出しが key,value ではありません")
		return
	while not f.eof_reached():
		var cells := f.get_csv_line()
		if cells.size() == 1 and cells[0] == "":
			continue
		if cells.size() != 2:
			_fail(MANIFEST_FILE, "", "列数が2ではありません")
			continue
		var key := cells[0]
		if key == CONTENT_VERSION_KEY:
			content_version = cells[1]
		elif not cells[1].is_valid_int():
			_fail(MANIFEST_FILE, key, "件数が整数ではありません: %s" % cells[1])
		else:
			_manifest_counts[key] = cells[1].to_int()
	if content_version == "":
		_fail(MANIFEST_FILE, CONTENT_VERSION_KEY, "content_version がありません")


## 各CSVの行数が `manifest.csv` の件数と一致する（DAT-901）
func _check_counts() -> void:
	for file in COLUMNS:
		if not _manifest_counts.has(file):
			_fail(MANIFEST_FILE, file, "件数が載っていません")
		elif row_counts.has(file) and row_counts[file] != _manifest_counts[file]:
			_fail(file, "", "行数が manifest.csv の件数と一致しません（manifest %d、実際 %d）"
					% [_manifest_counts[file], row_counts[file]])
	for key in _manifest_counts:
		if not COLUMNS.has(key):
			_fail(MANIFEST_FILE, key, "未知のファイルの件数です")


# --- 値の変換 ------------------------------------------------------------------

func _int(file: String, row: Dictionary, column: String, id: String, default := 0) -> int:
	var raw: String = row[column]
	if raw == "":
		return default
	if not raw.is_valid_int():
		_fail(file, id, "%s が整数ではありません: %s" % [column, raw])
		return default
	return raw.to_int()


func _float(file: String, row: Dictionary, column: String, id: String, default := 0.0) -> float:
	var raw: String = row[column]
	if raw == "":
		return default
	if not raw.is_valid_float():
		_fail(file, id, "%s が小数ではありません: %s" % [column, raw])
		return default
	return raw.to_float()


func _bool(file: String, row: Dictionary, column: String, id: String) -> bool:
	var raw: String = row[column]
	if raw == "true":
		return true
	if raw != "false" and raw != "":
		_fail(file, id, "%s が true / false ではありません: %s" % [column, raw])
	return false


## `|` 区切りの複数値。空欄は空の配列
func _names(raw: String) -> Array[StringName]:
	var out: Array[StringName] = []
	if raw == "":
		return out
	for part in raw.split(LIST_DELIMITER):
		out.append(StringName(part))
	return out


# --- 定義の構築 ----------------------------------------------------------------

func _build_definitions(tables: Dictionary) -> void:
	var skill_effects := _effects_by_owner("skill_effects.csv", "skill_id", tables)
	var item_effects := _effects_by_owner("item_effects.csv", "item_id", tables)
	var action_effects := _effects_by_owner("enemy_action_effects.csv", "action_id", tables)

	_build_jobs(tables["jobs.csv"])
	_build_skills(tables["skills.csv"], skill_effects)
	_build_equipment(tables["equipment.csv"])
	_build_items(tables["items.csv"], item_effects)
	_build_enemies(tables)
	_build_enemy_actions(tables["enemy_actions.csv"], action_effects)
	_build_texts(tables["texts.csv"])
	_build_floors(tables)
	_build_quests(tables["quests.csv"])
	_build_shop_tiers(tables["shop_tiers.csv"])
	_build_new_game(tables["new_game.csv"])


## 同じIDが2回あれば問題として記録し、後のものは捨てる（件数が合わなくなるため）
func _register(file: String, id: StringName, definition: Resource, by_id: Dictionary, list: Array) -> void:
	if by_id.has(id):
		_fail(file, String(id), "IDが重複しています（GLS-401）")
		return
	by_id[id] = definition
	list.append(definition)


func _stat_block(file: String, row: Dictionary, prefix: String, id: String) -> StatBlock:
	var block := StatBlock.new()
	block.hp = _int(file, row, prefix + "hp", id)
	block.sp = _int(file, row, prefix + "sp", id)
	block.str = _int(file, row, prefix + "str", id)
	block.vit = _int(file, row, prefix + "vit", id)
	block.tec = _int(file, row, prefix + "tec", id)
	block.agi = _int(file, row, prefix + "agi", id)
	block.luc = _int(file, row, prefix + "luc", id)
	return block


func _stat_chance(file: String, row: Dictionary, prefix: String, id: String) -> StatChance:
	var chance := StatChance.new()
	chance.hp = _float(file, row, prefix + "hp", id)
	chance.sp = _float(file, row, prefix + "sp", id)
	chance.str = _float(file, row, prefix + "str", id)
	chance.vit = _float(file, row, prefix + "vit", id)
	chance.tec = _float(file, row, prefix + "tec", id)
	chance.agi = _float(file, row, prefix + "agi", id)
	chance.luc = _float(file, row, prefix + "luc", id)
	return chance


func _build_jobs(rows: Array[Dictionary]) -> void:
	const FILE := "jobs.csv"
	for row in rows:
		var id: String = row["id"]
		var def := JobDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.base_stats = _stat_block(FILE, row, "base_", id)
		def.growth_fixed = _stat_block(FILE, row, "fixed_", id)
		def.growth_extra_chance = _stat_chance(FILE, row, "chance_", id)
		def.starting_weapon_id = StringName(row["starting_weapon_id"])
		def.starting_armor_id = StringName(row["starting_armor_id"])
		def.initial_skill_id = StringName(row["initial_skill_id"])
		def.weapon_category = StringName(row["weapon_category"])
		_register(FILE, def.id, def, _job_by_id, _jobs)


func _build_skills(rows: Array[Dictionary], effects: Dictionary) -> void:
	const FILE := "skills.csv"
	for row in rows:
		var id: String = row["id"]
		var def := SkillDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.job_id = StringName(row["job_id"])
		def.required_level = _int(FILE, row, "required_level", id)
		def.learn_cost = _int(FILE, row, "learn_cost", id)
		def.sp_cost = _int(FILE, row, "sp_cost", id)
		def.target = StringName(row["target"])
		def.contexts = _names(row["contexts"])
		def.always_hit = _bool(FILE, row, "always_hit", id)
		def.priority = _int(FILE, row, "priority", id)
		def.effects = _typed_effects(effects.get(def.id, []))
		_register(FILE, def.id, def, _skill_by_id, _skills)


func _build_equipment(rows: Array[Dictionary]) -> void:
	const FILE := "equipment.csv"
	for row in rows:
		var id: String = row["id"]
		var def := EquipmentDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.slot = StringName(row["slot"])
		def.category = StringName(row["category"])
		def.allowed_jobs = _names(row["allowed_jobs"])
		def.attack = _int(FILE, row, "attack", id)
		def.defense = _int(FILE, row, "defense", id)
		def.stat_bonus = _stat_block(FILE, row, "bonus_", id)
		def.buy_price = _int(FILE, row, "buy_price", id)
		def.sell_price = _int(FILE, row, "sell_price", id)
		def.shop_tier = StringName(row["shop_tier"])
		def.icon = _texture(icon_path(def.id))
		_register(FILE, def.id, def, _equipment_by_id, _equipment)


func _build_items(rows: Array[Dictionary], effects: Dictionary) -> void:
	const FILE := "items.csv"
	for row in rows:
		var id: String = row["id"]
		var def := ItemDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.kind = StringName(row["kind"])
		def.max_stack = _int(FILE, row, "max_stack", id, ItemDef.DEFAULT_MAX_STACK)
		def.buy_price = _int(FILE, row, "buy_price", id, ItemDef.NOT_FOR_SALE)
		def.sell_price = _int(FILE, row, "sell_price", id)
		def.shop_tier = StringName(row["shop_tier"])
		def.target = StringName(row["target"])
		def.contexts = _names(row["contexts"])
		def.effects = _typed_effects(effects.get(def.id, []))
		def.icon = _texture(icon_path(def.id))
		_register(FILE, def.id, def, _item_by_id, _items)


func _build_enemies(tables: Dictionary) -> void:
	const FILE := "enemies.csv"
	for row in tables[FILE]:
		var id: String = row["id"]
		var def := EnemyDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.hp = _int(FILE, row, "hp", id)
		def.attack = _int(FILE, row, "attack", id)
		def.defense = _int(FILE, row, "defense", id)
		def.tec = _int(FILE, row, "tec", id)
		def.agi = _int(FILE, row, "agi", id)
		def.luc = _int(FILE, row, "luc", id)
		def.exp = _int(FILE, row, "exp", id)
		def.gold = _int(FILE, row, "gold", id)
		def.drop_item_id = StringName(row["drop_item_id"])
		def.drop_chance = _float(FILE, row, "drop_chance", id)
		def.action_mode = StringName(row["action_mode"])
		def.is_boss = _bool(FILE, row, "is_boss", id)
		def.portrait = _texture(enemy_portrait_path(def.id))
		_register(FILE, def.id, def, _enemy_by_id, _enemies)

	# 属性倍率と状態異常耐性倍率。記載のないものは 1.0 として扱うため、辞書には載せない
	const MODIFIERS := "enemy_modifiers.csv"
	for row in tables[MODIFIERS]:
		var enemy_def: EnemyDef = _enemy_by_id.get(StringName(row["enemy_id"]))
		if enemy_def == null:
			continue
		var key := StringName(row["key"])
		var multiplier := _float(MODIFIERS, row, "multiplier", row["enemy_id"], 1.0)
		match row["kind"]:
			"element":
				enemy_def.element_multipliers[key] = multiplier
			"status":
				enemy_def.status_multipliers[key] = multiplier
			_:
				_fail(MODIFIERS, row["enemy_id"], "kind が element / status ではありません: %s" % row["kind"])

	const WEIGHTS := "enemy_action_weights.csv"
	for row in tables[WEIGHTS]:
		var enemy_def: EnemyDef = _enemy_by_id.get(StringName(row["enemy_id"]))
		if enemy_def == null:
			continue
		var weighted := WeightedAction.new()
		weighted.action_id = StringName(row["action_id"])
		weighted.weight = _int(WEIGHTS, row, "weight", row["enemy_id"])
		enemy_def.action_weights.append(weighted)

	# 固定巡回は turn_index の昇順（先頭が1）
	const CYCLES := "enemy_action_cycles.csv"
	var cycle_rows: Array = tables[CYCLES].duplicate()
	cycle_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["turn_index"]).to_int() < String(b["turn_index"]).to_int())
	for row in cycle_rows:
		var enemy_def: EnemyDef = _enemy_by_id.get(StringName(row["enemy_id"]))
		if enemy_def == null:
			continue
		_int(CYCLES, row, "turn_index", row["enemy_id"])
		enemy_def.action_cycle.append(StringName(row["action_id"]))


func _build_enemy_actions(rows: Array[Dictionary], effects: Dictionary) -> void:
	const FILE := "enemy_actions.csv"
	for row in rows:
		var id: String = row["id"]
		var def := EnemyActionDef.new()
		def.id = StringName(id)
		def.name = row["name"]
		def.target = StringName(row["target"])
		def.priority = _int(FILE, row, "priority", id)
		def.always_hit = _bool(FILE, row, "always_hit", id)
		def.effects = _typed_effects(effects.get(def.id, []))
		_register(FILE, def.id, def, _enemy_action_by_id, _enemy_actions)


func _build_texts(rows: Array[Dictionary]) -> void:
	for row in rows:
		var id := StringName(row["id"])
		if _texts.has(id):
			_fail("texts.csv", String(id), "IDが重複しています（GLS-401）")
			continue
		_texts[id] = row["text"]


func _build_floors(tables: Dictionary) -> void:
	const FILE := "floors.csv"
	for row in tables[FILE]:
		var id: String = row["id"]
		var def := FloorDef.new()
		def.id = StringName(id)
		def.display_name = row["display_name"]
		def.dungeon = StringName(row["dungeon"])
		def.order = _int(FILE, row, "order", id)
		def.expected_level_min = _int(FILE, row, "expected_level_min", id)
		def.expected_level_max = _int(FILE, row, "expected_level_max", id)
		def.default_spawn = Vector2i(_int(FILE, row, "default_spawn_x", id), _int(FILE, row, "default_spawn_y", id))
		def.default_facing = _int(FILE, row, "default_facing", id)
		def.authoring_scene_path = "%s/%s.tscn" % [FLOOR_SCENE_DIR, id]
		_register(FILE, def.id, def, _floor_by_id, _floors)

	# 編成は encounter_index の昇順
	const ENCOUNTERS := "encounters.csv"
	var encounter_rows: Array = tables[ENCOUNTERS].duplicate()
	encounter_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["encounter_index"]).to_int() < String(b["encounter_index"]).to_int())
	for row in encounter_rows:
		var floor_data: FloorDef = _floor_by_id.get(StringName(row["floor_id"]))
		if floor_data == null:
			continue
		var encounter := EncounterDef.new()
		encounter.enemy_ids = _names(row["enemy_ids"])
		encounter.weight = _int(ENCOUNTERS, row, "weight", row["floor_id"])
		floor_data.encounters.append(encounter)

	const EVENTS := "floor_events.csv"
	for row in tables[EVENTS]:
		var id: String = row["event_id"]
		var floor_data: FloorDef = _floor_by_id.get(StringName(row["floor_id"]))
		var event := CellEventDef.new()
		event.id = StringName(id)
		event.cell = Vector2i(_int(EVENTS, row, "cell_x", id), _int(EVENTS, row, "cell_y", id))
		event.kind = StringName(row["kind"])
		event.link_floor_id = StringName(row["link_floor_id"])
		event.link_cell = _optional_cell(EVENTS, row, "link_cell_x", "link_cell_y", id, CellEventDef.UNSET_CELL)
		event.link_facing = _int(EVENTS, row, "link_facing", id, CellEventDef.UNSET_FACING)
		event.enemy_id = StringName(row["enemy_id"])
		event.warp_id = StringName(row["warp_id"])
		event.unlock_from = _optional_cell(EVENTS, row, "unlock_from_x", "unlock_from_y", id, CellEventDef.UNSET_CELL)
		event.text_id = StringName(row["text_id"])
		if _event_by_id.has(event.id):
			_fail(EVENTS, id, "セルイベントのIDが重複しています（GLS-401）")
			continue
		_event_by_id[event.id] = event
		if floor_data != null:
			floor_data.events.append(event)

	# 宝箱の中身。経験値は設定しない
	const CHESTS := "chest_rewards.csv"
	for row in tables[CHESTS]:
		var id: String = row["event_id"]
		var event: CellEventDef = _event_by_id.get(StringName(id))
		if event == null:
			continue
		var reward := RewardDef.new()
		reward.gold = _int(CHESTS, row, "gold", id)
		var stack := _item_stack(CHESTS, row, "item_id", "quantity", id)
		if stack != null:
			reward.items.append(stack)
		event.reward = reward


func _optional_cell(file: String, row: Dictionary, x_column: String, y_column: String, id: String, unset: Vector2i) -> Vector2i:
	if row[x_column] == "" and row[y_column] == "":
		return unset
	return Vector2i(_int(file, row, x_column, id), _int(file, row, y_column, id))


## アイテムIDが空欄ならアイテムなし（null）
func _item_stack(file: String, row: Dictionary, item_column: String, quantity_column: String, id: String) -> ItemStackDef:
	if row[item_column] == "":
		return null
	var stack := ItemStackDef.new()
	stack.item_id = StringName(row[item_column])
	stack.quantity = _int(file, row, quantity_column, id)
	return stack


func _build_quests(rows: Array[Dictionary]) -> void:
	const FILE := "quests.csv"
	for row in rows:
		var id: String = row["id"]
		var def := QuestDef.new()
		def.id = StringName(id)
		def.title = row["title"]
		var description_id := StringName(QUEST_TEXT_PREFIX + id)
		def.description = _texts.get(description_id, "")
		def.unlock = ConditionDef.new()
		def.unlock.kind = StringName(row["unlock_kind"])
		def.unlock.target_id = StringName(row["unlock_target_id"])
		def.kind = StringName(row["kind"])
		def.target_id = StringName(row["target_id"])
		def.target_count = _int(FILE, row, "target_count", id)
		def.reward = RewardDef.new()
		def.reward.exp = _int(FILE, row, "reward_exp", id)
		def.reward.gold = _int(FILE, row, "reward_gold", id)
		var stack := _item_stack(FILE, row, "reward_item_id", "reward_item_quantity", id)
		if stack != null:
			def.reward.items.append(stack)
		_register(FILE, def.id, def, _quest_by_id, _quests)


func _build_shop_tiers(rows: Array[Dictionary]) -> void:
	for row in rows:
		var tier := StringName(row["tier"])
		if _shop_tier_conditions.has(tier):
			_fail("shop_tiers.csv", String(tier), "品揃えが重複しています")
			continue
		var condition := ConditionDef.new()
		condition.kind = StringName(row["unlock_kind"])
		condition.target_id = StringName(row["unlock_target_id"])
		_shop_tier_conditions[tier] = condition


func _build_new_game(rows: Array[Dictionary]) -> void:
	const FILE := "new_game.csv"
	for row in rows:
		var id: String = row["id"]
		match row["kind"]:
			"gold":
				new_game_gold += _int(FILE, row, "amount", id)
			"item":
				var stack := _item_stack(FILE, row, "id", "amount", id)
				if stack != null:
					new_game_items.append(stack)
			_:
				_fail(FILE, id, "kind が gold / item ではありません: %s" % row["kind"])


## 効果の表を、所有者のID → `order` 昇順の効果の配列にする
func _effects_by_owner(file: String, owner_column: String, tables: Dictionary) -> Dictionary:
	var grouped := {}
	var rows: Array = tables[file].duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["order"]).to_int() < String(b["order"]).to_int())
	for row in rows:
		var owner_id := StringName(row[owner_column])
		var id: String = row[owner_column]
		var effect := ActionEffect.new()
		_int(file, row, "order", id)
		effect.kind = StringName(row["kind"])
		effect.damage_model = StringName(row["damage_model"])
		effect.element = StringName(row["element"])
		effect.power = _int(file, row, "power", id)
		effect.multiplier = _float(file, row, "multiplier", id, 1.0)
		effect.defense_ratio = _float(file, row, "defense_ratio", id, 1.0)
		effect.status_id = StringName(row["status_id"])
		effect.status_chance = _float(file, row, "status_chance", id)
		effect.restore_ratio = _float(file, row, "restore_ratio", id)
		effect.restore_flat = _int(file, row, "restore_flat", id)
		effect.duration_steps = _int(file, row, "duration_steps", id)
		effect.requires_previous_hit = _bool(file, row, "requires_previous_hit", id)
		if not grouped.has(owner_id):
			grouped[owner_id] = []
		grouped[owner_id].append(effect)
	return grouped


func _typed_effects(untyped: Array) -> Array[ActionEffect]:
	var typed: Array[ActionEffect] = []
	typed.assign(untyped)
	return typed


## 導出フィールド（DAT-227）。CSVに列はなく、読込時に作る
func _derive_fields() -> void:
	for job_def in _jobs:
		for skill_def in _skills:
			if skill_def.job_id == job_def.id:
				job_def.learnable_skill_ids.append(skill_def.id)
		for equipment_def in _equipment:
			if equipment_def.slot == &"armor" and equipment_def.allowed_jobs.has(job_def.id):
				job_def.armor_ids.append(equipment_def.id)


# --- 参照の検査（DAT-902） -----------------------------------------------------

func _check_references(tables: Dictionary) -> void:
	for id in _equipment_by_id:
		if _item_by_id.has(id):
			_fail("equipment.csv", String(id), "items.csv と同じIDです（DAT-124）")

	for job_def in _jobs:
		_require(_equipment_by_id, job_def.starting_weapon_id, "jobs.csv", job_def.id, "starting_weapon_id")
		_require(_equipment_by_id, job_def.starting_armor_id, "jobs.csv", job_def.id, "starting_armor_id")
		_require(_skill_by_id, job_def.initial_skill_id, "jobs.csv", job_def.id, "initial_skill_id")
	for skill_def in _skills:
		_require(_job_by_id, skill_def.job_id, "skills.csv", skill_def.id, "job_id")
	for equipment_def in _equipment:
		for job_id in equipment_def.allowed_jobs:
			_require(_job_by_id, job_id, "equipment.csv", equipment_def.id, "allowed_jobs")
	for enemy_def in _enemies:
		_require_stackable(enemy_def.drop_item_id, "enemies.csv", enemy_def.id, "drop_item_id", true)
		for weighted in enemy_def.action_weights:
			_require(_enemy_action_by_id, weighted.action_id, "enemy_action_weights.csv", enemy_def.id, "action_id")
		for action_id in enemy_def.action_cycle:
			_require(_enemy_action_by_id, action_id, "enemy_action_cycles.csv", enemy_def.id, "action_id")
	for floor_data in _floors:
		for encounter in floor_data.encounters:
			for enemy_id in encounter.enemy_ids:
				_require(_enemy_by_id, enemy_id, "encounters.csv", floor_data.id, "enemy_ids")
		for event in floor_data.events:
			_check_event_references(event)
	for quest_def in _quests:
		_check_condition(quest_def.unlock, "quests.csv", quest_def.id)
		match quest_def.kind:
			&"kill":
				_require(_enemy_by_id, quest_def.target_id, "quests.csv", quest_def.id, "target_id")
			&"deliver":
				_require(_item_by_id, quest_def.target_id, "quests.csv", quest_def.id, "target_id")
			_:
				_fail("quests.csv", String(quest_def.id), "kind が kill / deliver ではありません: %s" % quest_def.kind)
		for stack in quest_def.reward.items:
			_require_stackable(stack.item_id, "quests.csv", quest_def.id, "reward_item_id")
	for tier in _shop_tier_conditions:
		_check_condition(_shop_tier_conditions[tier], "shop_tiers.csv", tier)
	for stack in new_game_items:
		_require_stackable(stack.item_id, "new_game.csv", stack.item_id, "id")

	_check_owner_refs(tables["skill_effects.csv"], "skill_effects.csv", "skill_id", _skill_by_id)
	_check_owner_refs(tables["item_effects.csv"], "item_effects.csv", "item_id", _item_by_id)
	_check_owner_refs(tables["enemy_action_effects.csv"], "enemy_action_effects.csv", "action_id", _enemy_action_by_id)
	_check_owner_refs(tables["enemy_modifiers.csv"], "enemy_modifiers.csv", "enemy_id", _enemy_by_id)
	_check_owner_refs(tables["enemy_action_weights.csv"], "enemy_action_weights.csv", "enemy_id", _enemy_by_id)
	_check_owner_refs(tables["enemy_action_cycles.csv"], "enemy_action_cycles.csv", "enemy_id", _enemy_by_id)
	_check_owner_refs(tables["encounters.csv"], "encounters.csv", "floor_id", _floor_by_id)
	_check_owner_refs(tables["floor_events.csv"], "floor_events.csv", "floor_id", _floor_by_id)
	_check_owner_refs(tables["chest_rewards.csv"], "chest_rewards.csv", "event_id", _event_by_id)


func _check_event_references(event: CellEventDef) -> void:
	const FILE := "floor_events.csv"
	if event.link_floor_id != &"":
		_require(_floor_by_id, event.link_floor_id, FILE, event.id, "link_floor_id")
	if event.enemy_id != &"":
		_require(_enemy_by_id, event.enemy_id, FILE, event.id, "enemy_id")
	if event.text_id != &"":
		_require(_texts, event.text_id, FILE, event.id, "text_id")
	if event.reward != null:
		for stack in event.reward.items:
			_require_stackable(stack.item_id, "chest_rewards.csv", event.id, "item_id")


## 解禁条件の対象ID。floor_visited はフロア、boss_first_defeated は敵、warp_unlocked は魔法陣のIDを参照する
func _check_condition(condition: ConditionDef, file: String, owner_id: StringName) -> void:
	match condition.kind:
		&"always":
			pass
		&"floor_visited":
			_require(_floor_by_id, condition.target_id, file, owner_id, "unlock_target_id")
		&"boss_first_defeated":
			_require(_enemy_by_id, condition.target_id, file, owner_id, "unlock_target_id")
		&"warp_unlocked":
			if not _has_warp(condition.target_id):
				_fail(file, String(owner_id), "unlock_target_id の魔法陣が存在しません: %s" % condition.target_id)
		_:
			_fail(file, String(owner_id), "unlock_kind が不正です: %s" % condition.kind)


func _has_warp(warp_id: StringName) -> bool:
	for event_id in _event_by_id:
		var event: CellEventDef = _event_by_id[event_id]
		if event.kind == &"warp" and event.warp_id == warp_id:
			return true
	return false


## 各行の所有者IDが存在する。所有者がないために構築で捨てられた行を拾う
func _check_owner_refs(rows: Array[Dictionary], file: String, column: String, by_id: Dictionary) -> void:
	for row in rows:
		_require(by_id, StringName(row[column]), file, StringName(row[column]), column)


func _require(by_id: Dictionary, target: StringName, file: String, owner_id: StringName, column: String) -> void:
	if not by_id.has(target):
		_fail(file, String(owner_id), "%s の参照先が存在しません: %s" % [column, target])


## アイテムと装備の和集合を参照する（DAT-124）。`allow_empty` なら空欄を許す
func _require_stackable(target: StringName, file: String, owner_id: StringName, column: String, allow_empty := false) -> void:
	if target == &"" and allow_empty:
		return
	if item_or_equipment(target) == null:
		_fail(file, String(owner_id), "%s の参照先が存在しません: %s" % [column, target])


# --- 素材 ----------------------------------------------------------------------

## ファイルがなければ null。取り込み済みの素材は元ファイルが書き出しに含まれないため、
## `FileAccess.file_exists()` ではなく `ResourceLoader.exists()` で調べる
func _texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[path] = texture
	return texture
