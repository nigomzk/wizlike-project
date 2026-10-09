extends Button
## 共通UI部品「選択不可の表示」（components.md, ARC-207）。選べない項目を、無効にして薄く表示し、項目名の後ろに「（不可）」を添える（PRS-305, PRS-006）。
## 薄い色は共通Theme の Button の無効時の文字色で決まる（ARC-208）。可否の判断は持たず、呼び出し側が `available` で与える。
## 選べない項目は、フォーカスも受けない。選択中の項目はフォーカスを持つ項目であり（PRS-304）、矢印キーと Tab で選べない項目へ移らないようにするため。

## 選べない項目の名前に添える文字（PRS-305）。
const UNAVAILABLE_SUFFIX := "（不可）"

## 項目名。表示は、選べない場合に「（不可）」を添えたもの。
@export var label: String = "":
	set(value):
		label = value
		_refresh()

## 選べるか。false の間は、ボタンを無効にする。
var available: bool = true:
	set(value):
		available = value
		_refresh()


func _refresh() -> void:
	text = label if available else label + UNAVAILABLE_SUFFIX
	disabled = not available
	focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	if not available and has_focus():
		release_focus()
