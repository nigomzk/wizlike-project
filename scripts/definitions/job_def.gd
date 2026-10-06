class_name JobDef
extends Resource
## DAT-200: 職業。`learnable_skill_ids` と `armor_ids` はCSVに列がなく、読込時に導出する（DAT-227）。

@export var id: StringName = &""
@export var name := ""
@export var base_stats: StatBlock
## DAT-221: 装備補正を含めない
@export var growth_fixed: StatBlock
@export var growth_extra_chance: StatChance
@export var starting_weapon_id: StringName = &""
@export var starting_armor_id: StringName = &""
@export var initial_skill_id: StringName = &""
@export var weapon_category: StringName = &""
## `skills.csv` の `job_id` が自分のスキル
@export var learnable_skill_ids: Array[StringName] = []
## `equipment.csv` の防具のうち、`allowed_jobs` に自分を含むもの
@export var armor_ids: Array[StringName] = []
