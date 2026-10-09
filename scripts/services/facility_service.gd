class_name FacilityService
extends RefCounted
## 施設の操作を、条件の確認と更新を1つにして行う（ARC-302, TWN-100）。画面は持たない。
##
## 今は冒険者の登録（`can_register` / `register`）だけ。操作の結果は `{ok, error_code, changes}`（ARC-400）。
## 失敗した操作は、所持金・装備・ID・乱数・未保存フラグのいずれも変えない（ARC-403, TWN-101, PTY-012）。
## エラーコードの日本語は UI が `data/texts.csv` の `error_*` から引く。ここでは表示文言を持たない（ARC-402）。
## 乱数は自分で作らず、セッションの `RngService` の系列から引く（ARC-404, GLS-201）。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。

const Character := preload("res://scripts/models/character_state.gd")
const Rules := preload("res://scripts/rules/inventory_rules.gd")
const Rng := preload("res://scripts/services/rng_service.gd")

## 登録者の上限（PTY-000）
const ROSTER_LIMIT := 20
## パーティの上限。4人未満であれば、登録した冒険者をパーティの末尾へ加える（PTY-013）
const PARTY_LIMIT := 4
## 名前の文字数。前後の空白を除いた後で数える（PTY-003）
const NAME_MIN := 1
const NAME_MAX := 12
## 顔画像は `portrait_01` 〜 `portrait_10` の10種（PTY-005, DAT-522）
const PORTRAIT_COUNT := 10

const ROSTER_FULL := &"ROSTER_FULL"
const INVALID_NAME := &"INVALID_NAME"
const INVALID_TARGET := &"INVALID_TARGET"

## 登録の成功をセッションの `changed` で知らせるときの種別
const CHANGE_ROSTER := &"roster"

## 名前の前後から取り除く空白。半角の空白とタブ、全角の空白（PTY-003）
const _TRIMMED: Array[String] = [" ", "\t", "　"]
## 名前に含められない文字（PTY-003）
const _LINE_BREAKS: Array[String] = ["\n", "\r"]

## `GameDatabase`。職業の定義（初期能力・初期装備・初期スキル）を読む
var _db


func _init(db) -> void:
	_db = db


## 名前の前後の空白（全角空白を含む）を取り除く（PTY-003）。長さと改行の判定はしない。
static func normalize_name(raw: String) -> String:
	var start := 0
	var end := raw.length()
	while start < end and _TRIMMED.has(raw[start]):
		start += 1
	while end > start and _TRIMMED.has(raw[end - 1]):
		end -= 1
	return raw.substr(start, end - start)


## 前後の空白を除いた名前が、1〜12文字で、改行を含まないか（PTY-003）。引数は `normalize_name()` の結果。
static func is_valid_name(normalized: String) -> bool:
	if normalized.length() < NAME_MIN or normalized.length() > NAME_MAX:
		return false
	for line_break in _LINE_BREAKS:
		if normalized.contains(line_break):
			return false
	return true


## 顔画像のIDが10種のどれかか（PTY-005, DAT-522）。
static func is_portrait_id(portrait_id: String) -> bool:
	for n in range(1, PORTRAIT_COUNT + 1):
		if portrait_id == "portrait_%02d" % n:
			return true
	return false


## 登録できるかを、何も変えずに確かめる。作成の途中の確認にも使う（PTY-007）。乱数も引かない（GLS-203）。
## 成功の `changes` は `{name}`（前後の空白を除いた名前）。
## 失敗は、上限が `ROSTER_FULL`（PTY-012）、職業と顔画像の不明が `INVALID_TARGET`、名前の誤りが `INVALID_NAME`（PTY-003）。
## 複数に当たるときは、この順で最初のものを返す。
func can_register(session, raw_name: String, job_id: StringName, portrait_id: String) -> Dictionary:
	if session.characters.size() >= ROSTER_LIMIT:
		return _failure(ROSTER_FULL)
	if _db.job(job_id) == null or not is_portrait_id(portrait_id):
		return _failure(INVALID_TARGET)
	var normalized := normalize_name(raw_name)
	if not is_valid_name(normalized):
		return _failure(INVALID_NAME)
	return _success({"name": normalized})


## 冒険者を1人登録する。確定の直前に条件を確かめ、成功したときだけ一括で反映する（TWN-100, TWN-101）。
## 登録は無料で、所持金と所持品を変えない（PTY-000, TWN-006）。初期の武器と防具は装備枠へ直接入れ、所持品を通さない（INV-101）。
## 乱数は、確定したときに限り、`creation` 系列から1回引いて `growth_rng` のseedにする（GLS-201, GLS-204）。
## 成功の `changes` は `{character_id, joined_party}`。
func register(session, raw_name: String, job_id: StringName, portrait_id: String) -> Dictionary:
	var checked := can_register(session, raw_name, job_id, portrait_id)
	if not checked.ok:
		return checked
	var job: JobDef = _db.job(job_id)

	var character: Character = Character.new()
	character.id = session.next_character_id
	character.name = checked.changes.name
	character.job_id = job_id
	character.portrait_id = portrait_id
	# 固定データの職業と能力値を共有しない（DAT-002）。初期能力は乱数を用いない（PTY-210）
	character.base_stats = job.base_stats.duplicate() as StatBlock
	character.equipment = {&"weapon": job.starting_weapon_id, &"armor": job.starting_armor_id, &"accessory": &""}
	character.learned_skill_ids.append(job.initial_skill_id)
	# レベル1で、HPとSPを満タンにする（PTY-009）。最大値には装備の補正を含む（INV-309）
	var stats := Rules.effective_stats(_db, character)
	character.current_hp = stats.hp
	character.current_sp = stats.sp
	character.growth_rng = RandomNumberGenerator.new()
	character.growth_rng.seed = session.rng.series(Rng.CREATION).randi()

	session.characters.append(character)
	session.next_character_id += 1
	var joined_party: bool = session.party_ids.size() < PARTY_LIMIT
	if joined_party:
		session.party_ids.append(character.id)
	session.notify_changed(CHANGE_ROSTER)
	return _success({"character_id": character.id, "joined_party": joined_party})


static func _success(changes: Dictionary) -> Dictionary:
	return {"ok": true, "error_code": &"", "changes": changes}


static func _failure(error_code: StringName) -> Dictionary:
	return {"ok": false, "error_code": error_code, "changes": {}}
