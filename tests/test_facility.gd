extends RefCounted
## TST-405: 施設・経済・日数・ボス復活・クエスト（F, Q）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"]

# 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、実行時に `load` で読む
const DB_SCRIPT := "res://scripts/core/game_database.gd"
const GAME_FLOW_SCRIPT := "res://scripts/core/game_flow.gd"
const SESSION_SCRIPT := "res://scripts/core/game_session.gd"
const RNG_SERVICE_SCRIPT := "res://scripts/services/rng_service.gd"
const DATA_DIR := "res://data"
const NEW_GAME_CSV := "res://data/new_game.csv"
## F08 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const F08_TMP_ROOT := "user://test_facility_f08"
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
	_f08(t)


# F08: ニューゲームを開始し、続けて1人登録する（TWN-001, TWN-002, TWN-003, TWN-004, TWN-005, TWN-006, FLW-304）
# 「1人登録しても所持金と所持品が増えない」部分は、登録を実装する #10 で確かめる。ここでは、ニューゲーム直後の状態までを判定する。
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
