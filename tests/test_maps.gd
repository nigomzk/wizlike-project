extends RefCounted
## TST-400: データとマップのコンパイル（D）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["D01", "D02", "D03", "D04"]

const DB_SCRIPT := "res://scripts/core/game_database.gd"
const DATA_DIR := "res://data"
const MANIFEST := "res://data/manifest.csv"
const CONTENT_VERSION_KEY := "content_version"
## D03 が不正を入れる複写の置き場所（TST-108）
const TMP_DIR := "user://test_tmp"
## manifest.csv に件数が載るCSV。0件で合格してしまわないよう、全件の存在を確かめる（DAT-901）
const COUNTED_FILES := [
	"jobs.csv", "skills.csv", "skill_effects.csv", "equipment.csv", "items.csv", "item_effects.csv",
	"enemies.csv", "enemy_modifiers.csv", "enemy_actions.csv", "enemy_action_effects.csv",
	"enemy_action_weights.csv", "enemy_action_cycles.csv", "floors.csv", "encounters.csv",
	"floor_events.csv", "chest_rewards.csv", "quests.csv", "shop_tiers.csv", "texts.csv", "new_game.csv",
]


func run(t) -> void:
	_d01(t)
	_d03(t)


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
		t.check("D01", ResourceLoader.exists(f.authoring_scene_path), f.authoring_scene != null)

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


# D03: 不正なデータはロードを失敗させ、問題のファイル名とIDをログへ出す
# （DAT-902, DAT-903, DAT-904, DAT-905, DAT-906, DAT-907, DAT-908, DAT-909, DAT-225）
func _d03(t) -> void:
	var bad: Array = []
	# 対照：無傷の複写は成功する。以降の失敗が、注入した不正によるものだと言えるようにする（TST-108）
	_copy_data()
	var control := _load_copy()
	t.check("D03", true, control["ok"])
	t.check("D03", [], control["log"])

	for c in _d03_cases():
		_copy_data()
		var applied := true
		for op in c["ops"]:
			if _apply(op) == 0:
				applied = false
		if not applied:
			bad.append("%s: 注入する行が見つからない" % c["label"])
			continue
		var result := _load_copy()
		if result["ok"]:
			bad.append("%s: ロードが成功した" % c["label"])
		var expected := "%s id=%s:" % [c["file"], c["id"] if c["id"] != "" else "-"]
		var found := false
		for line in result["log"]:
			if line.contains(expected):
				found = true
		if not found:
			bad.append("%s: ログに「%s」がない（%s）" % [c["label"], expected, result["log"]])
		# ログへ出した行は、データベースが記録した問題と一致する
		t.check("D03", result["log"], result["errors"])
	t.check("D03", [], bad)
	_remove_data_copy()


## 注入する不正の一覧。`file` と `id` は、ログに出るべき問題のファイル名とID（IDなしは空）
func _d03_cases() -> Array:
	var cases: Array = []
	# 参照切れ（DAT-902）
	cases.append(_case("参照切れ: ドロップ品", "enemies.csv", "slime",
			[_op_set("enemies.csv", {"id": "slime"}, {"drop_item_id": "no_such_item"})]))
	cases.append(_case("参照切れ: 敵行動", "enemy_action_weights.csv", "wolf",
			[_op_set("enemy_action_weights.csv", {"enemy_id": "wolf", "action_id": "bite"}, {"action_id": "no_such_action"})]))
	# 件数（DAT-901）
	cases.append(_case("件数: manifest と一致しない", "jobs.csv", "",
			[_op_set("manifest.csv", {"key": "jobs.csv"}, {"value": "6"})]))
	# 負の料金（DAT-903）
	cases.append(_case("負の料金: 装備の購入価格", "equipment.csv", "sword_1",
			[_op_set("equipment.csv", {"id": "sword_1"}, {"buy_price": "-5"})]))
	cases.append(_case("負の料金: アイテムの売却価格", "items.csv", "herb",
			[_op_set("items.csv", {"id": "herb"}, {"sell_price": "-1"})]))
	cases.append(_case("負の料金: 非売品（-1）以外の購入価格", "items.csv", "herb",
			[_op_set("items.csv", {"id": "herb"}, {"buy_price": "-2"})]))
	cases.append(_case("負の料金: 習得料金", "skills.csv", "sweep",
			[_op_set("skills.csv", {"id": "sweep"}, {"learn_cost": "-1"})]))
	cases.append(_case("負の料金: クエスト報酬のお金", "quests.csv", "q_slime",
			[_op_set("quests.csv", {"id": "q_slime"}, {"reward_gold": "-1"})]))
	cases.append(_case("負の料金: 宝箱のお金", "chest_rewards.csv", "ruins_f1_chest_b",
			[_op_set("chest_rewards.csv", {"event_id": "ruins_f1_chest_b"}, {"gold": "-1"})]))
	cases.append(_case("負の料金: 敵のお金", "enemies.csv", "slime",
			[_op_set("enemies.csv", {"id": "slime"}, {"gold": "-1"})]))
	cases.append(_case("負の料金: 初期の所持金", "new_game.csv", "",
			[_op_set("new_game.csv", {"kind": "gold"}, {"amount": "-1"})]))
	# HPが0以下（DAT-903）
	cases.append(_case("HP: 敵が0", "enemies.csv", "slime",
			[_op_set("enemies.csv", {"id": "slime"}, {"hp": "0"})]))
	cases.append(_case("HP: 職業の基礎値が0", "jobs.csv", "warrior",
			[_op_set("jobs.csv", {"id": "warrior"}, {"base_hp": "0"})]))
	# 範囲外の確率（DAT-903）
	cases.append(_case("確率: ドロップ率が1を超える", "enemies.csv", "slime",
			[_op_set("enemies.csv", {"id": "slime"}, {"drop_chance": "1.5"})]))
	cases.append(_case("確率: 追加増加の確率が負", "jobs.csv", "warrior",
			[_op_set("jobs.csv", {"id": "warrior"}, {"chance_hp": "-0.1"})]))
	cases.append(_case("確率: スキル効果の状態異常の確率が1を超える", "skill_effects.csv", "sleep_dust",
			[_op_set("skill_effects.csv", {"skill_id": "sleep_dust"}, {"status_chance": "2"})]))
	# 職業との対応（DAT-904）
	cases.append(_case("職業: 初期武器を装備できない", "jobs.csv", "warrior",
			[_op_set("jobs.csv", {"id": "warrior"}, {"starting_weapon_id": "staff_1"})]))
	cases.append(_case("職業: 初期防具が防具でない", "jobs.csv", "warrior",
			[_op_set("jobs.csv", {"id": "warrior"}, {"starting_armor_id": "sword_1"})]))
	cases.append(_case("職業: 初期スキルが別の職業のもの", "jobs.csv", "warrior",
			[_op_set("jobs.csv", {"id": "warrior"}, {"initial_skill_id": "fire"})]))
	cases.append(_case("職業: 装備できる職業がない", "equipment.csv", "sword_1",
			[_op_set("equipment.csv", {"id": "sword_1"}, {"allowed_jobs": ""})]))
	cases.append(_case("職業: 武器の種別が職業の武器種と合わない", "equipment.csv", "sword_1",
			[_op_set("equipment.csv", {"id": "sword_1"}, {"category": "axe"})]))
	# 対象と使用場面（DAT-905）
	cases.append(_case("組み合わせ: 敵対象のスキルが街で使える", "skills.csv", "fire",
			[_op_set("skills.csv", {"id": "fire"}, {"contexts": "battle|town"})]))
	cases.append(_case("組み合わせ: PARTY が戦闘で使える", "skills.csv", "silent_steps",
			[_op_set("skills.csv", {"id": "silent_steps"}, {"contexts": "battle|exploration"})]))
	cases.append(_case("組み合わせ: 使用場面が空", "skills.csv", "heal",
			[_op_set("skills.csv", {"id": "heal"}, {"contexts": ""})]))
	cases.append(_case("組み合わせ: 対象が列挙にない", "skills.csv", "heal",
			[_op_set("skills.csv", {"id": "heal"}, {"target": "NOBODY"})]))
	cases.append(_case("組み合わせ: 使用場面が列挙にない", "skills.csv", "heal",
			[_op_set("skills.csv", {"id": "heal"}, {"contexts": "battle|space"})]))
	cases.append(_case("組み合わせ: アイテムの PARTY が戦闘で使える", "items.csv", "return_thread",
			[_op_set("items.csv", {"id": "return_thread"}, {"contexts": "battle|exploration"})]))
	cases.append(_case("組み合わせ: 素材に対象がある", "items.csv", "slime_gel",
			[_op_set("items.csv", {"id": "slime_gel"}, {"target": "LIVING_ALLY"})]))
	cases.append(_case("組み合わせ: 素材に使用場面がある", "items.csv", "slime_gel",
			[_op_set("items.csv", {"id": "slime_gel"}, {"contexts": "town"})]))
	cases.append(_case("組み合わせ: アイテムの種類が列挙にない", "items.csv", "herb",
			[_op_set("items.csv", {"id": "herb"}, {"kind": "gadget"})]))
	cases.append(_case("組み合わせ: 敵行動の対象が PARTY", "enemy_actions.csv", "attack",
			[_op_set("enemy_actions.csv", {"id": "attack"}, {"target": "PARTY"})]))
	# 敵の行動（DAT-906）
	cases.append(_case("敵行動: 重み合計が100でない", "enemy_action_weights.csv", "wolf",
			[_op_set("enemy_action_weights.csv", {"enemy_id": "wolf", "action_id": "attack"}, {"weight": "60"})]))
	cases.append(_case("敵行動: 重みが0の行がある（合計は100）", "enemy_action_weights.csv", "wolf",
			[_op_set("enemy_action_weights.csv", {"enemy_id": "wolf", "action_id": "attack"}, {"weight": "100"}),
			_op_set("enemy_action_weights.csv", {"enemy_id": "wolf", "action_id": "bite"}, {"weight": "0"})]))
	cases.append(_case("敵行動: 重み付きなのに行動表がない", "enemy_action_weights.csv", "slime",
			[_op_remove("enemy_action_weights.csv", {"enemy_id": "slime"})]))
	cases.append(_case("敵行動: 行動の方式が列挙にない", "enemies.csv", "slime",
			[_op_set("enemies.csv", {"id": "slime"}, {"action_mode": "random"})]))
	cases.append(_case("敵行動: 固定巡回の連番が欠ける", "enemy_action_cycles.csv", "gatekeeper",
			[_op_remove("enemy_action_cycles.csv", {"enemy_id": "gatekeeper", "turn_index": "2"})]))
	cases.append(_case("敵行動: 固定巡回の連番が重複する", "enemy_action_cycles.csv", "gatekeeper",
			[_op_set("enemy_action_cycles.csv", {"enemy_id": "gatekeeper", "turn_index": "3"}, {"turn_index": "2"})]))
	cases.append(_case("敵行動: 固定巡回が1から始まらない", "enemy_action_cycles.csv", "gatekeeper",
			[_op_set("enemy_action_cycles.csv", {"enemy_id": "gatekeeper", "turn_index": "1"}, {"turn_index": "0"})]))
	# クエスト（DAT-907）
	cases.append(_case("クエスト: 必要数が0", "quests.csv", "q_slime",
			[_op_set("quests.csv", {"id": "q_slime"}, {"target_count": "0"})]))
	cases.append(_case("クエスト: 報酬のアイテムの数が0", "quests.csv", "q_slime",
			[_op_set("quests.csv", {"id": "q_slime"}, {"reward_item_quantity": "0"})]))
	cases.append(_case("クエスト: 報酬の経験値が負", "quests.csv", "q_slime",
			[_op_set("quests.csv", {"id": "q_slime"}, {"reward_exp": "-1"})]))
	cases.append(_case("クエスト: 納品先のIDがない", "quests.csv", "q_wings",
			[_op_set("quests.csv", {"id": "q_wings"}, {"target_id": "no_such_item"})]))
	# セルイベントの必須欄（DAT-225）
	cases.append(_case("イベント: 階段に移動先のセルがない", "floor_events.csv", "ruins_f1_exit",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_exit"}, {"link_cell_x": "", "link_cell_y": ""})]))
	cases.append(_case("イベント: 階段の向きが範囲外", "floor_events.csv", "ruins_f1_exit",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_exit"}, {"link_facing": "9"})]))
	cases.append(_case("イベント: 近道に開通許可側がない", "floor_events.csv", "ruins_f1_shortcut",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_shortcut"}, {"unlock_from_x": "", "unlock_from_y": ""})]))
	cases.append(_case("イベント: 近道の開通許可側が単位ベクトルでない", "floor_events.csv", "ruins_f1_shortcut",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_shortcut"}, {"unlock_from_x": "1", "unlock_from_y": "1"})]))
	cases.append(_case("イベント: 宝箱の行がない", "floor_events.csv", "ruins_f1_chest_a",
			[_op_remove("chest_rewards.csv", {"event_id": "ruins_f1_chest_a"})]))
	cases.append(_case("イベント: 宝箱の行が2つある", "chest_rewards.csv", "ruins_f1_chest_a",
			[_op_append("chest_rewards.csv", {"event_id": "ruins_f1_chest_a", "gold": "0", "item_id": "herb", "quantity": "1"})]))
	cases.append(_case("イベント: 宝箱でないイベントに報酬がある", "chest_rewards.csv", "ruins_f1_door",
			[_op_append("chest_rewards.csv", {"event_id": "ruins_f1_door", "gold": "5", "item_id": "", "quantity": "0"})]))
	cases.append(_case("イベント: 会話碑に文章IDがない", "floor_events.csv", "ruins_f1_inscription",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_inscription"}, {"text_id": ""})]))
	cases.append(_case("イベント: ボスの敵がボスでない", "floor_events.csv", "ruins_f3_boss",
			[_op_set("floor_events.csv", {"event_id": "ruins_f3_boss"}, {"enemy_id": "slime"})]))
	cases.append(_case("イベント: ボスに敵がない", "floor_events.csv", "ruins_f3_boss",
			[_op_set("floor_events.csv", {"event_id": "ruins_f3_boss"}, {"enemy_id": ""})]))
	cases.append(_case("イベント: 魔法陣に向きがない", "floor_events.csv", "warp_depths",
			[_op_set("floor_events.csv", {"event_id": "warp_depths"}, {"link_facing": ""})]))
	cases.append(_case("イベント: 魔法陣にIDがない", "floor_events.csv", "warp_depths",
			[_op_set("floor_events.csv", {"event_id": "warp_depths"}, {"warp_id": ""})]))
	cases.append(_case("イベント: 扉に表にない欄がある", "floor_events.csv", "ruins_f1_door",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_door"}, {"enemy_id": "slime"})]))
	cases.append(_case("イベント: 種類が列挙にない", "floor_events.csv", "ruins_f1_door",
			[_op_set("floor_events.csv", {"event_id": "ruins_f1_door"}, {"kind": "trapdoor"})]))
	# 文章（DAT-909）。行を消す注入は、manifest.csv の件数も合わせる
	cases.append(_case("文章: IDが重複する", "texts.csv", "intro",
			[_op_append("texts.csv", {"id": "intro", "text": "重複"})]))
	cases.append(_case("文章: 本文が空", "texts.csv", "save_done",
			[_op_set("texts.csv", {"id": "save_done"}, {"text": ""})]))
	cases.append(_case("文章: 波括弧の名前が定めた名前でない", "texts.csv", "rescue_confirm",
			[_op_set("texts.csv", {"id": "rescue_confirm"}, {"text": "所持金{money}Gを渡します。"})]))
	cases.append(_case("文章: 波括弧が閉じていない", "texts.csv", "rescue_confirm",
			[_op_set("texts.csv", {"id": "rescue_confirm"}, {"text": "所持金{gold"})]))
	cases.append(_case("文章: 必須の文章がない（導入）", "texts.csv", "intro",
			[_op_remove("texts.csv", {"id": "intro"})]))
	cases.append(_case("文章: 必須の文章がない（確認文）", "texts.csv", "guild_train_confirm",
			[_op_remove("texts.csv", {"id": "guild_train_confirm"})]))
	cases.append(_case("文章: 必須の文章がない（保存）", "texts.csv", "save_failed",
			[_op_remove("texts.csv", {"id": "save_failed"})]))
	cases.append(_case("文章: 必須の文章がない（起動エラー）", "texts.csv", "boot_error",
			[_op_remove("texts.csv", {"id": "boot_error"})]))
	cases.append(_case("文章: 必須の文章がない（会話碑）", "texts.csv", "insc_ruins_f1",
			[_op_remove("texts.csv", {"id": "insc_ruins_f1"})]))
	cases.append(_case("文章: 必須の文章がない（ボス前）", "texts.csv", "boss_gatekeeper_pre",
			[_op_remove("texts.csv", {"id": "boss_gatekeeper_pre"})]))
	cases.append(_case("文章: 必須の文章がない（ボス初回撃破）", "texts.csv", "boss_gatekeeper_first",
			[_op_remove("texts.csv", {"id": "boss_gatekeeper_first"})]))
	cases.append(_case("文章: 必須の文章がない（エラーコード）", "texts.csv", "error_no_gold",
			[_op_remove("texts.csv", {"id": "error_no_gold"})]))
	cases.append(_case("文章: 必須の文章がない（エラーコード。複数語）", "texts.csv", "error_no_living_member",
			[_op_remove("texts.csv", {"id": "error_no_living_member"})]))
	return cases


func _case(label: String, file: String, id: String, ops: Array) -> Dictionary:
	return {"label": label, "file": file, "id": id, "ops": ops}


## 一致する行（`match_row` の全列が一致）の列を書き換える
func _op_set(file: String, match_row: Dictionary, values: Dictionary) -> Dictionary:
	return {"op": "set", "file": file, "match": match_row, "values": values}


## 一致する行を消す。`manifest.csv` の件数も合わせる
func _op_remove(file: String, match_row: Dictionary) -> Dictionary:
	return {"op": "remove", "file": file, "match": match_row}


## 行を末尾へ足す。`manifest.csv` の件数も合わせる
func _op_append(file: String, row: Dictionary) -> Dictionary:
	return {"op": "append", "file": file, "row": row}


## 注入を1つ適用する。書き換えた（消した・足した）行数を返す
func _apply(op: Dictionary) -> int:
	var path := "%s/%s" % [TMP_DIR, op["file"]]
	var table := _read_csv_table(path)
	var header: PackedStringArray = table["header"]
	var rows: Array = table["rows"]
	var changed := 0
	match op["op"]:
		"set":
			for row in rows:
				if _row_matches(header, row, op["match"]):
					for column in op["values"]:
						row[header.find(column)] = op["values"][column]
					changed += 1
		"remove":
			var kept: Array = []
			for row in rows:
				if _row_matches(header, row, op["match"]):
					changed += 1
				else:
					kept.append(row)
			rows = kept
		"append":
			var added := PackedStringArray()
			for column in header:
				added.append(op["row"].get(column, ""))
			rows.append(added)
			changed = 1
	_write_csv_table(path, header, rows)
	if op["op"] != "set" and changed > 0:
		_adjust_manifest_count(op["file"], changed if op["op"] == "append" else -changed)
	return changed


func _adjust_manifest_count(file: String, delta: int) -> void:
	var path := "%s/manifest.csv" % TMP_DIR
	var table := _read_csv_table(path)
	var header: PackedStringArray = table["header"]
	for row in table["rows"]:
		if row[header.find("key")] == file:
			row[header.find("value")] = str(int(row[header.find("value")]) + delta)
	_write_csv_table(path, header, table["rows"])


func _row_matches(header: PackedStringArray, row: PackedStringArray, match_row: Dictionary) -> bool:
	for column in match_row:
		if row[header.find(column)] != match_row[column]:
			return false
	return true


## CSVを {header, rows} として読む。行は PackedStringArray
func _read_csv_table(path: String) -> Dictionary:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	var header := f.get_csv_line()
	while not f.eof_reached():
		var cells := f.get_csv_line()
		if cells.size() == 1 and cells[0] == "":
			continue
		rows.append(cells)
	return {"header": header, "rows": rows}


func _write_csv_table(path: String, header: PackedStringArray, rows: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_csv_line(header)
	for row in rows:
		f.store_csv_line(row)


## `res://data` の全CSVを、`user://` 配下の置き場所へ複写する（開発者の `data/` を変えない）
func _copy_data() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	for file in DirAccess.get_files_at(DATA_DIR):
		if file.ends_with(".csv"):
			var out := FileAccess.open("%s/%s" % [TMP_DIR, file], FileAccess.WRITE)
			out.store_buffer(FileAccess.get_file_as_bytes("%s/%s" % [DATA_DIR, file]))


func _remove_data_copy() -> void:
	for file in DirAccess.get_files_at(TMP_DIR):
		DirAccess.remove_absolute("%s/%s" % [TMP_DIR, file])
	DirAccess.remove_absolute(TMP_DIR)


## 複写からロードし、成功か・ログへ出た行・データベースが記録した問題を返す
func _load_copy() -> Dictionary:
	var db = load(DB_SCRIPT).new()
	var log_lines: Array = []
	var ok: bool = db.load_and_validate(TMP_DIR, func(line: String) -> void: log_lines.append(line))
	var errors: Array = Array(db.errors)
	db.free()
	return {"ok": ok, "log": log_lines, "errors": errors}


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
