extends PanelContainer
## 共通UI部品「所持金ヘッダー」（components.md, PRS-205, ARC-207）。現在の所持金を表示する。
## セッションを参照し、変更の通知（`changed`）で表示を更新する（ARC-204, ARC-205）。GameFlow には依存しない。

## 表示の形。短いラベルで、文章ではない（PRS-702）。
const GOLD_FORMAT := "所持金 %dG"

var _session: RefCounted = null

@onready var _value: Label = %Value


## 表示するセッションを結ぶ。先に結んでいたセッションの通知は解除する。
func bind(session: RefCounted) -> void:
	_unbind()
	_session = session
	if _session != null:
		_session.changed.connect(_on_session_changed)
	_refresh()


func _ready() -> void:
	_refresh()


func _exit_tree() -> void:
	_unbind()


func _unbind() -> void:
	if _session != null and _session.changed.is_connected(_on_session_changed):
		_session.changed.disconnect(_on_session_changed)
	_session = null


func _on_session_changed(_kind: StringName) -> void:
	_refresh()


func _refresh() -> void:
	if _value != null and _session != null:
		_value.text = GOLD_FORMAT % _session.gold
