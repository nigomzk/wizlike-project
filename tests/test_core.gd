extends RefCounted
## TST-409: 構成と共通サービス（A）のテスト。

const IDS := ["A01", "A02", "A03", "A04", "A05", "A06", "A07"]

const MAIN_SCENE := "res://scenes/main.tscn"
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、実行時に `load` で読む
const RNG_SERVICE_SCRIPT := "res://scripts/services/rng_service.gd"
const FACILITY_SCRIPT := "res://scripts/services/facility_service.gd"
const SESSION_SCRIPT := "res://scripts/core/game_session.gd"
const DB_SCRIPT := "res://scripts/core/game_database.gd"
const GAME_FLOW_SCRIPT := "res://scripts/core/game_flow.gd"
const RULES_SCRIPT := "res://scripts/rules/inventory_rules.gd"
const DATA_DIR := "res://data"
## GLS-200: 乱数の系列
const RNG_SERIES: Array[StringName] = [&"encounter", &"battle", &"loot", &"creation"]
## A02 が系列ごとに注入する seed。系列で異なる値にする
const RNG_SEEDS := {&"encounter": 1001, &"battle": 2002, &"loot": 3003, &"creation": 4004}
## A03, A04, A05 が注入する seed。A02 とは別の値にする
const GROWTH_SEEDS := {&"encounter": 5005, &"battle": 6006, &"loot": 7007, &"creation": 8008}
## ARC-401: エラーコードは、この11個に限る
const ERROR_CODES: Array[StringName] = [
	&"NO_GOLD", &"NO_SPACE", &"INVALID_TARGET", &"PARTY_EMPTY", &"PARTY_FULL", &"ROSTER_FULL",
	&"INVALID_NAME", &"NO_LIVING_MEMBER", &"ALREADY_LEARNED", &"LOCKED", &"INVALID_SAVE",
]
## ARC-400: サービスの結果のキー（並べ替えた順）
const RESULT_KEYS := ["changes", "error_code", "ok"]
## A03 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const A03_TMP_ROOT := "user://test_core_a03"
const ALLOWED_AUTOLOADS := ["GameDatabase", "SaveService"]
const GAME_THEME := "res://scenes/ui/components/game_theme.tres"
const SCENES_DIR := "res://scenes"
const UI_SCRIPTS_DIR := "res://scripts/ui"
## 0件で合格してしまわないよう、走査に必ず含まれるべきシーン
const KNOWN_SCENES := ["res://scenes/ui/title.tscn", "res://scenes/ui/placeholder.tscn"]
## 画面のスクリプトに現れてはならない語（ARC-208）
const FORBIDDEN_SCRIPT_WORDS := ["add_theme_", "theme_override"]
## A07 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const A07_TMP_ROOT := "user://test_core_a07"


## エンジンが出したエラー（push_error を含む）の件数を数える。A07 で、同じシグナルへの二重の結線を検出するため。
## `_log_error` は複数のスレッドから呼ばれうるため、`Mutex` で守る。
class EngineErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var _count := 0

	func _log_error(
			_function: String,
			_file: String,
			_line: int,
			_code: String,
			_rationale: String,
			_editor_notify: bool,
			error_type: int,
			_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_ERROR:
			return
		_mutex.lock()
		_count += 1
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var n := _count
		_mutex.unlock()
		return n


func run(t) -> void:
	_a01(t)
	_a02(t)
	_a03(t)
	_a04(t)
	_a05(t)
	_a06(t)
	await _a07(t)


# A01: main.tscn をインスタンス化する（ARC-003, 200, 201）
func _a01(t) -> void:
	t.check("A01", MAIN_SCENE, ProjectSettings.get_setting("application/run/main_scene", ""))

	var packed := load(MAIN_SCENE) as PackedScene
	t.check("A01", true, packed != null)
	if packed == null:
		return
	var root := packed.instantiate()
	t.check("A01", "Node", root.get_class())

	var expected_children := {
		"GameFlow": "Node",
		"ScreenHost": "Control",
		"DungeonHost": "Node3D",
		"ModalHost": "CanvasLayer",
		"AudioHost": "Node",
	}
	for child_name in expected_children:
		var child := root.get_node_or_null(NodePath(child_name))
		t.check("A01", true, child != null)
		if child != null:
			t.check("A01", expected_children[child_name], child.get_class())
	t.check("A01", expected_children.size(), root.get_child_count())

	# ScreenHost は全面アンカー
	var screen_host := root.get_node_or_null("ScreenHost") as Control
	if screen_host != null:
		t.check("A01", [0.0, 0.0, 1.0, 1.0],
			[screen_host.anchor_left, screen_host.anchor_top, screen_host.anchor_right, screen_host.anchor_bottom])
	root.free()

	# Autoload は GameDatabase と SaveService の範囲に収まる
	var autoloads: Array = []
	for property in ProjectSettings.get_property_list():
		var name_: String = property.name
		if name_.begins_with("autoload/"):
			autoloads.append(name_.trim_prefix("autoload/"))
	var outside := autoloads.filter(func(n): return not ALLOWED_AUTOLOADS.has(n))
	t.check("A01", [], outside)


# A02: 系列ごとに同じseedを注入した RngService を2つ作り、同じ順に引く（GLS-200, GLS-204, ARC-404, TST-102）
func _a02(t) -> void:
	var service_script := load(RNG_SERVICE_SCRIPT) as GDScript
	t.check("A02", true, service_script != null)
	if service_script == null:
		return
	# 系列は4つ（GLS-200）
	t.check("A02", RNG_SERIES, service_script.SERIES)

	var first = service_script.new()
	var second = service_script.new()
	for id in RNG_SERIES:
		t.check("A02", true, first.seed_series(id, RNG_SEEDS[id]))
		t.check("A02", true, second.seed_series(id, RNG_SEEDS[id]))
		# seed を注入しただけでは引かない（GLS-204）。先頭の値は、同じseedの素の生成器と一致する
		var plain := RandomNumberGenerator.new()
		plain.seed = RNG_SEEDS[id]
		t.check("A02", plain.state, first.series(id).state)
		t.check("A02", plain.randi(), first.series(id).randi())
		# 引いた1回を戻して、同じ順で引き直す
		first.series(id).seed = RNG_SEEDS[id]

	# 系列ごとに、同じ順で引くと同じ値の列になる。系列の引き方（整数、実数、範囲）が混ざっても同じ
	for id in RNG_SERIES:
		t.check("A02", _draw(second.series(id)), _draw(first.series(id)))

	# 系列は互いに独立している。ある系列を引いても、他の系列の続きは変わらない（GLS-200）
	var reference = service_script.new()
	var disturbed = service_script.new()
	for id in RNG_SERIES:
		reference.seed_series(id, RNG_SEEDS[id])
		disturbed.seed_series(id, RNG_SEEDS[id])
	_draw(disturbed.series(&"battle"))
	for id in RNG_SERIES:
		if id != &"battle":
			t.check("A02", _draw(reference.series(id)), _draw(disturbed.series(id)))
	t.check("A02", false, reference.series(&"battle").state == disturbed.series(&"battle").state)

	# 1つの系列へ注入しても、他の系列のseedは変わらない
	var partial = service_script.new()
	var before: Dictionary = {}
	for id in RNG_SERIES:
		before[id] = partial.series(id).state
	partial.seed_series(&"loot", RNG_SEEDS[&"loot"])
	for id in RNG_SERIES:
		if id != &"loot":
			t.check("A02", before[id], partial.series(id).state)

	# まとめての注入。系列にない名前が1つでもあれば、何も変えない
	var bulk = service_script.new()
	t.check("A02", true, bulk.seed_all(RNG_SEEDS))
	for id in RNG_SERIES:
		var one_by_one := RandomNumberGenerator.new()
		one_by_one.seed = RNG_SEEDS[id]
		t.check("A02", _draw(one_by_one), _draw(bulk.series(id)))
	var untouched: int = bulk.series(&"battle").state
	t.check("A02", false, bulk.seed_all({&"battle": 1, &"no_such_series": 2}))
	t.check("A02", untouched, bulk.series(&"battle").state)
	t.check("A02", false, bulk.seed_series(&"no_such_series", 1))
	t.check("A02", null, bulk.series(&"no_such_series"))

	# 注入しないときは、作るたびにランダムな初期値になる（同じ値の列にならない）
	var random_a = service_script.new()
	var random_b = service_script.new()
	for id in RNG_SERIES:
		t.check("A02", false, random_a.series(id).state == random_b.series(id).state)
	random_a.seed_all(RNG_SEEDS)
	random_a.randomize_all()
	for id in RNG_SERIES:
		t.check("A02", false, random_a.series(id).seed == RNG_SEEDS[id])


## 系列から、種類の違う引き方で数回引いた値の列。
func _draw(rng: RandomNumberGenerator) -> Array:
	return [rng.randi(), rng.randf(), rng.randi_range(0, 5), rng.randi(), rng.randf()]


# A03: ある系列から引く。画面の開閉、一覧の操作、冒険者作成の途中キャンセルを行う（GLS-200, GLS-202, GLS-203, PTY-007）
func _a03(t) -> void:
	# 引いた系列以外のstateは変わらない
	for drawn in RNG_SERIES:
		var series_rng = load(RNG_SERVICE_SCRIPT).new()
		series_rng.seed_all(GROWTH_SEEDS)
		var before := _states(series_rng)
		series_rng.series(drawn).randi()
		var after := _states(series_rng)
		for id in RNG_SERIES:
			t.check("A03", id == drawn, before[id] != after[id])

	# 画面の開閉、一覧の操作、冒険者作成の途中キャンセルでは、どの系列のstateも変わらない
	var db = load(DB_SCRIPT).new()
	t.check("A03", true, db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))
	var flow: Node = load(GAME_FLOW_SCRIPT).new()
	flow.save_dir = A03_TMP_ROOT + "/saves"
	flow.settings_path = A03_TMP_ROOT + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool) -> void: pass
	flow.database = db
	var rng = load(RNG_SERVICE_SCRIPT).new()
	rng.seed_all(GROWTH_SEEDS)
	flow.rng_service = rng
	t.root.add_child(flow)
	var initial := _states(rng)
	t.check("A03", true, flow.new_game())
	t.check("A03", true, flow.go_town())
	var service = load(FACILITY_SCRIPT).new(db)
	var session = flow.session

	# 登録者0人の街：選べない項目の確認と選択を試し、ギルドを開いて閉じる
	for action in [&"guild", &"temple", &"shop", &"inn", &"tavern", &"departure", &"menu", &"save", &"title", &"no_such_action"]:
		flow.check_town_action(action)
	for action in [&"temple", &"menu", &"save", &"departure"]:
		flow.select_town_action(action)
	t.check("A03", true, flow.select_town_action(&"guild").ok)
	t.check("A03", true, flow.go_back())
	# 作成の途中キャンセル：確定の前の検証だけを繰り返し、確定しない。入力の誤りで拒否された操作も含む
	for raw in ["アリス", " ", "あ".repeat(13), "a\nb"]:
		service.can_register(session, raw, &"warrior", "portrait_01")
	t.check("A03", false, service.register(session, "", &"warrior", "portrait_01").ok)
	t.check("A03", false, service.register(session, "あ", &"no_such_job", "portrait_01").ok)
	t.check("A03", false, service.register(session, "あ", &"warrior", "no_such_portrait").ok)
	t.check("A03", initial, _states(rng))
	t.check("A03", 0, session.characters.size())
	t.check("A03", 1, session.next_character_id)

	# 確定した作成は、creation 系列から引く。ほかの系列は変わらない
	var reference := RandomNumberGenerator.new()
	reference.seed = GROWTH_SEEDS[&"creation"]
	reference.randi()
	t.check("A03", true, service.register(session, "アリス", &"warrior", "portrait_01").ok)
	var after_register := _states(rng)
	for id in RNG_SERIES:
		if id == &"creation":
			t.check("A03", reference.state, after_register[id])
			t.check("A03", false, initial[id] == after_register[id])
		else:
			t.check("A03", initial[id], after_register[id])

	# 登録後に、画面を開閉し、確認を繰り返し、20人まで埋めて拒否される操作を試みても、引かれない
	for action in [&"guild", &"temple", &"shop", &"inn", &"tavern", &"departure", &"menu", &"save"]:
		flow.check_town_action(action)
		t.check("A03", true, flow.select_town_action(action).ok)
		t.check("A03", true, flow.go_back())
	t.check("A03", after_register, _states(rng))
	for i in 19:
		service.register(session, "冒険者%d" % i, &"mage", "portrait_02")
	t.check("A03", 20, session.characters.size())
	var full := _states(rng)
	t.check("A03", false, service.register(session, "二十一人目", &"mage", "portrait_02").ok)
	service.can_register(session, "二十一人目", &"mage", "portrait_02")
	t.check("A03", full, _states(rng))

	t.root.remove_child(flow)
	flow.free()
	db.free()
	_remove_dir(A03_TMP_ROOT)


# A04: 同じseedで冒険者を同じ順に作成する（GLS-201, GLS-204, PTY-006）
func _a04(t) -> void:
	var db = load(DB_SCRIPT).new()
	t.check("A04", true, db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))
	var jobs: Array[StringName] = [&"warrior", &"knight", &"mage", &"priest", &"scout"]
	var runs: Array = []
	for run_index in 2:
		var rng = load(RNG_SERVICE_SCRIPT).new()
		rng.seed_all(GROWTH_SEEDS)
		var session = load(SESSION_SCRIPT).create_new(db, rng)
		var service = load(FACILITY_SCRIPT).new(db)
		var seeds: Array = []
		var other_states := _states(rng)
		other_states.erase(&"creation")
		for i in jobs.size():
			# 確定しない操作は引かない（GLS-204）。確定のときにだけ、1回引く
			var creation_before: int = rng.series(&"creation").state
			service.can_register(session, "あ", jobs[i], "portrait_01")
			service.register(session, "", jobs[i], "portrait_01")
			t.check("A04", creation_before, rng.series(&"creation").state)
			t.check("A04", true, service.register(session, "冒険者%d" % i, jobs[i], "portrait_01").ok)
			seeds.append(session.characters[i].growth_rng.seed)
		# 引いたのは creation 系列だけで、ほかの系列は変わらない
		var remaining := _states(rng)
		remaining.erase(&"creation")
		t.check("A04", other_states, remaining)
		runs.append({"seeds": seeds, "creation": rng.series(&"creation").state})

	# 2回の実行で、冒険者ごとの growth_rng の seed が一致する
	t.check("A04", runs[0].seeds, runs[1].seeds)
	t.check("A04", runs[0].creation, runs[1].creation)
	# seed は、creation 系列から確定のたびに1回ずつ引いた値（`randi()` を1回）。冒険者ごとに別の値になる
	var reference := RandomNumberGenerator.new()
	reference.seed = GROWTH_SEEDS[&"creation"]
	var expected: Array = []
	for i in jobs.size():
		expected.append(reference.randi())
	t.check("A04", expected, runs[0].seeds)
	t.check("A04", reference.state, runs[0].creation)
	var unique := {}
	for value in runs[0].seeds:
		unique[value] = true
	t.check("A04", jobs.size(), unique.size())

	# 冒険者ごとに独立している。一方から引いても、他方の続きは変わらない
	var rng2 = load(RNG_SERVICE_SCRIPT).new()
	rng2.seed_all(GROWTH_SEEDS)
	var session2 = load(SESSION_SCRIPT).create_new(db, rng2)
	var service2 = load(FACILITY_SCRIPT).new(db)
	service2.register(session2, "A", &"warrior", "portrait_01")
	service2.register(session2, "B", &"warrior", "portrait_01")
	var first_rng: RandomNumberGenerator = session2.characters[0].growth_rng
	var second_rng: RandomNumberGenerator = session2.characters[1].growth_rng
	var plain := RandomNumberGenerator.new()
	plain.seed = second_rng.seed
	var untouched_state: int = second_rng.state
	first_rng.randi()
	first_rng.randi()
	t.check("A04", untouched_state, second_rng.state)
	t.check("A04", plain.randi(), second_rng.randi())

	db.free()


# A05: ARC-401の全エラーコードとサービスの戻り値を確認する（ARC-400, ARC-401, ARC-402）
func _a05(t) -> void:
	var db = load(DB_SCRIPT).new()
	t.check("A05", true, db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))

	# 全コードについて、`error_` + 小文字のIDの文章がある。サービスは表示文言を持たない（ARC-402）
	t.check("A05", 11, ERROR_CODES.size())
	for code in ERROR_CODES:
		var text_id := StringName("error_" + String(code).to_lower())
		t.check("A05", true, db.has_text(text_id))
		t.check("A05", false, db.text(text_id) == "" or db.text(text_id) == String(text_id))
	# 名前の誤りの文言は、文字数の範囲を埋め込む
	var invalid_name: String = db.text(&"error_invalid_name", {"min": 1, "max": 12})
	t.check("A05", true, invalid_name.contains("1") and invalid_name.contains("12") and not invalid_name.contains("{"))

	# サービスの戻り値は `{ok, error_code, changes}` の形。成功は空の `error_code`、失敗は ARC-401 のコード
	var rng = load(RNG_SERVICE_SCRIPT).new()
	rng.seed_all(GROWTH_SEEDS)
	var session = load(SESSION_SCRIPT).create_new(db, rng)
	var service = load(FACILITY_SCRIPT).new(db)
	var rules = load(RULES_SCRIPT)
	var results: Array = []
	# FacilityService：成功、名前、職業と顔画像、上限
	results.append(service.can_register(session, "アリス", &"warrior", "portrait_01"))
	results.append(service.register(session, "アリス", &"warrior", "portrait_01"))
	results.append(service.can_register(session, "", &"warrior", "portrait_01"))
	results.append(service.register(session, "", &"warrior", "portrait_01"))
	results.append(service.register(session, "アリス", &"no_such_job", "portrait_01"))
	results.append(service.register(session, "アリス", &"warrior", "portrait_99"))
	for i in 19:
		results.append(service.register(session, "冒険者%d" % i, &"mage", "portrait_02"))
	results.append(service.register(session, "二十一人目", &"mage", "portrait_02"))
	results.append(service.can_register(session, "二十一人目", &"mage", "portrait_02"))
	# InventoryRules：成功、容量の不足、所持していない品の削除、存在しない品の装備
	var herb := ItemStackDef.new()
	herb.item_id = &"herb"
	herb.quantity = 1
	var heap := ItemStackDef.new()
	heap.item_id = &"herb"
	heap.quantity = 9 * 31
	results.append(rules.plan_transaction(db, session.inventory, [herb], []))
	results.append(rules.plan_transaction(db, session.inventory, [heap], []))
	results.append(rules.plan_transaction(db, session.inventory, [], [heap]))
	results.append(rules.plan_equip(db, session.inventory, session.characters[0], &"weapon", &"no_such_item"))
	# GameFlow：街の操作の可否と選択
	var flow: Node = load(GAME_FLOW_SCRIPT).new()
	flow.database = db
	flow.rng_service = rng
	results.append(flow.check_town_action(&"guild"))
	results.append(flow.check_town_action(&"no_such_action"))
	results.append(flow.select_town_action(&"guild"))
	flow.free()

	var codes_seen := {}
	for result in results:
		var keys: Array = result.keys()
		keys.sort()
		t.check("A05", RESULT_KEYS, keys)
		t.check("A05", TYPE_BOOL, typeof(result.ok))
		t.check("A05", TYPE_STRING_NAME, typeof(result.error_code))
		t.check("A05", TYPE_DICTIONARY, typeof(result.changes))
		if result.ok:
			t.check("A05", &"", result.error_code)
		else:
			t.check("A05", true, ERROR_CODES.has(result.error_code))
			t.check("A05", {}, result.changes)
			codes_seen[result.error_code] = true
	# 上の操作で、主要なコードを実際に返している（形だけの検査で終わらせない）
	for code in [&"INVALID_NAME", &"INVALID_TARGET", &"ROSTER_FULL", &"NO_SPACE", &"LOCKED"]:
		t.check("A05", true, codes_seen.has(code))

	db.free()


## 4系列それぞれの state。系列を消費したかどうかの比較に使う。
func _states(rng) -> Dictionary:
	var states := {}
	for id in RNG_SERIES:
		states[id] = rng.series(id).state
	return states


# A06: 画面のシーンとスクリプトが、見た目を共通Theme と Type Variation だけで決めている（ARC-208, PRS-300）
func _a06(t) -> void:
	t.check("A06", GAME_THEME, ProjectSettings.get_setting("gui/theme/custom", ""))
	var theme := load(GAME_THEME) as Theme
	t.check("A06", true, theme != null)
	if theme == null:
		return
	# 共通Theme は SceneTree ができる前に読み込まれるため、スクリプトを持つリソースを入れない（ARC-208）
	t.check("A06", [], _scripted_theme_items(theme))
	# 判定そのものが見逃さないことを、スクリプトを持つ StyleBox を1つ入れた Theme で確かめる
	var scripted := GDScript.new()
	scripted.source_code = "extends StyleBoxEmpty\n"
	t.check("A06", OK, scripted.reload())
	var scripted_box := StyleBoxEmpty.new()
	scripted_box.set_script(scripted)
	var bad_theme := Theme.new()
	bad_theme.set_stylebox(&"panel", &"PanelContainer", scripted_box)
	t.check("A06", ["PanelContainer/styles/panel"], _scripted_theme_items(bad_theme))
	# 項目の先の依存（フォントの base_font）にあるスクリプトも見逃さない
	var scripted_font_script := GDScript.new()
	scripted_font_script.source_code = "extends FontVariation\n"
	t.check("A06", OK, scripted_font_script.reload())
	var scripted_font := FontVariation.new()
	scripted_font.set_script(scripted_font_script)
	var outer_font := FontVariation.new()
	outer_font.base_font = scripted_font
	var nested_theme := Theme.new()
	nested_theme.default_font = outer_font
	t.check("A06", ["default_font/base_font"], _scripted_theme_items(nested_theme))

	var scene_paths := _files_with_suffix(SCENES_DIR, ".tscn")
	for path in KNOWN_SCENES:
		t.check("A06", true, scene_paths.has(path))
	var violations: Array = []
	for path in scene_paths:
		var packed := load(path) as PackedScene
		t.check("A06", true, packed != null)
		if packed != null:
			violations.append_array(_theme_violations(packed, theme))
	t.check("A06", [], violations)

	var script_hits: Array = []
	for path in _files_with_suffix(UI_SCRIPTS_DIR, ".gd"):
		var source := FileAccess.get_file_as_string(path)
		for word in FORBIDDEN_SCRIPT_WORDS:
			if source.contains(word):
				script_hits.append("%s: %s" % [path, word])
	t.check("A06", [], script_hits)

	# 判定そのものが違反を見逃さないことを、違反を1つずつ持つシーンで確かめる
	var bad_root := Control.new()
	var with_override := Label.new()
	with_override.add_theme_font_size_override("font_size", 40)
	var with_theme := Control.new()
	with_theme.theme = Theme.new()
	var with_unknown_variation := Label.new()
	with_unknown_variation.theme_type_variation = &"NoSuchVariation"
	for child in [with_override, with_theme, with_unknown_variation]:
		bad_root.add_child(child)
		child.owner = bad_root
	var bad_scene := PackedScene.new()
	t.check("A06", OK, bad_scene.pack(bad_root))
	bad_root.free()
	t.check("A06", 3, _theme_violations(bad_scene, theme).size())


## Theme から保存されるプロパティをたどって届くリソース（項目、フォントの base_font や fallbacks などの入れ子を含む）のうち、
## スクリプトを持つものを、Theme からのプロパティのパス（例：PanelContainer/styles/panel、default_font/base_font）の一覧で返す（ARC-208）。
func _scripted_theme_items(theme: Theme) -> Array:
	var result: Array = []
	if theme.get_script() != null:
		result.append("(theme)")
	_collect_scripted(theme, "", {}, result)
	return result


func _collect_scripted(resource: Resource, path: String, visited: Dictionary, result: Array) -> void:
	if visited.has(resource):
		return
	visited[resource] = true
	for property in resource.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE) or property.name == "script":
			continue
		var value = resource.get(property.name)
		var children: Array = []
		if value is Resource:
			children = [value]
		elif value is Array:
			children = value.filter(func(v): return v is Resource)
		for child in children:
			var child_path: String = property.name if path == "" else path + "/" + property.name
			if child.get_script() != null:
				result.append(child_path)
			_collect_scripted(child, child_path, visited, result)


## シーンの中で、ARC-208 に反するプロパティを「ノードのパス: プロパティ名」の一覧で返す。
func _theme_violations(packed: PackedScene, theme: Theme) -> Array:
	var result: Array = []
	var known_types := theme.get_type_list()
	var state := packed.get_state()
	for node_idx in state.get_node_count():
		var node_path := String(state.get_node_path(node_idx))
		for prop_idx in state.get_node_property_count(node_idx):
			var prop_name := String(state.get_node_property_name(node_idx, prop_idx))
			if prop_name.begins_with("theme_override_") or prop_name == "theme":
				result.append("%s: %s" % [node_path, prop_name])
			elif prop_name == "theme_type_variation":
				var variation := String(state.get_node_property_value(node_idx, prop_idx))
				if not known_types.has(variation):
					result.append("%s: %s=%s" % [node_path, prop_name, variation])
	return result


## ディレクトリの下を再帰的にたどり、名前が suffix で終わるファイルの res:// パスを返す。
func _files_with_suffix(dir_path: String, suffix: String) -> Array:
	var result: Array = []
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(suffix):
			result.append(dir_path + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		result.append_array(_files_with_suffix(dir_path + "/" + sub, suffix))
	return result


# A07: マウスを動かして載せた項目へフォーカスが移る。動かさない場合と、入力の遮断中は移らない（ARC-209, FLW-200）
func _a07(t) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("A07", true, packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("A07", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	# 開発者の実際の設定とスロットに触れないよう、置き場所を差し替える（TST-107）
	flow.save_dir = A07_TMP_ROOT + "/saves"
	flow.settings_path = A07_TMP_ROOT + "/settings.cfg"
	t.root.add_child(main)
	# 初期フォーカスは遅延して置かれるため、1フレーム待つ
	await t.process_frame

	var buttons := _buttons(host.current_screen)
	t.check("A07", 4, buttons.size())
	if buttons.size() != 4:
		_free_main(t, main)
		return
	t.check("A07", true, buttons[0].has_focus())

	# 別の項目へマウスを動かすと、その項目へフォーカスが移る
	t.root.push_input(_mouse_motion_over(buttons[2], Vector2(4, 0)), true)
	t.check("A07", true, buttons[2].has_focus())
	t.root.push_input(_mouse_motion_over(buttons[3], Vector2(0, 4)), true)
	t.check("A07", true, buttons[3].has_focus())

	# カーソルが入った通知や、移動量のないマウスの移動だけでは、フォーカスは動かない
	buttons[1].mouse_entered.emit()
	t.check("A07", true, buttons[3].has_focus())
	t.root.push_input(_mouse_motion_over(buttons[1], Vector2.ZERO), true)
	t.check("A07", true, buttons[3].has_focus())

	# カーソルを「終了」の上に置いたまま、仮画面へ行って戻る。初期の選択は最初の項目のまま
	t.root.push_input(_mouse_motion_over(buttons[3], Vector2(4, 0)), true)
	t.check("A07", true, flow.open_settings())
	await t.process_frame
	t.check("A07", true, flow.go_back())
	await t.process_frame
	await t.process_frame
	buttons = _buttons(host.current_screen)
	t.check("A07", true, buttons[0].has_focus())
	t.check("A07", false, buttons[3].has_focus())

	# 入力の遮断中は、マウスを動かしてもフォーカスを移さない
	flow.block_input(&"modal")
	t.root.push_input(_mouse_motion_over(buttons[2], Vector2(4, 0)), true)
	t.check("A07", false, buttons[2].has_focus())
	buttons[2].mouse_entered.emit()
	t.check("A07", false, buttons[2].has_focus())
	flow.unblock_input(&"modal")
	t.check("A07", true, buttons[0].has_focus())

	# 画面の中の項目がツリーから外れて入り直しても、結線は1つのままで、マウスの移動でフォーカスが移る
	var item: Control = buttons[1]
	var items_parent := item.get_parent()
	var errors := EngineErrorCounter.new()
	OS.add_logger(errors)
	items_parent.remove_child(item)
	items_parent.add_child(item)
	items_parent.move_child(item, 1)
	OS.remove_logger(errors)
	t.check("A07", 0, errors.count())
	t.check("A07", 1, item.gui_input.get_connections().filter(func(c): return c.callable.get_object() == host).size())
	t.root.push_input(_mouse_motion_over(item, Vector2(4, 0)), true)
	t.check("A07", true, item.has_focus())

	_free_main(t, main)
	_remove_dir(A07_TMP_ROOT)


## 項目の中央へ、指定した移動量でマウスを動かしたイベント（ビューポートの座標）。
func _mouse_motion_over(control: Control, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.relative = relative
	return event


func _buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false)


func _free_main(t, main: Node) -> void:
	t.root.remove_child(main)
	main.free()


func _remove_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		_remove_dir(dir_path + "/" + sub)
	DirAccess.remove_absolute(dir_path)
