extends HBoxContainer
## 共通UI部品「冒険者の状態表示」（components.md, PRS-006, ARC-207）。顔、名前、HP/SP、死亡と毒を出す。
## 死亡は「死亡」、毒は「毒」と文字で示す。色だけで区別しない（PRS-006）。冒険者の状態を書き換えない（ARC-205）。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。

const Rules := preload("res://scripts/rules/inventory_rules.gd")

## 表示する文字。短いラベルで、文章ではない（PRS-702）。
const TEXT_DEAD := "死亡"
const TEXT_POISON := "毒"
const TEXT_LEVEL := "Lv"
const TEXT_HP := "HP"
const TEXT_SP := "SP"

@onready var _face: TextureRect = %Face
@onready var _missing: Control = %Missing
@onready var _name: Label = %Name
@onready var _points: Label = %Points
@onready var _flags: Label = %Flags


## 死亡と毒を示す文字。どちらでもなければ空。死亡は HP が0になった状態（PTY-200）。
static func flags_text(character) -> String:
	var flags: Array[String] = []
	if character.current_hp <= 0:
		flags.append(TEXT_DEAD)
	if character.poison:
		flags.append(TEXT_POISON)
	return "　".join(flags)


## HP/SP の表示。最大値は装備補正を含む（INV-309）。
static func points_text(db, character) -> String:
	var stats := Rules.effective_stats(db, character)
	return "%s %d/%d　%s %d/%d" % [TEXT_HP, character.current_hp, stats.hp, TEXT_SP, character.current_sp, stats.sp]


## 一覧の1行の文字。顔以外の、名前、職業、レベル、HP/SP、死亡と毒、パーティでの順番（`slot_text`。待機者は「待機」）。
static func list_text(db, character, slot_text: String) -> String:
	var parts: Array[String] = [character.name, db.job(character.job_id).name, "%s%d" % [TEXT_LEVEL, character.level],
		points_text(db, character)]
	var flags := flags_text(character)
	if flags != "":
		parts.append(flags)
	parts.append(slot_text)
	return "　".join(parts)


## 冒険者を表示する。`slot_text` はパーティでの順番か「待機」。
## 顔の画像が無い場合は、仮の図形（枠）を出す（DAT-228, PRS-601）。
func show_character(db, character, slot_text: String) -> void:
	var texture: Texture2D = db.portrait_texture(character.portrait_id)
	_face.texture = texture
	_face.visible = texture != null
	_missing.visible = texture == null
	_name.text = "%s　%s %s%d" % [character.name, db.job(character.job_id).name, TEXT_LEVEL, character.level]
	_points.text = points_text(db, character)
	var flags := flags_text(character)
	_flags.text = flags if slot_text == "" else (slot_text if flags == "" else slot_text + "　" + flags)
