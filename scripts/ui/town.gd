extends Control
## 街の画面の presenter（town.md）。項目の可否は GameFlow が判定し、ここは結果を表示するだけにする（FLW-204, TWN-110, ARC-204）。
## 押下は GameFlow へ送り、遷移の判断をしない。セッションの変更の通知で、表示を更新する（ARC-205）。

var _flow: Node = null
## 通知を受けているセッション。TITLE へ戻ると GameFlow のセッションは破棄されるため、解除のために持つ。
var _session: RefCounted = null
## 街の操作 -> ボタン（FLW-004）。表示の順は、シーンの並びで決まる。
var _actions: Dictionary = {}

@onready var _gold_header: PanelContainer = %GoldHeader
@onready var _guide: Label = %Guide


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_actions = {
		&"guild": %Guild,
		&"temple": %Temple,
		&"shop": %Shop,
		&"inn": %Inn,
		&"tavern": %Tavern,
		&"departure": %Departure,
		&"menu": %Menu,
		&"save": %Save,
		&"title": %Title,
	}
	for action in _actions:
		_actions[action].pressed.connect(_on_pressed.bind(action))
	_guide.text = _flow.database.text(&"town_need_register")
	_session = _flow.session
	_gold_header.bind(_session)
	if _session != null:
		_session.changed.connect(_on_session_changed)
	_refresh()


func _exit_tree() -> void:
	if _session != null and _session.changed.is_connected(_on_session_changed):
		_session.changed.disconnect(_on_session_changed)


## 最初の項目（ギルド）へフォーカスを置く。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_actions[&"guild"].grab_focus()


func _on_pressed(action: StringName) -> void:
	_flow.select_town_action(action)


func _on_session_changed(_kind: StringName) -> void:
	_refresh()


## 登録者が0人の間は、ギルドとタイトルへ以外を選択不可にして、案内文を出す（TWN-110, TWN-112）。
func _refresh() -> void:
	for action in _actions:
		_actions[action].available = _flow.check_town_action(action).ok
	_guide.visible = _flow.is_town_restricted()
