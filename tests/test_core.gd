extends RefCounted
## TST-409: 構成と共通サービス（A）のテスト。

const IDS := ["A01", "A02", "A03", "A04", "A05"]

const MAIN_SCENE := "res://scenes/main.tscn"
const ALLOWED_AUTOLOADS := ["GameDatabase", "SaveService"]


func run(t) -> void:
	_a01(t)


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
