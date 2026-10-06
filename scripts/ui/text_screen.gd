extends Control
## 文章画面の presenter（text_screen.md）。文章を表示し、決定（Enter / 左クリック）で次へ進む。最後の文章で遷移先へ進む（PRS-503）。
## 遷移の判断は GameFlow が持ち、ここは要求を送るだけにする（ARC-204, ARC-205）。
## 現在は NEW_GAME の導入だけを扱う。GAME_OVER と ENDING は、それを実装するIssueが足す。

## NEW_GAME で表示する文章のID（FLW-002）。`data/texts.csv` の文章を、本文を複写せずIDで指定する（PRS-702）。
const NEW_GAME_PAGES: Array[StringName] = [&"intro"]

var _flow: Node = null
var _pages: Array[StringName] = []
var _page := 0

@onready var _text: Label = %Text


func setup(flow: Node) -> void:
	_flow = flow
	_pages = NEW_GAME_PAGES


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_show_page()


## 文章画面に、フォーカスを受ける項目はない。決定は、Enter を `_unhandled_input` で、左クリックを画面全体の `gui_input` で受ける。
func grab_initial_focus() -> void:
	pass


## キーの決定。キーの長押しで繰り返されるイベントは、決定に数えない（`is_action_pressed` の既定）ため、
## タイトルで押した Enter が、導入を飛ばすことはない。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		# 決定の結果、この画面はツリーから外れる。外れた後は get_viewport() が null になるため、先に処理済みにする
		get_viewport().set_input_as_handled()
		_decide()


func _on_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_decide()


## 次の文章へ進む。最後の文章なら、遷移先へ進む。入力の遮断中は進まない（FLW-200）。
func _decide() -> void:
	if _flow.is_input_blocked():
		return
	if _page + 1 < _pages.size():
		_page += 1
		_show_page()
	else:
		_flow.go_town()


func _show_page() -> void:
	_text.text = _flow.database.text(_pages[_page])
