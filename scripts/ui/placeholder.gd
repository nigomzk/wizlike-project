extends Control
## 遷移先が未実装の操作が開く仮画面。見出し「準備中」と戻るボタンだけを持つ（PRS-208）。

var _flow: Node = null

@onready var _back: Button = %Back


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_back.pressed.connect(func(): _flow.go_back())


## 戻るボタンへフォーカスを置く。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_flow.go_back()
		get_viewport().set_input_as_handled()
