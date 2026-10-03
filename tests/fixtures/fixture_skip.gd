extends RefCounted
## T03 用フィクスチャ。X01 は成功、X02 は明示的なスキップ、X03 は報告なし（自動でスキップ）。

const IDS := ["X01", "X02", "X03"]


func run(t) -> void:
	t.check("X01", 1, 1)
	t.skip("X02", "fixture skip")
