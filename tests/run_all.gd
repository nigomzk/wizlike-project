extends SceneTree
## テストの入口（TST-001）。
##
## godot --headless --path . --script tests/run_all.gd [-- --require=ID,ID,...] [--files=res://a.gd,res://b.gd]
##
## 各テストファイルは `extends RefCounted`、`const IDS`、`func run(t)` を持つ（TST-413）。
## `t` には `check(id, expected, actual)` と `skip(id, reason)` がある。
## `run()` の実行中にスクリプトの実行時エラーが起きたファイルは、`skip()` 済み以外の全IDを失敗とする（TST-007）。

const TEST_FILES := [
	"res://tests/test_maps.gd",
	"res://tests/test_growth.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_battle.gd",
	"res://tests/test_save.gd",
	"res://tests/test_facility.gd",
	"res://tests/test_flow.gd",
	"res://tests/test_exploration.gd",
	"res://tests/test_runner.gd",
	"res://tests/test_core.gd",
]

const PASSED := "passed"
const FAILED := "failed"
const SKIPPED := "skipped"


## スクリプトの実行時エラーの件数を数える（TST-007）。`push_error` と `push_warning` は数えない。
## `_log_error` は複数のスレッドから呼ばれうるため、`Mutex` で守る。
class ScriptErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var _count := 0

	func _log_error(
			_function: String,
			_file: String,
			_line: int,
			_code: String,
			_rationale: String,
			_editor_notify: bool,
			error_type: int,
			_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_count += 1
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var n := _count
		_mutex.unlock()
		return n


## ID -> PASSED / FAILED / SKIPPED。IDSに列挙された全IDが入る
var _status: Dictionary = {}
## ID -> スキップの理由
var _skip_reasons: Dictionary = {}
## 現在実行中のテストファイルのIDS
var _declared: Array = []
## 実行時エラーで打ち切られたテストファイルの数
var _aborted_files := 0


func _initialize() -> void:
	var files: Array = TEST_FILES.duplicate()
	var required: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--require="):
			required = _split_ids(arg.trim_prefix("--require="))
		elif arg.begins_with("--files="):
			files = Array(arg.trim_prefix("--files=").split(",", false))

	var load_errors := 0
	for path in files:
		if not _run_file(path):
			load_errors += 1

	quit(_finish(required, load_errors))


func _run_file(path: String) -> bool:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		printerr("ERROR: cannot load test file %s" % path)
		return false
	var test_file = script.new()
	_declared = Array(test_file.IDS)
	for id in _declared:
		if not _status.has(id):
			_status[id] = ""
	var error_counter := ScriptErrorCounter.new()
	OS.add_logger(error_counter)
	test_file.run(self)
	OS.remove_logger(error_counter)
	if error_counter.count() > 0:
		_fail_aborted_file(path, error_counter.count())
		return true
	# 報告されなかったIDは自動でスキップとする（TST-410）
	for id in _declared:
		if _status[id] == "":
			_set_skipped(id, "not reported (not implemented)")
	return true


## 実行時エラーで打ち切られたファイルの、明示的に `skip()` されたもの以外のIDを失敗にする（TST-007）。
func _fail_aborted_file(path: String, error_count: int) -> void:
	_aborted_files += 1
	print("ABORT %s: %d script error(s) during run(); IDs not skipped explicitly are failed" % [path, error_count])
	for id in _declared:
		if _status[id] == SKIPPED:
			continue
		if _status[id] != FAILED:
			_status[id] = FAILED
			print("FAIL %s: aborted by script error in %s" % [id, path])


## 期待値と実測値を比較する。同じIDで複数回呼べる。1回でも不一致なら、そのIDは失敗になる。
func check(id: String, expected: Variant, actual: Variant) -> void:
	if not _status.has(id) or not _declared.has(id):
		_record_failure(id, expected, actual, "undeclared ID")
		return
	if expected == actual:
		# スキップ済みのIDは、後から成功を報告されても成功にしない
		if _status[id] == "":
			_status[id] = PASSED
		return
	_record_failure(id, expected, actual)


## IDを明示的にスキップとして報告する。スキップは成功に数えない（TST-411）。
func skip(id: String, reason: String) -> void:
	if not _status.has(id) or not _declared.has(id):
		_record_failure(id, "declared in IDS", "undeclared ID")
		return
	if _status[id] != FAILED:
		_set_skipped(id, reason)


func _set_skipped(id: String, reason: String) -> void:
	_status[id] = SKIPPED
	_skip_reasons[id] = reason


func _record_failure(id: String, expected: Variant, actual: Variant, note: String = "") -> void:
	_status[id] = FAILED
	var line := "FAIL %s: expected=%s actual=%s" % [id, var_to_str(expected), var_to_str(actual)]
	if note != "":
		line += " (%s)" % note
	print(line)


## 結果を出力し、終了コードを返す（TST-003, 006）。
func _finish(required: Array, load_errors: int) -> int:
	var ids: Array = _status.keys()
	ids.sort()
	var counts := {PASSED: 0, FAILED: 0, SKIPPED: 0}
	for id in ids:
		counts[_status[id]] += 1
	for id in ids:
		if _status[id] == SKIPPED:
			print("SKIP %s: %s" % [id, _skip_reasons[id]])

	var unmet: Array = []
	for id in required:
		if _status.get(id, "") != PASSED:
			unmet.append(id)
			print("REQUIRE %s: %s" % [id, _status.get(id, "unknown")])

	print("SUMMARY passed=%d failed=%d skipped=%d" % [counts[PASSED], counts[FAILED], counts[SKIPPED]])
	if counts[FAILED] > 0 or not unmet.is_empty() or load_errors > 0 or _aborted_files > 0:
		return 1
	return 0


func _split_ids(text: String) -> Array:
	var ids: Array = []
	for part in text.split(",", false):
		ids.append(part.strip_edges())
	return ids
