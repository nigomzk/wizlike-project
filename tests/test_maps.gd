extends RefCounted
## TST-400: データとマップのコンパイル（D）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["D01", "D02", "D03", "D04"]

const DB_SCRIPT := "res://scripts/core/game_database.gd"
const DATA_DIR := "res://data"
const MANIFEST := "res://data/manifest.csv"
const CONTENT_VERSION_KEY := "content_version"
## manifest.csv に件数が載るCSV。0件で合格してしまわないよう、全件の存在を確かめる（DAT-901）
const COUNTED_FILES := [
	"jobs.csv", "skills.csv", "skill_effects.csv", "equipment.csv", "items.csv", "item_effects.csv",
	"enemies.csv", "enemy_modifiers.csv", "enemy_actions.csv", "enemy_action_effects.csv",
	"enemy_action_weights.csv", "enemy_action_cycles.csv", "floors.csv", "encounters.csv",
	"floor_events.csv", "chest_rewards.csv", "quests.csv", "shop_tiers.csv", "texts.csv", "new_game.csv",
]


func run(t) -> void:
	_d01(t)


# D01: データベースをロードする（DAT-901, DAT-902）
func _d01(t) -> void:
	var manifest := _read_manifest()
	var db = load(DB_SCRIPT).new()
	var log_lines: Array = []
	var ok: bool = db.load_and_validate(DATA_DIR, func(line: String) -> void: log_lines.append(line))
	t.check("D01", true, ok)
	t.check("D01", [], log_lines)

	# content_version と、全CSVの件数は manifest.csv から読む（DAT-901）
	t.check("D01", true, manifest.has(CONTENT_VERSION_KEY))
	t.check("D01", manifest.get(CONTENT_VERSION_KEY, ""), db.content_version)
	for file in COUNTED_FILES:
		t.check("D01", true, manifest.has(file))
	t.check("D01", COUNTED_FILES.size() + 1, manifest.size())

	# 読んだ行数が manifest.csv と一致する。さらに、定義へ変換された件数も一致する
	var row_counts: Dictionary = db.row_counts
	for file in COUNTED_FILES:
		t.check("D01", manifest.get(file, -1), row_counts.get(file, -2))
		t.check("D01", manifest.get(file, -1), _loaded_count(db, file))

	_check_references(t, db)
	_check_csv_values(t, db)
	_check_derived(t, db)
	_check_resolution(t, db)
	_check_keep_file_imports(t)
	db.free()


## 各CSVが定義Resourceへ何件変換されたか
func _loaded_count(db, file: String) -> int:
	var n := 0
	match file:
		"jobs.csv":
			return db.jobs().size()
		"skills.csv":
			return db.skills().size()
		"skill_effects.csv":
			for s in db.skills():
				n += s.effects.size()
		"equipment.csv":
			return db.equipment_list().size()
		"items.csv":
			return db.items().size()
		"item_effects.csv":
			for i in db.items():
				n += i.effects.size()
		"enemies.csv":
			return db.enemies().size()
		"enemy_modifiers.csv":
			for e in db.enemies():
				n += e.element_multipliers.size() + e.status_multipliers.size()
		"enemy_actions.csv":
			return db.enemy_actions().size()
		"enemy_action_effects.csv":
			for a in db.enemy_actions():
				n += a.effects.size()
		"enemy_action_weights.csv":
			for e in db.enemies():
				n += e.action_weights.size()
		"enemy_action_cycles.csv":
			for e in db.enemies():
				n += e.action_cycle.size()
		"floors.csv":
			return db.floors().size()
		"encounters.csv":
			for f in db.floors():
				n += f.encounters.size()
		"floor_events.csv":
			for f in db.floors():
				n += f.events.size()
		"chest_rewards.csv":
			for f in db.floors():
				for ev in f.events:
					if ev.reward != null:
						n += 1
		"quests.csv":
			return db.quests().size()
		"shop_tiers.csv":
			return db.shop_tier_conditions().size()
		"texts.csv":
			return db.text_count()
		"new_game.csv":
			return 1 + db.new_game_items.size()
	return n


## すべての参照先IDが存在する（DAT-902, DAT-124）。壊れたものは「どこの何」を一覧で出す
func _check_references(t, db) -> void:
	var bad: Array = []
	for job in db.jobs():
		var weapon = db.equipment(job.starting_weapon_id)
		if weapon == null or weapon.slot != &"weapon":
			bad.append("job %s starting_weapon_id %s" % [job.id, job.starting_weapon_id])
		var armor = db.equipment(job.starting_armor_id)
		if armor == null or armor.slot != &"armor":
			bad.append("job %s starting_armor_id %s" % [job.id, job.starting_armor_id])
		if db.skill(job.initial_skill_id) == null:
			bad.append("job %s initial_skill_id %s" % [job.id, job.initial_skill_id])
	for skill in db.skills():
		if db.job(skill.job_id) == null:
			bad.append("skill %s job_id %s" % [skill.id, skill.job_id])
	for eq in db.equipment_list():
		for job_id in eq.allowed_jobs:
			if db.job(job_id) == null:
				bad.append("equipment %s allowed_jobs %s" % [eq.id, job_id])
	for enemy in db.enemies():
		if enemy.drop_item_id != &"" and db.item_or_equipment(enemy.drop_item_id) == null:
			bad.append("enemy %s drop_item_id %s" % [enemy.id, enemy.drop_item_id])
		for w in enemy.action_weights:
			if db.enemy_action(w.action_id) == null:
				bad.append("enemy %s weight action %s" % [enemy.id, w.action_id])
		for action_id in enemy.action_cycle:
			if db.enemy_action(action_id) == null:
				bad.append("enemy %s cycle action %s" % [enemy.id, action_id])
	for floor_def in db.floors():
		for enc in floor_def.encounters:
			for enemy_id in enc.enemy_ids:
				if db.enemy(enemy_id) == null:
					bad.append("floor %s encounter enemy %s" % [floor_def.id, enemy_id])
		for ev in floor_def.events:
			if ev.link_floor_id != &"" and db.floor_def(ev.link_floor_id) == null:
				bad.append("event %s link_floor_id %s" % [ev.id, ev.link_floor_id])
			if ev.enemy_id != &"" and db.enemy(ev.enemy_id) == null:
				bad.append("event %s enemy_id %s" % [ev.id, ev.enemy_id])
			if ev.text_id != &"" and not db.has_text(ev.text_id):
				bad.append("event %s text_id %s" % [ev.id, ev.text_id])
			if ev.reward != null:
				for stack in ev.reward.items:
					if db.item_or_equipment(stack.item_id) == null:
						bad.append("event %s reward item %s" % [ev.id, stack.item_id])
			if db.cell_event(ev.id) != ev:
				bad.append("event %s not resolvable by id" % ev.id)
	for quest in db.quests():
		_check_target(db, quest, bad)
		for stack in quest.reward.items:
			if db.item_or_equipment(stack.item_id) == null:
				bad.append("quest %s reward item %s" % [quest.id, stack.item_id])
	for stack in db.new_game_items:
		if db.item_or_equipment(stack.item_id) == null:
			bad.append("new_game item %s" % stack.item_id)
	t.check("D01", [], bad)


func _check_target(db, quest, bad: Array) -> void:
	match quest.kind:
		&"kill":
			if db.enemy(quest.target_id) == null:
				bad.append("quest %s kill target %s" % [quest.id, quest.target_id])
		&"deliver":
			var item = db.item(quest.target_id)
			if item == null:
				bad.append("quest %s deliver target %s" % [quest.id, quest.target_id])
		_:
			bad.append("quest %s kind %s" % [quest.id, quest.kind])


## 数値をコードに直書きせず、CSVから読んだ値と一致する
func _check_csv_values(t, db) -> void:
	for row in _read_rows("jobs.csv"):
		var job = db.job(StringName(row["id"]))
		t.check("D01", true, job != null)
		if job == null:
			continue
		t.check("D01", row["name"], job.name)
		t.check("D01", int(row["base_hp"]), job.base_stats.hp)
		t.check("D01", int(row["base_luc"]), job.base_stats.luc)
		t.check("D01", int(row["fixed_str"]), job.growth_fixed.str)
		t.check("D01", float(row["chance_agi"]), job.growth_extra_chance.agi)
		t.check("D01", row["weapon_category"], String(job.weapon_category))
	for row in _read_rows("equipment.csv"):
		var eq = db.equipment(StringName(row["id"]))
		t.check("D01", true, eq != null)
		if eq == null:
			continue
		t.check("D01", int(row["attack"]), eq.attack)
		t.check("D01", int(row["bonus_sp"]), eq.stat_bonus.sp)
		t.check("D01", int(row["buy_price"]), eq.buy_price)
		t.check("D01", row["shop_tier"], String(eq.shop_tier))
	for row in _read_rows("items.csv"):
		var item = db.item(StringName(row["id"]))
		t.check("D01", true, item != null)
		if item == null:
			continue
		t.check("D01", int(row["max_stack"]), item.max_stack)
		t.check("D01", int(row["buy_price"]), item.buy_price)
	for row in _read_rows("enemies.csv"):
		var enemy = db.enemy(StringName(row["id"]))
		t.check("D01", true, enemy != null)
		if enemy == null:
			continue
		t.check("D01", int(row["hp"]), enemy.hp)
		t.check("D01", float(row["drop_chance"]), enemy.drop_chance)
		t.check("D01", row["is_boss"] == "true", enemy.is_boss)
	for row in _read_rows("skill_effects.csv"):
		var skill = db.skill(StringName(row["skill_id"]))
		t.check("D01", true, skill != null)
		if skill == null:
			continue
		var matching: Array = skill.effects.filter(func(e): return String(e.kind) == row["kind"] and is_equal_approx(e.multiplier, float(row["multiplier"])))
		t.check("D01", true, matching.size() >= 1)
	for row in _read_rows("floors.csv"):
		var f = db.floor_def(StringName(row["id"]))
		t.check("D01", true, f != null)
		if f == null:
			continue
		t.check("D01", Vector2i(int(row["default_spawn_x"]), int(row["default_spawn_y"])), f.default_spawn)
		t.check("D01", int(row["default_facing"]), f.default_facing)


## 導出フィールド（DAT-227）
func _check_derived(t, db) -> void:
	var skill_rows := _read_rows("skills.csv")
	var equipment_rows := _read_rows("equipment.csv")
	for row in _read_rows("jobs.csv"):
		var job = db.job(StringName(row["id"]))
		if job == null:
			continue
		var expected_skills: Array = []
		for s in skill_rows:
			if s["job_id"] == row["id"]:
				expected_skills.append(s["id"])
		var expected_armors: Array = []
		for e in equipment_rows:
			if e["slot"] == "armor" and Array(e["allowed_jobs"].split("|")).has(row["id"]):
				expected_armors.append(e["id"])
		t.check("D01", expected_skills, _strings(job.learnable_skill_ids))
		t.check("D01", true, expected_skills.size() > 0)
		t.check("D01", expected_armors, _strings(job.armor_ids))
		t.check("D01", true, expected_armors.size() > 0)


## 素材のパス解決（DAT-228, DAT-229）と文章の取得
func _check_resolution(t, db) -> void:
	t.check("D01", "res://assets/icons/herb.png", db.icon_path(&"herb"))
	t.check("D01", "res://assets/enemies/slime.png", db.enemy_portrait_path(&"slime"))
	t.check("D01", "res://assets/portraits/portrait_01.png", db.portrait_path("portrait_01"))
	# ファイルがなければ null（画面が仮の図形を出す）。検証エラーにはしない
	t.check("D01", ResourceLoader.exists(db.icon_path(&"herb")), db.icon_texture(&"herb") != null)
	t.check("D01", ResourceLoader.exists(db.enemy_portrait_path(&"slime")), db.enemy_portrait_texture(&"slime") != null)
	t.check("D01", ResourceLoader.exists(db.portrait_path("portrait_01")), db.portrait_texture("portrait_01") != null)
	t.check("D01", db.icon_texture(&"herb") != null, db.item(&"herb").icon != null)
	# authoring_scene は解決規約だけを持ち、存在を検証しない
	for f in db.floors():
		t.check("D01", "res://scenes/floors/%s.tscn" % f.id, f.authoring_scene_path)

	# 文章：波括弧を置換する。渡さない名前はそのまま残す
	var texts := {}
	for row in _read_rows("texts.csv"):
		texts[row["id"]] = row["text"]
	t.check("D01", texts["rescue_confirm"].replace("{gold}", "120"), db.text(&"rescue_confirm", {"gold": 120}))
	t.check("D01", texts["rescue_confirm"], db.text(&"rescue_confirm"))
	t.check("D01", texts["guild_train_confirm"].replace("{name}", "A").replace("{skill}", "B").replace("{gold}", "5"),
			db.text(&"guild_train_confirm", {"name": "A", "skill": "B", "gold": 5}))
	t.check("D01", true, db.has_text(&"intro"))
	t.check("D01", false, db.has_text(&"no_such_text"))


## data/*.csv を翻訳として取り込まない（Keep File）
func _check_keep_file_imports(t) -> void:
	for file in COUNTED_FILES + ["manifest.csv"]:
		var cfg := ConfigFile.new()
		var err := cfg.load("%s/%s.import" % [DATA_DIR, file])
		t.check("D01", OK, err)
		t.check("D01", "keep", cfg.get_value("remap", "importer", ""))


func _strings(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(String(v))
	return out


func _read_manifest() -> Dictionary:
	var out := {}
	for row in _read_rows("manifest.csv"):
		var key: String = row["key"]
		out[key] = row["value"] if key == CONTENT_VERSION_KEY else int(row["value"])
	return out


## テストの期待値をDBの読込とは別に作るため、CSVをここで読む
func _read_rows(file: String) -> Array:
	var rows: Array = []
	var f := FileAccess.open("%s/%s" % [DATA_DIR, file], FileAccess.READ)
	if f == null:
		return rows
	var header := f.get_csv_line()
	while not f.eof_reached():
		var cells := f.get_csv_line()
		if cells.size() == 1 and cells[0] == "":
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cells[i] if i < cells.size() else ""
		rows.append(row)
	return rows
