extends RefCounted
## TST-409: 構成と共通サービス（A）のテスト。

const IDS := ["A01", "A02", "A03", "A04", "A05", "A06", "A07"]

const MAIN_SCENE := "res://scenes/main.tscn"
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


## Theme の中で、スクリプトを持つリソース（StyleBox、フォント、アイコン、既定のフォント）を「型/種類/名前」の一覧で返す（ARC-208）。
func _scripted_theme_items(theme: Theme) -> Array:
	var result: Array = []
	if theme.default_font != null and theme.default_font.get_script() != null:
		result.append("default_font")
	for type_name in theme.get_stylebox_type_list():
		for item in theme.get_stylebox_list(type_name):
			if theme.get_stylebox(item, type_name).get_script() != null:
				result.append("%s/styles/%s" % [type_name, item])
	for type_name in theme.get_font_type_list():
		for item in theme.get_font_list(type_name):
			if theme.get_font(item, type_name).get_script() != null:
				result.append("%s/fonts/%s" % [type_name, item])
	for type_name in theme.get_icon_type_list():
		for item in theme.get_icon_list(type_name):
			if theme.get_icon(item, type_name).get_script() != null:
				result.append("%s/icons/%s" % [type_name, item])
	return result


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
