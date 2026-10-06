class_name ItemDef
extends Resource
## DAT-203: アイテム。素材は `target` と `contexts` を空とする（DAT-905）。`icon` は DAT-228。

const KINDS: Array[StringName] = [&"consumable", &"material"]
## 非売品を表す `buy_price`
const NOT_FOR_SALE := -1

@export var id: StringName = &""
@export var name := ""
@export var kind: StringName = &""
@export var max_stack := 9
@export var buy_price := NOT_FOR_SALE
@export var sell_price := 0
@export var shop_tier: StringName = &""
@export var target: StringName = &""
@export var contexts: Array[StringName] = []
@export var effects: Array[ActionEffect] = []
@export var icon: Texture2D
