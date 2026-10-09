extends Control
## 共通UI部品「確認ダイアログ」（components.md, ARC-207）。確認文、確定で変更される項目と費用、「はい」「いいえ」を出す。
## ModalHost に置き、表示している間は GameFlow の入力遮断に登録して、背景の画面への入力を止める（FLW-200, FLW-204, TWN-102）。
## 初期選択は「いいえ」（取消側。FLW-203）。Esc も「いいえ」と同じ取消とする（PRS-104）。答えは1回だけ受け付ける。

const DIALOG_SCENE := "res://scenes/ui/components/confirm_dialog.tscn"
## 入力の遮断を登録する理由（GameFlow の `block_input()`）。
const BLOCK_REASON := &"confirm_dialog"

## 答えが出たときに送る。`confirmed` が true なら「はい」。
signal answered(confirmed: bool)

var _flow: Node = null
var _answered := false

@onready var _message: Label = %Message
@onready var _details: Label = %Details
@onready var _yes: Button = %Yes
@onready var _no: Button = %No


## ダイアログを `host`（ModalHost）に出して返す。`details` は確定で変更される項目と費用の行（TWN-102）。
## 戻り値の `answered` を待つ。
static func open(host: Node, flow: Node, message: String, details: Array[String] = []) -> Control:
	var dialog: Control = (load(DIALOG_SCENE) as PackedScene).instantiate()
	host.add_child(dialog)
	dialog.present(flow, message, details)
	return dialog


func _ready() -> void:
	_yes.pressed.connect(_answer.bind(true))
	_no.pressed.connect(_answer.bind(false))
	# Tab と矢印キーで、背景の項目へフォーカスが出ないよう、2つのボタンの間だけを巡らせる（FLW-200）
	for pair in [[_yes, _no], [_no, _yes]]:
		var from: Button = pair[0]
		var to_path := from.get_path_to(pair[1])
		from.focus_neighbor_left = to_path
		from.focus_neighbor_right = to_path
		from.focus_neighbor_top = to_path
		from.focus_neighbor_bottom = to_path
		from.focus_next = to_path
		from.focus_previous = to_path


## 内容を設定し、入力を遮断して、「いいえ」へフォーカスを置く。
## 遮断の登録でScreenHostが先にフォーカスを取るため、その後でここがフォーカスを取る。
func present(flow: Node, message: String, details: Array[String]) -> void:
	_flow = flow
	_message.text = message
	_details.text = "\n".join(details)
	_details.visible = not details.is_empty()
	_flow.block_input(BLOCK_REASON)
	_no.grab_focus()


## 外から取り除かれた場合も、遮断を残さない。
func _exit_tree() -> void:
	_release()


func _input(event: InputEvent) -> void:
	if _answered or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_answer(false)


func _answer(confirmed: bool) -> void:
	if _answered:
		return
	_answered = true
	hide()
	_release()
	answered.emit(confirmed)
	queue_free()


## 遮断を外す。一度だけ外す。
func _release() -> void:
	if _flow != null and is_instance_valid(_flow):
		_flow.unblock_input(BLOCK_REASON)
	_flow = null
