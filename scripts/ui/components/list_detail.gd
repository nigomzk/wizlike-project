extends VBoxContainer
## 共通UI部品「一覧・詳細・戻る」（components.md, PRS-205, PRS-007, ARC-207）。
## 見出し、スクロールできる一覧、選択中の項目の詳細、戻るボタンを持つ。選択中の項目はフォーカスを持つ項目で、塗りと枠で示す（PRS-304）。
## 一覧の項目と詳細の中身は、使う画面が与える。一覧の外に置く操作は `actions()` の入れ物へ足す。可否の判断は持たない。

const ROW_SCENE := preload("res://scenes/ui/components/availability_button.tscn")
## 一覧の1行の高さ。顔の画像を1行に収める高さにする。
const ROW_HEIGHT := 48

## 項目にフォーカスが移った（選択中になった）。
signal item_focused(index: int)
## 項目が決定された（Enter / 左クリック。PRS-104）。
signal item_activated(index: int)
## 戻るボタンが押された。
signal back_pressed

var _rows: Array[Button] = []

@onready var _heading: Label = %Heading
@onready var _items: VBoxContainer = %Items
@onready var _detail: VBoxContainer = %Detail
@onready var _actions: HBoxContainer = %Actions
@onready var _back: Button = %Back


func _ready() -> void:
	_back.pressed.connect(func(): back_pressed.emit())


func set_heading(text: String) -> void:
	_heading.text = text


## 一覧を作り直す。項目は `{label: String, available: bool（省略時 true）, icon: Texture2D（省略可）}`。
## 選べない項目は「（不可）」を添えて薄く表示し、フォーカスを受けない（PRS-305）。
func set_items(entries: Array) -> void:
	for row in _rows:
		_items.remove_child(row)
		row.queue_free()
	_rows.clear()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row: Button = ROW_SCENE.instantiate()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.label = entry.label
		row.available = entry.get("available", true)
		var icon: Texture2D = entry.get("icon")
		if icon != null:
			row.icon = icon
			row.expand_icon = true
		row.focus_entered.connect(func(): item_focused.emit(i))
		row.pressed.connect(func(): item_activated.emit(i))
		_items.add_child(row)
		_rows.append(row)


func item_count() -> int:
	return _rows.size()


func item_button(index: int) -> Button:
	return _rows[index]


## 詳細の入れ物。使う画面が中身を足す。
func detail() -> VBoxContainer:
	return _detail


## 一覧の下に置く操作の入れ物。戻るボタンの左に並ぶ。
func actions() -> HBoxContainer:
	return _actions


## 詳細の中身を取り除く。
func clear_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()


## `index` の項目へフォーカスを置く。範囲外と、選べない項目は置かない。置けたら true。
func focus_item(index: int) -> bool:
	if index < 0 or index >= _rows.size() or not _rows[index].available or not is_inside_tree():
		return false
	_rows[index].grab_focus()
	return true


func focus_back() -> void:
	_back.grab_focus()
