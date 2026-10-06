extends RefCounted
## TST-402: 所持品と装備（I）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08"]

const DB_SCRIPT := "res://scripts/core/game_database.gd"
const DATA_DIR := "res://data"
# 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、実行時に `load` で読む
const RULES_SCRIPT := "res://scripts/rules/inventory_rules.gd"
const CHARACTER_SCRIPT := "res://scripts/models/character_state.gd"
const STACK_SCRIPT := "res://scripts/models/inventory_state.gd"

## INV-100: 共有の所持品の枠数。設計書の規則であり、`data/` にはない
const CAPACITY := 30
const SLOTS: Array[StringName] = [&"weapon", &"armor", &"accessory"]
const STAT_FIELDS: Array[String] = ["hp", "sp", "str", "vit", "tec", "agi", "luc"]

const NO_SPACE := &"NO_SPACE"
const INVALID_TARGET := &"INVALID_TARGET"


## I05 が最大SPの増減を確かめるための、SPの補正を持つ装備だけを返す差し替えのデータベース。
## `InventoryRules` は `item_or_equipment()` だけを読む。
class StubDb extends RefCounted:
	var _by_id: Dictionary = {}

	func add(def: Resource) -> void:
		_by_id[def.id] = def

	func item_or_equipment(id: StringName) -> Resource:
		return _by_id.get(id)


var _rules
var _db


func run(_t) -> void:
	_rules = load(RULES_SCRIPT)
	_db = load(DB_SCRIPT).new()
	_db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass)
	_i01(_t)
	_i02(_t)
	_i05(_t)
	_i06(_t)
	_i08(_t)
	_db.free()


# I01: 同一の消耗品を8個持つ状態で3個追加する（INV-103, INV-104, INV-200, INV-201, ARC-403）
func _i01(t) -> void:
	var herb: ItemDef = _db.item(&"herb")
	var max_stack := herb.max_stack
	var inv := [_stack(&"herb", 8)]

	var plan: Dictionary = _rules.plan_transaction(_db, inv, [_def(&"herb", 3)], [])
	t.check("I01", true, plan.ok)
	t.check("I01", &"", plan.error_code)
	# 9個の枠と2個の枠の計2枠になる
	t.check("I01", [[&"herb", max_stack], [&"herb", 8 + 3 - max_stack]], _pairs(plan.changes.inventory))
	t.check("I01", 2, _rules.slot_count(_db, plan.changes.inventory))
	# 試算中は入力を変更しない（ARC-403）
	t.check("I01", [[&"herb", 8]], _pairs(inv))
	# 成功時のみ適用する（INV-200）
	t.check("I01", true, _rules.apply(plan, inv))
	t.check("I01", [[&"herb", max_stack], [&"herb", 8 + 3 - max_stack]], _pairs(inv))

	# 同種の品は、部分的に埋まっているスタックから先に詰める（INV-104）
	var partial := [_stack(&"herb", 5), _stack(&"herb", max_stack), _stack(&"ether", 4)]
	var filled: Dictionary = _rules.plan_transaction(_db, partial, [_def(&"herb", 6)], [])
	var rest := 5 + 6 - max_stack
	t.check("I01", [[&"herb", max_stack], [&"herb", max_stack], [&"ether", 4], [&"herb", rest]], _pairs(filled.changes.inventory))

	# 10個であれば2枠を占める（INV-103）。武器・防具・装飾品は1個につき1枠（INV-102）
	t.check("I01", 2, _rules.slot_count(_db, [_stack(&"herb", max_stack + 1)]))
	t.check("I01", 3, _rules.slot_count(_db, [_stack(&"sword_1", 1), _stack(&"sword_1", 1), _stack(&"cloth", 1)]))
	# 重要アイテムは別の辞書で管理し、所持品の枠に数えない（INV-105）。所持品の配列だけを数える
	t.check("I01", 0, _rules.slot_count(_db, []))

	# 削除は、あとの枠から減らす。0個になった枠は消える
	var removal: Dictionary = _rules.plan_transaction(_db, [_stack(&"herb", max_stack), _stack(&"herb", 2)], [], [_def(&"herb", 3)])
	t.check("I01", true, removal.ok)
	t.check("I01", [[&"herb", max_stack - 1]], _pairs(removal.changes.inventory))

	# 容量が不足する場合は、取引の全体を成立させない（INV-201）。部分的な取得を行わない
	var full := _filler(CAPACITY - 1)
	var over: Dictionary = _rules.plan_transaction(_db, full, [_def(&"sword_1", 1), _def(&"sword_2", 1)], [])
	t.check("I01", false, over.ok)
	t.check("I01", NO_SPACE, over.error_code)
	t.check("I01", {}, over.changes)
	t.check("I01", CAPACITY - 1, full.size())
	t.check("I01", false, _rules.apply(over, full))
	t.check("I01", CAPACITY - 1, full.size())
	# 削除で空く枠を、同じ取引の追加に使える（交換。INV-200）
	var swap: Dictionary = _rules.plan_transaction(_db, _filler(CAPACITY), [_def(&"sword_1", 1)], [_def(&"cloth", 1)])
	t.check("I01", true, swap.ok)
	t.check("I01", CAPACITY, _rules.slot_count(_db, swap.changes.inventory))

	# 所持していない品の削除、存在しないID、0個以下は INVALID_TARGET とし、何も変更しない
	for bad in [
		_rules.plan_transaction(_db, [_stack(&"herb", 2)], [], [_def(&"herb", 3)]),
		_rules.plan_transaction(_db, [], [], [_def(&"herb", 1)]),
		_rules.plan_transaction(_db, [], [_def(&"no_such_item", 1)], []),
		_rules.plan_transaction(_db, [], [_def(&"herb", 0)], []),
	]:
		t.check("I01", false, bad.ok)
		t.check("I01", INVALID_TARGET, bad.error_code)
		t.check("I01", {}, bad.changes)


# I02: 30枠が埋まった状態で装備を交換し、装備を取り外す（INV-303, INV-101）
func _i02(t) -> void:
	var inv := [_stack(&"sword_2", 1)]
	inv.append_array(_filler(CAPACITY - 1))
	var c = _character(&"warrior")
	t.check("I02", CAPACITY, _rules.slot_count(_db, inv))

	# 差分で収まる交換は成立する（外した剣が、着けた剣の空きへ入る）
	var swap: Dictionary = _rules.plan_equip(_db, inv, c, &"weapon", &"sword_2")
	t.check("I02", true, swap.ok)
	t.check("I02", CAPACITY, _rules.slot_count(_db, swap.changes.inventory))
	t.check("I02", true, _pairs(swap.changes.inventory).has([&"sword_1", 1]))
	t.check("I02", false, _pairs(swap.changes.inventory).has([&"sword_2", 1]))
	t.check("I02", &"sword_2", swap.changes.equipment[&"weapon"])
	# 試算中は入力を変更しない（ARC-403）
	t.check("I02", &"sword_1", c.equipment[&"weapon"])
	t.check("I02", CAPACITY, inv.size())
	t.check("I02", true, _pairs(inv).has([&"sword_2", 1]))
	# 装備の試算は、冒険者なしでは適用しない。所持品だけが変わって食い違うことを防ぐ（INV-200, ARC-403）
	var before_swap := _pairs(inv)
	t.check("I02", false, _rules.apply(swap, inv))
	t.check("I02", before_swap, _pairs(inv))
	t.check("I02", true, _rules.apply(swap, inv, c))
	t.check("I02", &"sword_2", c.equipment[&"weapon"])
	t.check("I02", CAPACITY, _rules.slot_count(_db, inv))

	# 31枠目を要する取り外しは失敗し、何も変更しない
	var before := _pairs(inv)
	var unequip: Dictionary = _rules.plan_equip(_db, inv, c, &"armor", &"")
	t.check("I02", false, unequip.ok)
	t.check("I02", NO_SPACE, unequip.error_code)
	t.check("I02", {}, unequip.changes)
	t.check("I02", false, _rules.apply(unequip, inv, c))
	t.check("I02", before, _pairs(inv))
	t.check("I02", &"cloth", c.equipment[&"armor"])

	# 空きが1枠あれば、取り外せる。外した品は所持品の枠に数える
	var roomy := _filler(CAPACITY - 1)
	var ok_unequip: Dictionary = _rules.plan_equip(_db, roomy, c, &"armor", &"")
	t.check("I02", true, ok_unequip.ok)
	t.check("I02", CAPACITY, _rules.slot_count(_db, ok_unequip.changes.inventory))
	t.check("I02", &"", ok_unequip.changes.equipment[&"armor"])
	t.check("I02", true, _rules.apply(ok_unequip, roomy, c))
	t.check("I02", &"", c.equipment[&"armor"])

	# 空の枠への装備は、所持品の枠を1つ空ける
	var from_full := _filler(CAPACITY - 1)
	from_full.append(_stack(&"vitality_ring", 1))
	var wear: Dictionary = _rules.plan_equip(_db, from_full, c, &"accessory", &"vitality_ring")
	t.check("I02", true, wear.ok)
	t.check("I02", CAPACITY - 1, _rules.slot_count(_db, wear.changes.inventory))

	# 外す品がない枠の取り外しは INVALID_TARGET
	var empty_slot: Dictionary = _rules.plan_equip(_db, [], c, &"accessory", &"")
	t.check("I02", false, empty_slot.ok)
	t.check("I02", INVALID_TARGET, empty_slot.error_code)


# I05: 最大HPが下がる装備と上がる装備へ変更する（INV-304, INV-305）
func _i05(t) -> void:
	var ring: EquipmentDef = _db.equipment(&"vitality_ring")
	var charm: EquipmentDef = _db.equipment(&"speed_charm")

	# 上がる場合は、現在HPを増やさない
	var c = _character(&"warrior")
	var base_hp: int = c.base_stats.hp
	c.current_hp = base_hp - 5
	var inv := [_stack(&"vitality_ring", 1)]
	var up: Dictionary = _rules.plan_equip(_db, inv, c, &"accessory", &"vitality_ring")
	t.check("I05", true, up.ok)
	t.check("I05", base_hp - 5, up.changes.current_hp)
	t.check("I05", true, _rules.apply(up, inv, c))
	t.check("I05", base_hp - 5, c.current_hp)
	t.check("I05", base_hp + ring.stat_bonus.hp, _rules.effective_stats(_db, c).hp)
	# 満タンからでも、現在HPは増えない
	var full = _character(&"warrior")
	var full_inv := [_stack(&"vitality_ring", 1)]
	_rules.apply(_rules.plan_equip(_db, full_inv, full, &"accessory", &"vitality_ring"), full_inv, full)
	t.check("I05", base_hp, full.current_hp)

	# 下がる場合は、現在HPを新しい最大HPへ丸める
	full.current_hp = base_hp + ring.stat_bonus.hp
	var down: Dictionary = _rules.plan_equip(_db, [], full, &"accessory", &"")
	t.check("I05", true, down.ok)
	t.check("I05", base_hp, down.changes.current_hp)
	t.check("I05", true, _rules.apply(down, [], full))
	t.check("I05", base_hp, full.current_hp)
	# 別の装飾品への交換でも、最大HPが下がれば丸める
	var wearing = _character(&"warrior")
	wearing.equipment[&"accessory"] = &"vitality_ring"
	wearing.current_hp = base_hp + ring.stat_bonus.hp
	var swapped: Dictionary = _rules.plan_equip(_db, [_stack(&"speed_charm", 1)], wearing, &"accessory", &"speed_charm")
	t.check("I05", true, swapped.ok)
	t.check("I05", base_hp + charm.stat_bonus.hp, swapped.changes.current_hp)
	# 新しい最大HP以下の現在HPは、そのまま残る
	wearing.current_hp = 3
	var low: Dictionary = _rules.plan_equip(_db, [], wearing, &"accessory", &"")
	t.check("I05", 3, low.changes.current_hp)
	# 死亡している冒険者の装備も変更できる（INV-204）。現在HPは0のまま
	wearing.current_hp = 0
	var dead: Dictionary = _rules.plan_equip(_db, [], wearing, &"accessory", &"")
	t.check("I05", true, dead.ok)
	t.check("I05", 0, dead.changes.current_hp)

	# 最大SPも同様（INV-305）。SPの補正を持つ装備は現行データにないため、差し替えのデータベースで確かめる
	var sp_ring := EquipmentDef.new()
	sp_ring.id = &"sp_ring"
	sp_ring.slot = &"accessory"
	sp_ring.allowed_jobs = [&"mage"]
	sp_ring.stat_bonus = StatBlock.new()
	sp_ring.stat_bonus.sp = 10
	var stub := StubDb.new()
	stub.add(sp_ring)
	var mage = _character(&"mage")
	var base_sp: int = mage.base_stats.sp
	var sp_inv := [_stack(&"sp_ring", 1)]
	var sp_up: Dictionary = _rules.plan_equip(stub, sp_inv, mage, &"accessory", &"sp_ring")
	t.check("I05", true, sp_up.ok)
	t.check("I05", base_sp, sp_up.changes.current_sp)
	_rules.apply(sp_up, sp_inv, mage)
	t.check("I05", base_sp + 10, _rules.effective_stats(stub, mage).sp)
	mage.current_sp = base_sp + 10
	var sp_down: Dictionary = _rules.plan_equip(stub, [], mage, &"accessory", &"")
	t.check("I05", base_sp, sp_down.changes.current_sp)


# I06: 職業が装備できない品を装備しようとする（INV-301）
func _i06(t) -> void:
	var c = _character(&"warrior")
	var inv := [_stack(&"spear_1", 1), _stack(&"robe", 1), _stack(&"staff_1", 1)]
	var before_inv := _pairs(inv)
	var before_equipment: Dictionary = c.equipment.duplicate()

	# 戦士は騎士の槍、術師の衣を装備できない。拒否し、装備と所持品のいずれも変更しない
	for target in [[&"weapon", &"spear_1"], [&"armor", &"robe"], [&"weapon", &"staff_1"]]:
		var plan: Dictionary = _rules.plan_equip(_db, inv, c, target[0], target[1])
		t.check("I06", false, plan.ok)
		t.check("I06", INVALID_TARGET, plan.error_code)
		t.check("I06", {}, plan.changes)
		t.check("I06", false, _rules.apply(plan, inv, c))
		t.check("I06", before_inv, _pairs(inv))
		t.check("I06", before_equipment, c.equipment)

	# 枠の違う品、所持していない品も INVALID_TARGET
	var wrong_slot: Dictionary = _rules.plan_equip(_db, [_stack(&"mail", 1)], c, &"weapon", &"mail")
	t.check("I06", INVALID_TARGET, wrong_slot.error_code)
	var not_owned: Dictionary = _rules.plan_equip(_db, [], c, &"weapon", &"sword_2")
	t.check("I06", INVALID_TARGET, not_owned.error_code)
	var not_equipment: Dictionary = _rules.plan_equip(_db, [_stack(&"herb", 1)], c, &"weapon", &"herb")
	t.check("I06", INVALID_TARGET, not_equipment.error_code)
	var unknown_slot: Dictionary = _rules.plan_equip(_db, inv, c, &"shield", &"")
	t.check("I06", INVALID_TARGET, unknown_slot.error_code)

	# 装備できる品は、同じ操作で成立する
	var priest = _character(&"priest")
	var staff_inv := [_stack(&"staff_2", 1)]
	t.check("I06", true, _rules.plan_equip(_db, staff_inv, priest, &"weapon", &"staff_2").ok)


# I08: 各職業の冒険者に装備を着脱し、能力値・攻撃力・守備力を求める（BTL-002, BTL-003, INV-309, PTY-211, PTY-311）
func _i08(t) -> void:
	for job in _db.jobs():
		var c = _character(job.id)
		var snapshot := _stat_values(job.base_stats)
		t.check("I08", true, job.base_stats.hp > 0)
		_check_derived(t, c)

		for cycle in 2:
			for equipment in _db.equipment_list():
				if not equipment.allowed_jobs.has(job.id):
					continue
				var inv := [_stack(equipment.id, 1)]
				var plan: Dictionary = _rules.plan_equip(_db, inv, c, equipment.slot, equipment.id)
				t.check("I08", true, plan.ok)
				t.check("I08", true, _rules.apply(plan, inv, c))
				t.check("I08", equipment.id, c.equipment[equipment.slot])
				_check_derived(t, c)
				# 着脱を繰り返しても、基礎能力は変わらない（PTY-211）
				t.check("I08", snapshot, _stat_values(c.base_stats))

		# すべて外した状態：武器の攻撃力と防具の防御力を0として計算する（INV-306, INV-307）
		var bare_inv := []
		for slot in SLOTS:
			var plan: Dictionary = _rules.plan_equip(_db, bare_inv, c, slot, &"")
			t.check("I08", true, plan.ok)
			t.check("I08", true, _rules.apply(plan, bare_inv, c))
		_check_derived(t, c)
		t.check("I08", job.base_stats.str, _rules.attack_power(_db, c))
		t.check("I08", job.base_stats.vit, _rules.defense_power(_db, c))
		t.check("I08", snapshot, _stat_values(c.base_stats))

		# 算出した能力値を書き換えても、基礎能力へ影響しない（装備補正は別に管理する）
		var effective: StatBlock = _rules.effective_stats(_db, c)
		effective.hp += 100
		t.check("I08", snapshot, _stat_values(c.base_stats))


## 冒険者の能力値・攻撃力・守備力を、データと BTL-003 の式から求めた期待値と比べる
func _check_derived(t, c) -> void:
	var expected := _expected_stats(c)
	var effective: StatBlock = _rules.effective_stats(_db, c)
	t.check("I08", expected, _stat_values(effective))
	var weapon: EquipmentDef = _db.equipment(c.equipment[&"weapon"]) if c.equipment[&"weapon"] != &"" else null
	var armor: EquipmentDef = _db.equipment(c.equipment[&"armor"]) if c.equipment[&"armor"] != &"" else null
	# 攻撃力は STR + 武器の攻撃力。守備力は、装飾品を含む装備のVIT補正を加えた VIT + 防具の防御力
	t.check("I08", expected["str"] + (weapon.attack if weapon != null else 0), _rules.attack_power(_db, c))
	t.check("I08", expected["vit"] + (armor.defense if armor != null else 0), _rules.defense_power(_db, c))


## 基礎能力に、装備中の3つの品の `stat_bonus` を加えた値（INV-309）
func _expected_stats(c) -> Dictionary:
	var result := _stat_values(c.base_stats)
	for slot in SLOTS:
		var id: StringName = c.equipment[slot]
		if id == &"":
			continue
		var bonus := _stat_values(_db.equipment(id).stat_bonus)
		for field in STAT_FIELDS:
			result[field] += bonus[field]
	return result


func _stat_values(block: StatBlock) -> Dictionary:
	var values := {}
	for field in STAT_FIELDS:
		values[field] = block.get(field)
	return values


## 職業の基礎能力で作る冒険者。初期武器と布の服を装備し、HPとSPは満タン（PTY-009, PTY-010）
func _character(job_id: StringName):
	var job: JobDef = _db.job(job_id)
	var c = load(CHARACTER_SCRIPT).new()
	c.job_id = job_id
	c.base_stats = job.base_stats.duplicate()
	c.current_hp = job.base_stats.hp
	c.current_sp = job.base_stats.sp
	c.equipment = {&"weapon": job.starting_weapon_id, &"armor": job.starting_armor_id, &"accessory": &""}
	return c


func _stack(id: StringName, quantity: int):
	return load(STACK_SCRIPT).new(id, quantity)


func _def(id: StringName, quantity: int) -> ItemStackDef:
	var def := ItemStackDef.new()
	def.item_id = id
	def.quantity = quantity
	return def


## `cloth` の1枠の品を `count` 個。枠の埋め草
func _filler(count: int) -> Array:
	var stacks := []
	for i in count:
		stacks.append(_stack(&"cloth", 1))
	return stacks


func _pairs(stacks: Array) -> Array:
	var pairs := []
	for stack in stacks:
		pairs.append([stack.item_id, stack.quantity])
	return pairs
