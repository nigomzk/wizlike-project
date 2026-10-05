@tool
extends StyleBox
## パネルの二重線を描く StyleBox（PRS-302, PRS-303）。画像を使わず、色と寸法は共通Theme から設定する。
## 外側の線の内側（隙間を含む）を塗りで満たし、その上に外側と同心の角丸で内側の線を重ねる。
## 内容までの余白（content_margin）は、線と隙間の幅に padding を足して自動で決める。

## 外側の線と塗りを描く箱。線と隙間の幅や色を変えるたびに _refresh() で設定し直す
var _outer := StyleBoxFlat.new()
## 内側の線だけを描く箱
var _inner := StyleBoxFlat.new()

## 塗り（隙間も含む）
@export var fill_color := Color(0, 0, 0, 0):
	set(value):
		fill_color = value
		_refresh()
## 二重線の色（外側と内側で共通）
@export var border_color := Color(1, 1, 1, 1):
	set(value):
		border_color = value
		_refresh()
## 外側の線の幅
@export_range(0, 16) var outer_width := 2:
	set(value):
		outer_width = value
		_refresh()
## 外側の線と内側の線の隙間
@export_range(0, 16) var gap := 2:
	set(value):
		gap = value
		_refresh()
## 内側の線の幅
@export_range(0, 16) var inner_width := 1:
	set(value):
		inner_width = value
		_refresh()
## 外側の線の角丸。内側の線は、ここから外側の線と隙間の幅を引いた半径で同心にする
@export_range(0, 32) var corner_radius := 6:
	set(value):
		corner_radius = value
		_refresh()
## 内側の線から内容までの余白
@export_range(0, 64) var padding := 16:
	set(value):
		padding = value
		_refresh()


func _init() -> void:
	_refresh()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	_outer.draw(to_canvas_item, rect)
	var inset := outer_width + gap
	_inner.draw(to_canvas_item, rect.grow(-inset))


func _refresh() -> void:
	_outer.bg_color = fill_color
	_outer.border_color = border_color
	_outer.set_border_width_all(outer_width)
	_outer.set_corner_radius_all(corner_radius)

	_inner.draw_center = false
	_inner.border_color = border_color
	_inner.set_border_width_all(inner_width)
	_inner.set_corner_radius_all(maxi(corner_radius - outer_width - gap, 0))

	var margin := outer_width + gap + inner_width + padding
	content_margin_left = margin
	content_margin_top = margin
	content_margin_right = margin
	content_margin_bottom = margin
	emit_changed()
