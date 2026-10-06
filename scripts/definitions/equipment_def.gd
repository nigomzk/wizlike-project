class_name EquipmentDef
extends Resource
## DAT-202: 装備。`icon` は `res://assets/icons/{id}.png` から解決し、なければ null（DAT-228）。

const SLOTS: Array[StringName] = [&"weapon", &"armor", &"accessory"]
## DAT-122
const SHOP_TIERS: Array[StringName] = [&"A", &"B", &"C"]

@export var id: StringName = &""
@export var name := ""
@export var slot: StringName = &""
@export var category: StringName = &""
@export var allowed_jobs: Array[StringName] = []
@export var attack := 0
@export var defense := 0
## DAT-224: 未指定の値は 0
@export var stat_bonus: StatBlock
@export var buy_price := 0
@export var sell_price := 0
@export var shop_tier: StringName = &""
@export var icon: Texture2D
