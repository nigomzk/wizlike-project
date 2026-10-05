extends Control
## タイトル画面の presenter。押下は GameFlow へ要求を送るだけで、遷移の判断をしない（ARC-204, ARC-205）。

var _flow: Node = null

@onready var _buttons: Array[Button] = [%NewGame, %LoadGame, %Settings, %Quit]


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_buttons[0].pressed.connect(func(): _flow.request_new_game())
	_buttons[1].pressed.connect(func(): _flow.open_load())
	_buttons[2].pressed.connect(func(): _flow.open_settings())
	_buttons[3].pressed.connect(func(): _flow.quit_app())
	# ↑ / ↓ も、Tab / Shift+Tab と同じく端から反対の端へ巡回させる（U03）
	_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(_buttons[-1])
	_buttons[-1].focus_neighbor_bottom = _buttons[-1].get_path_to(_buttons[0])


## 最初の項目へフォーカスを置く。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_buttons[0].grab_focus()
