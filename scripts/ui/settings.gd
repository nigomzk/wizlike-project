extends Control
## 設定画面の presenter（FLW-014, FLW-111, FLW-112, FLW-113）。
## 値は GameFlow から読み、コピーを持たない。変更は GameFlow へ要求を送るだけで、保存や反映の判断をしない（ARC-204, ARC-205）。

## 左右キー1回あたりの音量の増減（PRS-400）。スライダーの操作は1刻み。
const KEY_VOLUME_STEP := 5
## フルスクリーンの状態を示す文字（色だけで区別しない。PRS-006）。
const TEXT_ON := "ON"
const TEXT_OFF := "OFF"

var _flow: Node = null

@onready var _volume: HSlider = %Volume
@onready var _volume_value: Label = %VolumeValue
@onready var _fullscreen: Button = %Fullscreen
@onready var _back: Button = %Back


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_volume.value_changed.connect(func(value: float): _flow.set_master_volume(int(value)))
	_volume.gui_input.connect(_on_volume_gui_input)
	_fullscreen.toggled.connect(func(on: bool): _flow.set_fullscreen(on))
	_back.pressed.connect(func(): _flow.go_back())
	# F11 など、この画面の外で設定が変わった場合も表示を追従させる
	_flow.settings_changed.connect(_refresh)
	# ↑ / ↓ も、Tab / Shift+Tab と同じく端から反対の端へ巡回させる（PRS-107）
	_volume.focus_neighbor_top = _volume.get_path_to(_back)
	_back.focus_neighbor_bottom = _back.get_path_to(_volume)
	_refresh()


## 音量のスライダーを最初に選ぶ。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_volume.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# go_back() は画面を差し替えて、このノードをツリーから外す。外れた後は get_viewport() が null になるため、先に処理済みにする
		get_viewport().set_input_as_handled()
		_flow.go_back()


## 左右キーで5ずつ増減する。スライダー標準の1刻みの処理には渡さず、ここで受け止める（PRS-400）。
func _on_volume_gui_input(event: InputEvent) -> void:
	var step := 0
	if event.is_action_pressed("ui_left", true):
		step = -KEY_VOLUME_STEP
	elif event.is_action_pressed("ui_right", true):
		step = KEY_VOLUME_STEP
	else:
		return
	get_viewport().set_input_as_handled()
	_flow.set_master_volume(_flow.master_volume + step)


func _refresh() -> void:
	_volume.set_value_no_signal(_flow.master_volume)
	_volume_value.text = str(_flow.master_volume)
	_fullscreen.set_pressed_no_signal(_flow.fullscreen)
	_fullscreen.text = TEXT_ON if _flow.fullscreen else TEXT_OFF
