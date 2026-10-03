extends RefCounted
## T04 用フィクスチャ。打ち切られるフィクスチャと同時に実行しても、IDSが重複しない完走する1件。

const IDS := ["Y01"]


func run(t) -> void:
	t.check("Y01", 1, 1)
