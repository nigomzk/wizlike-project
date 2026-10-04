extends Control
## 遷移先が未実装の操作が開く仮画面。見出し「準備中」と戻るボタンだけを持つ（PRS-208）。

var _flow: Node = null

@onready var _back: Button = %Back


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_back.pressed.connect(func(): _flow.go_back())
	_back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_flow.go_back()
		get_viewport().set_input_as_handled()
