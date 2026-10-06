extends Control
## 起動不可のエラー画面の presenter（FLW-016, DAT-900）。メッセージと終了ボタンだけを持ち、遷移の判断をしない（ARC-204, ARC-205）。
## 問題のIDとファイル名は画面に出さず、ログへ出す（DAT-908。ログの出力は GameDatabase が行う）。

## `data/texts.csv` を読み込めない場合に表示する、コードに固定した文（PRS-704）。`boot_error` の文章と同じ内容にする。
const FALLBACK_MESSAGE := "データの読込に失敗したため、ゲームを開始できません。"
## 表示する文章のID（DAT-909）
const MESSAGE_ID := &"boot_error"

var _flow: Node = null

@onready var _message: Label = %Message
@onready var _quit: Button = %Quit


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	# texts.csv 自体を読み込めない（文章が1件もない）場合に限り、固定した文を表示する（PRS-704）
	var database: Node = _flow.database
	_message.text = database.text(MESSAGE_ID) if database.text_count() > 0 else FALLBACK_MESSAGE
	_quit.pressed.connect(func(): _flow.quit_app())


## 終了ボタンへフォーカスを置く。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_quit.grab_focus()


## フォーカスが外れていても、Enter で終了する。フォーカスのあるボタンは、自分で Enter を受けて終了する。入力の遮断中は終了しない（FLW-200）。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not _flow.is_input_blocked():
		get_viewport().set_input_as_handled()
		_flow.quit_app()
