extends Control
## 状態から画面シーンへの対応表を持ち、GameFlow の状態に合わせて画面を差し替える（ARC-200, ARC-205）。
## 対応のない状態は仮画面「準備中」を出す（PRS-208）。入力の遮断中は背景の入力を止める（FLW-200）。
## マウスを動かして載せた項目へフォーカスを移す処理を、画面ごとではなくここで一括して付ける（ARC-209）。

const GameFlowScript := preload("res://scripts/core/game_flow.gd")

const PLACEHOLDER_SCENE := "res://scenes/ui/placeholder.tscn"
## 状態 -> 画面シーン。画面を実装するIssueが、ここへ行を足す。
const SCREEN_SCENES := {
	GameFlowScript.State.BOOT_ERROR: "res://scenes/ui/boot_error.tscn",
	GameFlowScript.State.TITLE: "res://scenes/ui/title.tscn",
	GameFlowScript.State.NEW_GAME: "res://scenes/ui/text_screen.tscn",
	GameFlowScript.State.TOWN: "res://scenes/ui/town.tscn",
	GameFlowScript.State.SETTINGS: "res://scenes/ui/settings.tscn",
}

## 施設 -> 画面シーン。FACILITY の状態は、開いている施設（`GameFlow.facility`）で画面が決まる。画面のない施設は仮画面を出す（PRS-208）。
## 施設の画面を実装するIssueが、ここへ行を足す。
const FACILITY_SCENES := {
	&"guild": "res://scenes/ui/guild.tscn",
}

## 現在表示している画面
var current_screen: Control = null
## 確認ダイアログなどのモーダルを置く先。`main.tscn` の ModalHost。無い構成では、この ScreenHost 自身（ARC-200, FLW-200）
var modal_host: Node = null
## 入力の遮断中に、背景の画面へのマウスとキーを止める全面のControl
var input_blocker: Control = null

var _flow: Node = null
var _focus_before_block: Control = null


func _ready() -> void:
	input_blocker = Control.new()
	input_blocker.name = "InputBlocker"
	input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	input_blocker.focus_mode = Control.FOCUS_ALL
	input_blocker.visible = false
	# 遮断中のキーは、フォーカス移動へ回さずここで受け止める
	input_blocker.gui_input.connect(func(_event: InputEvent): input_blocker.accept_event())
	add_child(input_blocker)
	modal_host = get_node_or_null("../ModalHost")
	if modal_host == null:
		modal_host = self
	# 画面へ後から追加された項目にも、ツリーに入った時点で結ぶ（ARC-209）
	get_tree().node_added.connect(_on_node_added)
	if _flow == null:
		bind(get_node_or_null("../GameFlow"))


## GameFlow を結び付けて、現在の状態の画面を表示する。
func bind(flow: Node) -> void:
	assert(flow != null, "ScreenHost needs a GameFlow")
	_flow = flow
	_flow.state_changed.connect(_on_state_changed)
	_flow.input_block_changed.connect(_on_input_block_changed)
	_show_screen(_flow.state)
	_on_input_block_changed(_flow.is_input_blocked())


func _on_state_changed(new_state: GameFlowScript.State, _old_state: GameFlowScript.State) -> void:
	_show_screen(new_state)


func _show_screen(state: GameFlowScript.State) -> void:
	if state == GameFlowScript.State.BOOT:
		return
	if current_screen != null:
		remove_child(current_screen)
		current_screen.queue_free()
		current_screen = null
	var packed := load(_scene_path(state)) as PackedScene
	var screen = packed.instantiate()
	screen.setup(_flow)
	current_screen = screen
	add_child(current_screen)
	# ScreenHost がツリーに入る前に表示した画面は node_added に届かないので、ここでも結ぶ（ARC-209）
	_follow_mouse_focus(current_screen)
	for node in current_screen.find_children("*", "Control", true, false):
		_follow_mouse_focus(node)
	if input_blocker != null:
		move_child(input_blocker, -1)
	# `_ready` の中より、遅延させたほうが確実にフォーカスが付く
	current_screen.call_deferred("grab_initial_focus")


func _scene_path(state: GameFlowScript.State) -> String:
	if state == GameFlowScript.State.FACILITY:
		return FACILITY_SCENES.get(_flow.facility, PLACEHOLDER_SCENE)
	return SCREEN_SCENES.get(state, PLACEHOLDER_SCENE)


func _on_node_added(node: Node) -> void:
	if current_screen != null and (node == current_screen or current_screen.is_ancestor_of(node)):
		_follow_mouse_focus(node)


## 表示中の画面の Control に、マウスの移動でフォーカスを移す処理を結ぶ（ARC-209）。
## 項目がツリーから外れて入り直したときに二重に結ばないよう、結線済みなら何もしない。
func _follow_mouse_focus(node: Node) -> void:
	var control := node as Control
	if control == null:
		return
	var handler := _on_item_gui_input.bind(control)
	if not control.gui_input.is_connected(handler):
		control.gui_input.connect(handler)


## マウスを実際に動かして載せた項目へ、フォーカスを移す（ARC-209）。
## `mouse_entered` は静止したカーソルの下に画面が差し替わったときにも届くため使わない。
## 移動量のない移動も、マウスを動かしていないものとして扱う。入力の遮断中は移さない（FLW-200）。
func _on_item_gui_input(event: InputEvent, item: Control) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or motion.relative == Vector2.ZERO:
		return
	if item.focus_mode != Control.FOCUS_ALL or item.has_focus() or _flow.is_input_blocked():
		return
	item.grab_focus()


func _on_input_block_changed(blocked: bool) -> void:
	if blocked == input_blocker.visible:
		return
	input_blocker.visible = blocked
	if blocked:
		_focus_before_block = get_viewport().gui_get_focus_owner()
		input_blocker.grab_focus()
		return
	# 遮断中に画面が差し替わっていた場合は、元のフォーカスが残っていないので、新しい画面の先頭へ置く
	if is_instance_valid(_focus_before_block) and _focus_before_block.is_inside_tree():
		_focus_before_block.grab_focus()
	elif current_screen != null:
		current_screen.grab_initial_focus()
	_focus_before_block = null
