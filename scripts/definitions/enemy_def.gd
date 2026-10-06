class_name EnemyDef
extends Resource
## DAT-204: 敵。`portrait` は `res://assets/enemies/{id}.png` から解決し、なければ null（DAT-228）。

## DAT-120
const ACTION_MODES: Array[StringName] = [&"weighted", &"cycle"]

@export var id: StringName = &""
@export var name := ""
@export var hp := 0
@export var attack := 0
@export var defense := 0
@export var tec := 0
@export var agi := 0
@export var luc := 0
## 属性 → 倍率。記載のない属性は 1.0（`data/README.md`）
@export var element_multipliers: Dictionary = {}
## 状態異常 → 耐性倍率。記載のないものは 1.0
@export var status_multipliers: Dictionary = {}
@export var exp := 0
@export var gold := 0
@export var drop_item_id: StringName = &""
@export var drop_chance := 0.0
@export var action_mode: StringName = &"weighted"
@export var action_weights: Array[WeightedAction] = []
## 固定巡回。先頭が `turn_index` 1
@export var action_cycle: Array[StringName] = []
@export var portrait: Texture2D
@export var is_boss := false
