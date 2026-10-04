extends Control
## 状態から画面シーンへの対応表を持ち、GameFlow の状態に合わせて画面を差し替える（ARC-200, ARC-205）。
## 対応のない状態は仮画面「準備中」を出す（PRS-208）。入力の遮断中は背景の入力を止める（FLW-200）。

const GameFlowScript := preload("res://scripts/core/game_flow.gd")

const PLACEHOLDER_SCENE := "res://scenes/ui/placeholder.tscn"
## 状態 -> 画面シーン。画面を実装するIssueが、ここへ行を足す。
const SCREEN_SCENES := {
	GameFlowScript.State.TITLE: "res://scenes/ui/title.tscn",
}

## 現在表示している画面
var current_screen: Control = null
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
	var packed := load(SCREEN_SCENES.get(state, PLACEHOLDER_SCENE)) as PackedScene
	var screen = packed.instantiate()
	screen.setup(_flow)
	current_screen = screen
	add_child(current_screen)
	if input_blocker != null:
		move_child(input_blocker, -1)


func _on_input_block_changed(blocked: bool) -> void:
	input_blocker.visible = blocked
	if blocked:
		_focus_before_block = get_viewport().gui_get_focus_owner()
		input_blocker.grab_focus()
	elif is_instance_valid(_focus_before_block) and _focus_before_block.is_inside_tree():
		_focus_before_block.grab_focus()
		_focus_before_block = null
