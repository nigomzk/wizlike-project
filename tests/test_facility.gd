extends RefCounted
## TST-405: 施設・経済・日数・ボス復活・クエスト（F, Q）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"]

# 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、実行時に `load` で読む
const DB_SCRIPT := "res://scripts/core/game_database.gd"
const FACILITY_SCRIPT := "res://scripts/services/facility_service.gd"
const GAME_FLOW_SCRIPT := "res://scripts/core/game_flow.gd"
const SESSION_SCRIPT := "res://scripts/core/game_session.gd"
const RNG_SERVICE_SCRIPT := "res://scripts/services/rng_service.gd"
const DATA_DIR := "res://data"
const NEW_GAME_CSV := "res://data/new_game.csv"
## F07, F08 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const F07_TMP_ROOT := "user://test_facility_f07"
const F08_TMP_ROOT := "user://test_facility_f08"
const F08_REGISTER_TMP_ROOT := "user://test_facility_f08_register"
## 街の操作（FLW-004）。ギルドとタイトルへだけが、登録者が0人でも選べる（TWN-112）
const TOWN_ACTIONS: Array[StringName] = [&"guild", &"temple", &"shop", &"inn", &"tavern", &"departure", &"menu", &"save", &"title"]
const TOWN_ALWAYS_AVAILABLE: Array[StringName] = [&"guild", &"title"]
## 遷移先の状態名（GameFlow.State）。タイトルへは TITLE、ほかの施設は FACILITY
const TOWN_DESTINATIONS := {
	&"guild": "FACILITY", &"temple": "FACILITY", &"shop": "FACILITY", &"inn": "FACILITY", &"tavern": "FACILITY",
	&"departure": "DEPARTURE", &"menu": "MENU", &"save": "SAVE",
}
const LOCKED := &"LOCKED"
## GLS-200: 乱数の系列
const RNG_SERIES: Array[StringName] = [&"encounter", &"battle", &"loot", &"creation"]
## F08 が注入する seed
const RNG_SEEDS := {&"encounter": 11, &"battle": 22, &"loot": 33, &"creation": 44}


## `GameSession.changed` の通知を記録する。通知を受けた時点の未保存フラグも記録する。
class ChangeRecorder extends RefCounted:
	var session
	var kinds: Array = []
	var dirty_at_notice: Array = []

	func on_changed(kind: StringName) -> void:
		kinds.append(kind)
		dirty_at_notice.append(session.dirty)


func run(t) -> void:
	_f07(t)
	_f08(t)
	_f08_register(t)


# F07: ニューゲーム直後、登録者0人の状態で各施設・出発・セーブ・メニューを試みる（TWN-110, TWN-111, TWN-112, FLW-110）
# ギルドとタイトルへ戻る操作のみ選択できる。1人登録すると解除される。登録は `FacilityService` で行う。
func _f07(t) -> void:
	var env := _make_flow(t, F07_TMP_ROOT)
	var flow: Node = env.flow
	var s = env.script.State
	t.check("F07", true, flow.new_game())
	t.check("F07", true, flow.go_town())
	t.check("F07", s.TOWN, flow.state)
	var session = flow.session
	t.check("F07", 0, session.characters.size())

	# 登録者が0人の間は、ギルドとタイトルへだけが選べる。ほかは `LOCKED` で、選んでも遷移しない
	t.check("F07", true, flow.is_town_restricted())
	for action in TOWN_ACTIONS:
		var open: bool = TOWN_ALWAYS_AVAILABLE.has(action)
		var checked: Dictionary = flow.check_town_action(action)
		t.check("F07", open, checked.ok)
		t.check("F07", &"" if open else LOCKED, checked.error_code)
		if open:
			continue
		var selected: Dictionary = flow.select_town_action(action)
		t.check("F07", false, selected.ok)
		t.check("F07", LOCKED, selected.error_code)
		t.check("F07", s.TOWN, flow.state)
	t.check("F07", false, session.dirty)

	# 登録に失敗しても、制限は解除されない（TWN-111）
	var service = load(FACILITY_SCRIPT).new(env.db)
	t.check("F07", false, service.register(session, "", &"warrior", "portrait_01").ok)
	t.check("F07", true, flow.is_town_restricted())
	t.check("F07", false, flow.check_town_action(&"menu").ok)

	# 最初の1人を登録すると解除される。すべての項目が選べて、遷移先へ進み、戻れる（TWN-111, FLW-110）
	var registered: Dictionary = service.register(session, "アリス", &"warrior", "portrait_01")
	t.check("F07", true, registered.ok)
	t.check("F07", false, flow.is_town_restricted())
	for action in TOWN_ACTIONS:
		var checked: Dictionary = flow.check_town_action(action)
		t.check("F07", true, checked.ok)
		t.check("F07", &"", checked.error_code)
	for action in TOWN_DESTINATIONS:
		t.check("F07", true, flow.select_town_action(action).ok)
		t.check("F07", s[TOWN_DESTINATIONS[action]], flow.state)
		t.check("F07", true, flow.go_back())
		t.check("F07", s.TOWN, flow.state)
	t.check("F07", true, flow.select_town_action(&"title").ok)
	t.check("F07", s.TITLE, flow.state)
	t.check("F07", false, flow.has_session())

	_free_env(t, env)
	_remove_dir(F07_TMP_ROOT)


# F08: ニューゲームを開始し、続けて1人登録する（TWN-001, TWN-002, TWN-003, TWN-004, TWN-005, TWN-006, FLW-304）
# この関数は、ニューゲーム直後の状態までを判定する。登録しても所持金と所持品が増えないことは、`_f08_register` で確かめる。
func _f08(t) -> void:
	var expected := _read_new_game(NEW_GAME_CSV)
	# 期待値は data/new_game.csv から読む。読めていなければ、以降の判定が空振りする
	t.check("F08", true, expected.gold > 0 and not expected.items.is_empty())

	var db = load(DB_SCRIPT).new()
	t.check("F08", true, db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))
	var flow_script := load(GAME_FLOW_SCRIPT) as GDScript
	var flow: Node = flow_script.new()
	flow.save_dir = F08_TMP_ROOT + "/saves"
	flow.settings_path = F08_TMP_ROOT + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool) -> void: pass
	flow.database = db
	var rng = load(RNG_SERVICE_SCRIPT).new()
	rng.seed_all(RNG_SEEDS)
	flow.rng_service = rng
	t.root.add_child(flow)

	# TITLE の間はセッションがない。「はじめから」で NEW_GAME に入る時点で、導入の表示より前に作る（FLW-002, FLW-108）
	t.check("F08", flow_script.State.TITLE, flow.state)
	t.check("F08", false, flow.has_session())

	var states_before := _rng_states(rng)
	t.check("F08", true, flow.new_game())
	t.check("F08", true, flow.has_session())
	t.check("F08", flow_script.State.NEW_GAME, flow.state)
	# NEW_GAME からは作り直せない
	t.check("F08", false, flow.new_game())
	var session = flow.session
	t.check("F08", true, session != null and session.get_script() == load(SESSION_SCRIPT))
	if session == null:
		_free_flow(t, flow, db)
		return

	# TWN-001: ゲーム日数は1
	t.check("F08", 1, session.day)
	# TWN-002: 所持金は new_game.csv の gold 行
	t.check("F08", expected.gold, session.gold)
	# TWN-003: 所持品は new_game.csv の item 行。それ以外は持たない
	var owned := {}
	for stack in session.inventory:
		owned[String(stack.item_id)] = owned.get(String(stack.item_id), 0) + stack.quantity
	t.check("F08", expected.items, owned)
	# TWN-004: 登録者とパーティは空。次の冒険者IDは1（GLS-403）
	t.check("F08", 0, session.characters.size())
	t.check("F08", 0, session.party_ids.size())
	t.check("F08", 1, session.next_character_id)
	# TWN-005: 探索記録、イベント、クエスト、ボスの撃破記録、魔法陣が未開始
	t.check("F08", 0, session.floors.size())
	t.check("F08", 0, session.quests.size())
	t.check("F08", 0, session.first_defeated_boss_ids.size())
	t.check("F08", 0, session.boss_last_defeated_day.size())
	t.check("F08", 0, session.unlocked_warp_ids.size())
	t.check("F08", "", session.last_visited_floor_id)
	t.check("F08", null, session.exploration)
	t.check("F08", 0, session.important_items.size())
	# クリアフラグと未保存フラグはともに偽（FLW-304）
	t.check("F08", false, session.cleared)
	t.check("F08", false, session.dirty)

	# 渡した RngService をそのまま保持する。作成で、どの系列も引かない（GLS-203）
	t.check("F08", true, session.rng == rng)
	t.check("F08", states_before, _rng_states(rng))

	# session_id はニューゲームごとに一意で、系列を引かない（GLS-203）
	t.check("F08", true, session.session_id != "")
	var another = load(SESSION_SCRIPT).create_new(db, rng)
	t.check("F08", true, another != null)
	if another != null:
		t.check("F08", true, another.session_id != session.session_id)
		t.check("F08", false, another.dirty)
	t.check("F08", states_before, _rng_states(rng))

	# 状態の変更が成功したときにだけ、通知して未保存フラグを立てる（ARC-205, FLW-304）。
	# 通知を呼んでいない間は、フラグは偽のまま
	var recorder := ChangeRecorder.new()
	recorder.session = session
	session.changed.connect(recorder.on_changed)
	t.check("F08", 0, recorder.kinds.size())
	t.check("F08", false, session.dirty)
	session.notify_changed(&"gold")
	t.check("F08", [&"gold"], recorder.kinds)
	t.check("F08", true, session.dirty)
	# 通知を受けた時点で、フラグは立っている
	t.check("F08", [true], recorder.dirty_at_notice)
	# 受け手がセッションを持つと参照が循環するため、終わったら切り離す
	session.changed.disconnect(recorder.on_changed)

	_free_flow(t, flow, db)
	_remove_dir(F08_TMP_ROOT)


# F08（続き）：ニューゲームの直後に1人登録しても、所持金と所持品が増えない（TWN-006, PTY-000, INV-101, FLW-304）
func _f08_register(t) -> void:
	var expected := _read_new_game(NEW_GAME_CSV)
	var env := _make_flow(t, F08_REGISTER_TMP_ROOT)
	var flow: Node = env.flow
	t.check("F08", true, flow.new_game())
	t.check("F08", true, flow.go_town())
	var session = flow.session
	var service = load(FACILITY_SCRIPT).new(env.db)
	var recorder := ChangeRecorder.new()
	recorder.session = session
	session.changed.connect(recorder.on_changed)

	# 失敗した登録では、通知も未保存フラグもない（FLW-304）
	t.check("F08", false, service.register(session, "   ", &"mage", "portrait_02").ok)
	t.check("F08", false, session.dirty)
	t.check("F08", 0, recorder.kinds.size())

	var result: Dictionary = service.register(session, "  ミナ ", &"mage", "portrait_02")
	t.check("F08", true, result.ok)
	t.check("F08", &"", result.error_code)
	# 登録者は1人、パーティは登録者のIDだけ（PTY-013）。次のIDは2（GLS-403）
	t.check("F08", 1, session.characters.size())
	t.check("F08", "ミナ", session.characters[0].name)
	t.check("F08", [session.characters[0].id], session.party_ids)
	t.check("F08", 1, session.characters[0].id)
	t.check("F08", 2, session.next_character_id)
	# 所持金と所持品は、ニューゲームのときのまま。登録で支給しない（TWN-006）。初期装備は所持品を通さない（INV-101）
	t.check("F08", expected.gold, session.gold)
	var owned := {}
	for stack in session.inventory:
		owned[String(stack.item_id)] = owned.get(String(stack.item_id), 0) + stack.quantity
	t.check("F08", expected.items, owned)
	# ほかの状態は、開始直後のまま
	t.check("F08", 1, session.day)
	t.check("F08", 0, session.floors.size())
	t.check("F08", 0, session.quests.size())
	t.check("F08", 0, session.first_defeated_boss_ids.size())
	t.check("F08", 0, session.unlocked_warp_ids.size())
	t.check("F08", false, session.cleared)
	# 成功したので、通知を1回送り、受けた時点で未保存フラグが立っている（ARC-205, FLW-304）
	t.check("F08", 1, recorder.kinds.size())
	t.check("F08", [true], recorder.dirty_at_notice)
	t.check("F08", true, session.dirty)
	# 登録者が入ったので、街の制限が解除される（TWN-111）
	t.check("F08", false, flow.is_town_restricted())

	session.changed.disconnect(recorder.on_changed)
	_free_env(t, env)
	_remove_dir(F08_REGISTER_TMP_ROOT)


## 起動前の GameFlow を作る。データベースとセッションの乱数系列は、テスト用に作る（TST-100, TST-107）。
func _make_flow(t, tmp_root: String) -> Dictionary:
	var db = load(DB_SCRIPT).new()
	db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass)
	var flow_script := load(GAME_FLOW_SCRIPT) as GDScript
	var flow: Node = flow_script.new()
	flow.save_dir = tmp_root + "/saves"
	flow.settings_path = tmp_root + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool) -> void: pass
	flow.database = db
	var rng = load(RNG_SERVICE_SCRIPT).new()
	rng.seed_all(RNG_SEEDS)
	flow.rng_service = rng
	t.root.add_child(flow)
	return {"flow": flow, "db": db, "script": flow_script}


func _free_env(t, env: Dictionary) -> void:
	_free_flow(t, env.flow, env.db)


## data/new_game.csv を読む。`gold` 行の値と、`item` 行のアイテムID -> 数量。
func _read_new_game(path: String) -> Dictionary:
	var result := {"gold": 0, "items": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3:
			continue
		if row[0] == "gold":
			result.gold = int(row[2])
		elif row[0] == "item":
			result.items[row[1]] = result.items.get(row[1], 0) + int(row[2])
	return result


## 4系列それぞれの state。系列を消費したかどうかの比較に使う。
func _rng_states(rng) -> Dictionary:
	var states := {}
	for id in RNG_SERIES:
		states[id] = rng.series(id).state
	return states


func _free_flow(t, flow: Node, db: Node) -> void:
	t.root.remove_child(flow)
	flow.free()
	db.free()


func _remove_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		_remove_dir(dir_path + "/" + sub)
	DirAccess.remove_absolute(dir_path)
