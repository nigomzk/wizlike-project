extends RefCounted
## T01 用フィクスチャ。全件が成功する。

const IDS := ["X01", "X02"]


func run(t) -> void:
	t.check("X01", 1, 1)
	t.check("X02", "a", "a")
