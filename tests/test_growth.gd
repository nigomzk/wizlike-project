extends RefCounted
## TST-401: 冒険者の登録と編成・経験値と成長・その他（G, L, P）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["G01", "G02", "G03", "G04", "G05", "L01", "L02", "L03", "P01", "P02"]

# 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、実行時に `load` で読む
const DB_SCRIPT := "res://scripts/core/game_database.gd"
const SESSION_SCRIPT := "res://scripts/core/game_session.gd"
const RNG_SERVICE_SCRIPT := "res://scripts/services/rng_service.gd"
const FACILITY_SCRIPT := "res://scripts/services/facility_service.gd"
const RULES_SCRIPT := "res://scripts/rules/inventory_rules.gd"
const DATA_DIR := "res://data"
const JOBS_CSV := "res://data/jobs.csv"

## GLS-200: 乱数の系列
const RNG_SERIES: Array[StringName] = [&"encounter", &"battle", &"loot", &"creation"]
const RNG_SEEDS := {&"encounter": 101, &"battle": 202, &"loot": 303, &"creation": 404}
const STAT_FIELDS: Array[String] = ["hp", "sp", "str", "vit", "tec", "agi", "luc"]
const SLOTS: Array[StringName] = [&"weapon", &"armor", &"accessory"]

## PTY-000: 登録者の上限。PTY-013: パーティの上限。設計書の規則で、`data/` にはない
const ROSTER_LIMIT := 20
const PARTY_LIMIT := 4
## PTY-003: 名前の文字数
const NAME_MIN := 1
const NAME_MAX := 12
## PTY-005, DAT-522: 顔画像は10種
const PORTRAIT_COUNT := 10

const ROSTER_FULL := &"ROSTER_FULL"
const INVALID_NAME := &"INVALID_NAME"
const INVALID_TARGET := &"INVALID_TARGET"


## 通知（`changed`）を記録する。
class ChangeRecorder extends RefCounted:
	var kinds: Array = []

	func on_changed(kind: StringName) -> void:
		kinds.append(kind)


func run(t) -> void:
	_g01(t)
	_g02(t)
	_p01(t)


# G01: 20人登録した状態で21人目の作成を試みる（PTY-000, PTY-012, PTY-006, TWN-006, FLW-304, ARC-403）
func _g01(t) -> void:
	var world := _world()
	var service = world.service
	var session = world.session
	var recorder := ChangeRecorder.new()
	session.changed.connect(recorder.on_changed)
	var start_gold: int = session.gold
	var jobs := _read_jobs()
	t.check("G01", 5, jobs.size())

	# 20人までは登録できる。登録は無料（PTY-000）。IDは1から単調に増える（PTY-006, GLS-403）
	for i in ROSTER_LIMIT:
		var job: Dictionary = jobs[i % jobs.size()]
		# 登録の入口の可否は、名前などを決める前に、上限だけで確かめられる（PTY-012）。試算は何も変えない
		var entry: Dictionary = service.can_start_register(session)
		t.check("G01", true, entry.ok)
		t.check("G01", &"", entry.error_code)
		t.check("G01", i, session.characters.size())
		var result: Dictionary = service.register(session, "冒険者%d" % i, StringName(job.id), _portrait(i))
		t.check("G01", true, result.ok)
		t.check("G01", &"", result.error_code)
		t.check("G01", i + 1, result.changes.character_id)
	t.check("G01", ROSTER_LIMIT, session.characters.size())
	t.check("G01", start_gold, session.gold)
	var ids: Array = session.characters.map(func(c): return c.id)
	t.check("G01", range(1, ROSTER_LIMIT + 1), ids)
	t.check("G01", ROSTER_LIMIT + 1, session.next_character_id)
	t.check("G01", ROSTER_LIMIT, recorder.kinds.size())

	# 21人目は、`ROSTER_FULL` で拒否する。所持金・装備・IDの状態をいずれも変更しない（PTY-012, ARC-403）
	var before := _snapshot(session)
	var notices_before: int = recorder.kinds.size()
	var warrior := StringName(jobs[0].id)
	var entry_full: Dictionary = service.can_start_register(session)
	t.check("G01", false, entry_full.ok)
	t.check("G01", ROSTER_FULL, entry_full.error_code)
	t.check("G01", {}, entry_full.changes)
	var preview: Dictionary = service.can_register(session, "二十一人目", warrior, _portrait(0))
	t.check("G01", false, preview.ok)
	t.check("G01", ROSTER_FULL, preview.error_code)
	var rejected: Dictionary = service.register(session, "二十一人目", warrior, _portrait(0))
	t.check("G01", false, rejected.ok)
	t.check("G01", ROSTER_FULL, rejected.error_code)
	t.check("G01", {}, rejected.changes)
	t.check("G01", before, _snapshot(session))
	t.check("G01", notices_before, recorder.kinds.size())
	# 拒否の理由が名前の誤りでも、上限を超える登録は成立しない
	t.check("G01", false, service.register(session, "", warrior, _portrait(0)).ok)
	t.check("G01", before, _snapshot(session))

	session.changed.disconnect(recorder.on_changed)
	_free_world(world)


# G02: 全5職業を1人ずつ作成する（PTY-001, PTY-002, PTY-004, PTY-005, PTY-009, PTY-010, PTY-011, PTY-013, INV-101, GLS-201）
func _g02(t) -> void:
	var world := _world()
	var service = world.service
	var session = world.session
	var db = world.db
	var rules = load(RULES_SCRIPT)
	var jobs := _read_jobs()
	t.check("G02", 5, jobs.size())
	var inventory_before := _inventory_pairs(session)
	var slots_before: int = rules.slot_count(db, session.inventory)
	var start_gold: int = session.gold

	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var name_ := "冒険者%d" % i
		var result: Dictionary = service.register(session, name_, StringName(job.id), _portrait(i))
		t.check("G02", true, result.ok)
		var character = session.characters[i]
		t.check("G02", i + 1, character.id)
		t.check("G02", TYPE_INT, typeof(character.id))
		t.check("G02", name_, character.name)
		t.check("G02", job.id, String(character.job_id))
		t.check("G02", _portrait(i), character.portrait_id)
		# PTY-009: レベル1、HPとSPは満タン
		t.check("G02", 1, character.level)
		t.check("G02", 0, character.total_exp)
		t.check("G02", false, character.poison)
		# PTY-210: 初期能力は `data/jobs.csv` の `base_*` と一致する
		for field in STAT_FIELDS:
			t.check("G02", int(job["base_" + field]), character.base_stats.get(field))
		t.check("G02", int(job.base_hp), character.current_hp)
		t.check("G02", int(job.base_sp), character.current_sp)
		# PTY-010: 職業別の初期武器と布の服を装備済み。装飾品は支給しない
		t.check("G02", [job.starting_weapon_id, job.starting_armor_id, ""],
			SLOTS.map(func(slot): return String(character.equipment.get(slot, "?"))))
		# PTY-011: 初期スキルを習得済み。習得料金を要しない
		t.check("G02", [job.initial_skill_id], character.learned_skill_ids.map(func(s): return String(s)))
		# GLS-201: 冒険者ごとに独立した成長乱数を持つ
		t.check("G02", true, character.growth_rng != null)
		# 職業定義（固定データ）と能力値を共有しない（DAT-002）
		var definition: JobDef = db.job(StringName(job.id))
		t.check("G02", false, character.base_stats == definition.base_stats)
		character.base_stats.hp += 1
		t.check("G02", int(job.base_hp), definition.base_stats.hp)
		character.base_stats.hp -= 1

	# 装備は所持品枠に数えない。所持品は変わらない（INV-101）。所持金も変わらない（PTY-000）
	t.check("G02", inventory_before, _inventory_pairs(session))
	t.check("G02", slots_before, rules.slot_count(db, session.inventory))
	t.check("G02", start_gold, session.gold)
	# growth_rng は冒険者ごとに別のオブジェクト
	var rngs: Array = session.characters.map(func(c): return c.growth_rng)
	for i in rngs.size():
		for j in range(i + 1, rngs.size()):
			t.check("G02", false, rngs[i] == rngs[j])
	# PTY-013: パーティが4人未満であれば末尾へ加える。4人の場合は待機者とする
	t.check("G02", [1, 2, 3, 4], session.party_ids)

	# PTY-001, PTY-004: 同じ職業・同じ名前の冒険者を登録できる
	var first_job := StringName(jobs[0].id)
	t.check("G02", true, service.register(session, "冒険者0", first_job, _portrait(0)).ok)
	t.check("G02", true, service.register(session, "冒険者0", first_job, _portrait(0)).ok)
	t.check("G02", 7, session.characters.size())
	t.check("G02", [1, 2, 3, 4], session.party_ids)
	t.check("G02", 8, session.next_character_id)

	# PTY-002, PTY-005: 職業は定義にあるもの、顔画像は10種から選ぶ。それ以外は `INVALID_TARGET` で、何も変えない
	var before := _snapshot(session)
	for portrait in ["", "portrait_00", "portrait_%02d" % (PORTRAIT_COUNT + 1), "portrait_1", "face_01"]:
		var bad_portrait: Dictionary = service.register(session, "あ", first_job, portrait)
		t.check("G02", false, bad_portrait.ok)
		t.check("G02", INVALID_TARGET, bad_portrait.error_code)
	var bad_job: Dictionary = service.register(session, "あ", &"no_such_job", _portrait(0))
	t.check("G02", false, bad_job.ok)
	t.check("G02", INVALID_TARGET, bad_job.error_code)
	t.check("G02", before, _snapshot(session))
	# 全職業で同じ10種を選べる
	for job in jobs:
		for n in range(1, PORTRAIT_COUNT + 1):
			t.check("G02", true, service.can_register(session, "あ", StringName(job.id), "portrait_%02d" % n).ok)

	_free_world(world)


# P01: 名前に前後の空白、13文字、0文字、空白のみ、改行を含む文字列を入力する（PTY-003, PTY-004）
func _p01(t) -> void:
	var world := _world()
	var service = world.service
	var session = world.session
	var service_script := load(FACILITY_SCRIPT) as GDScript
	var job := &"warrior"
	var twelve := "あ".repeat(NAME_MAX)
	var thirteen := "あ".repeat(NAME_MAX + 1)
	t.check("P01", NAME_MAX, twelve.length())

	# 前後の空白（半角・全角）を除去して、1〜12文字かつ改行を含まない場合のみ受理する
	var accepted := {
		"a": "a",
		"  a  ": "a",
		"　a　": "a",
		" 　 a 　 ": "a",
		"\ta\t": "a",
		"a b": "a b",
		"a　b": "a　b",
		" a　b ": "a　b",
		twelve: twelve,
		" " + twelve + " ": twelve,
		"　" + twelve + "　": twelve,
		# 空白を除いて12文字ちょうど。除去した後の文字数で判定する
		"  " + twelve + "  ": twelve,
		"あ": "あ",
	}
	var rejected: Array = [
		"",
		" ",
		"   ",
		"　",
		"　　",
		" 　 　 ",
		"\t",
		thirteen,
		" " + thirteen + " ",
		"　" + thirteen + "　",
		"a\nb",
		"a\r\nb",
		"\n",
		"\r",
		"a\n",
		"\na",
		" a\nb ",
	]

	var registered := 0
	for raw in accepted:
		var expected: String = accepted[raw]
		t.check("P01", expected, service_script.normalize_name(raw))
		# 名前だけの試算は、除去した後の名前を返す（作成の最初の手順で、職業と顔の前に確かめる。PTY-003）
		var named: Dictionary = service.can_name(raw)
		t.check("P01", true, named.ok)
		t.check("P01", &"", named.error_code)
		t.check("P01", {"name": expected}, named.changes)
		var preview: Dictionary = service.can_register(session, raw, job, _portrait(0))
		t.check("P01", true, preview.ok)
		t.check("P01", &"", preview.error_code)
		# 試算は、登録後の行き先（パーティか待機。PTY-013）と費用（無料。PTY-000）も返す。確定した結果と一致する
		var party_before: int = session.party_ids.size()
		t.check("P01", {"name": expected, "joined_party": party_before < PARTY_LIMIT, "cost": 0}, preview.changes)
		# 試算は何も変えない
		t.check("P01", registered, session.characters.size())
		var result: Dictionary = service.register(session, raw, job, _portrait(0))
		t.check("P01", true, result.ok)
		t.check("P01", preview.changes.joined_party, result.changes.joined_party)
		t.check("P01", expected, session.characters.back().name)
		registered += 1
	t.check("P01", accepted.size(), session.characters.size())

	var before := _snapshot(session)
	for raw in rejected:
		var named: Dictionary = service.can_name(raw)
		t.check("P01", false, named.ok)
		t.check("P01", INVALID_NAME, named.error_code)
		t.check("P01", {}, named.changes)
		var preview: Dictionary = service.can_register(session, raw, job, _portrait(0))
		t.check("P01", false, preview.ok)
		t.check("P01", INVALID_NAME, preview.error_code)
		var result: Dictionary = service.register(session, raw, job, _portrait(0))
		t.check("P01", false, result.ok)
		t.check("P01", INVALID_NAME, result.error_code)
		t.check("P01", {}, result.changes)
	# 拒否では、IDも登録者も乱数の系列も変わらない（PTY-007, ARC-403）
	t.check("P01", before, _snapshot(session))

	_free_world(world)


## データベース、サービス、ニューゲーム直後のセッション。各系列に固定のseedを注入する（TST-102）。
func _world() -> Dictionary:
	var db = load(DB_SCRIPT).new()
	db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass)
	var rng = load(RNG_SERVICE_SCRIPT).new()
	rng.seed_all(RNG_SEEDS)
	var session = load(SESSION_SCRIPT).create_new(db, rng)
	var service = load(FACILITY_SCRIPT).new(db)
	return {"db": db, "rng": rng, "session": session, "service": service}


func _free_world(world: Dictionary) -> void:
	world.db.free()


func _portrait(i: int) -> String:
	return "portrait_%02d" % (i % PORTRAIT_COUNT + 1)


## `data/jobs.csv` の行。列名 -> 値（文字列）
func _read_jobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(JOBS_CSV, FileAccess.READ)
	if file == null:
		return rows
	var header := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i]
		rows.append(row)
	return rows


func _inventory_pairs(session) -> Array:
	return session.inventory.map(func(s): return [String(s.item_id), s.quantity])


## 登録で変わってはならない状態の写し。所持金・装備・ID・パーティ・所持品・各系列のstate・未保存フラグ。
func _snapshot(session) -> Dictionary:
	var equipment := {}
	var names := {}
	for character in session.characters:
		equipment[character.id] = [String(character.equipment[&"weapon"]), String(character.equipment[&"armor"]), String(character.equipment[&"accessory"])]
		names[character.id] = character.name
	var states := {}
	for id in RNG_SERIES:
		states[id] = session.rng.series(id).state
	return {
		"gold": session.gold,
		"next_character_id": session.next_character_id,
		"party_ids": session.party_ids.duplicate(),
		"inventory": _inventory_pairs(session),
		"equipment": equipment,
		"names": names,
		"rng": states,
		"dirty": session.dirty,
	}
