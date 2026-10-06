class_name FloorDef
extends Resource
## DAT-210: フロア。マップの制作シーンは `res://scenes/floors/{id}.tscn` から解決する（DAT-229）。
## パスだけを持ち、シーンの存在は検証しない（検証はマップのコンパイル D02, D04 で行う）。

@export var id: StringName = &""
@export var display_name := ""
@export var dungeon: StringName = &""
@export var order := 0
@export var expected_level_min := 0
@export var expected_level_max := 0
@export var authoring_scene_path := ""
## DAT-210 の `authoring_scene`。参照するたびに読み込む（ファイルがなければ null）。
## 読込時には存在を検証しないため、`@export` にしない
var authoring_scene: PackedScene:
	get:
		return load_authoring_scene()
@export var encounters: Array[EncounterDef] = []
@export var events: Array[CellEventDef] = []
@export var default_spawn := Vector2i.ZERO
## 北0・東1・南2・西3
@export var default_facing := 0


## 制作シーンを読み込む。ファイルがなければ null
func load_authoring_scene() -> PackedScene:
	if not ResourceLoader.exists(authoring_scene_path):
		return null
	return load(authoring_scene_path) as PackedScene
