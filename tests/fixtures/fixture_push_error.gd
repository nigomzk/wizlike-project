extends RefCounted
## T04 用フィクスチャ。push_error と push_warning を出すが、スクリプトの実行時エラーではないので、打ち切りとして扱わない。

const IDS := ["Z01"]


func run(t) -> void:
	push_error("fixture intentional error")
	push_warning("fixture intentional warning")
	t.check("Z01", 1, 1)
