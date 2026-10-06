class_name ItemStackState
extends RefCounted
## DAT-515: 所持品の1枠。装備は quantity=1、消耗品と素材は1〜max_stack。
## 所持品の一覧は `Array[ItemStackState]`（DAT-500）。

var item_id: StringName = &""
var quantity := 0


func _init(id: StringName = &"", count := 0) -> void:
	item_id = id
	quantity = count


## 試算で入力を変えないための複写（ARC-403）。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、自分の名前でなくスクリプトから作る
func copy() -> RefCounted:
	return get_script().new(item_id, quantity)
