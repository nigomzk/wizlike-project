extends RefCounted
## TST-408: テスト基盤（T）のテスト。フィクスチャを子プロセスの Godot で実行し、終了コードと出力を判定する。

const IDS := ["T01", "T02", "T03", "T04"]

const FIXTURE_PASS := "res://tests/fixtures/fixture_pass.gd"
const FIXTURE_FAIL := "res://tests/fixtures/fixture_fail.gd"
const FIXTURE_SKIP := "res://tests/fixtures/fixture_skip.gd"
const FIXTURE_CRASH := "res://tests/fixtures/fixture_crash.gd"
const FIXTURE_CRASH_NESTED := "res://tests/fixtures/fixture_crash_nested.gd"
const FIXTURE_COMPLETE := "res://tests/fixtures/fixture_complete.gd"


func run(t) -> void:
	_t01(t)
	_t02(t)
	_t03(t)
	_t04(t)


## 子プロセスの Godot で run_all.gd を実行する。`{exit_code, output}` を返す。
func _run_child(files: String, extra_args: Array = []) -> Dictionary:
	var args: Array = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/run_all.gd",
		"--",
		"--files=" + files,
	]
	args.append_array(extra_args)
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray(args), output, true)
	return {"exit_code": exit_code, "output": "".join(output), "args": args}


# T01: 全件が成功するフィクスチャを実行する（TST-002, 003, 005）
func _t01(t) -> void:
	var r := _run_child(FIXTURE_PASS)
	t.check("T01", 0, r.exit_code)
	# 0件の実行で成功になる抜け道を塞ぐため、フィクスチャの2件が成功したことも確かめる
	t.check("T01", true, "passed=2 failed=0" in r.output)
	# エディターを起動しない（TST-005）: --headless --script で、エディターなしに完走して終了コードを返すこと自体が根拠になる


# T02: 1件だけ失敗するフィクスチャを実行する（TST-003, 004）
func _t02(t) -> void:
	var r := _run_child(FIXTURE_FAIL)
	t.check("T02", true, r.exit_code != 0 and r.exit_code != -1)
	t.check("T02", true, "X02" in r.output)
	t.check("T02", true, "expected=1" in r.output)
	t.check("T02", true, "actual=2" in r.output)
	# 成功したIDは失敗として出さない
	t.check("T02", false, "FAIL X01" in r.output)


# T03: スキップを含むフィクスチャを --require なしと、スキップしたIDを --require に指定して実行する（TST-006, 410, 411）
func _t03(t) -> void:
	var plain := _run_child(FIXTURE_SKIP)
	t.check("T03", 0, plain.exit_code)
	# スキップは成功件数に数えられず、一覧で報告される（明示のスキップも、報告がなくIDSにだけあるものも）
	t.check("T03", true, "passed=1" in plain.output)
	t.check("T03", true, "skipped=2" in plain.output)
	t.check("T03", true, "SKIP X02" in plain.output)
	t.check("T03", true, "SKIP X03" in plain.output)

	var required_skip := _run_child(FIXTURE_SKIP, ["--require=X02"])
	t.check("T03", true, required_skip.exit_code != 0 and required_skip.exit_code != -1)
	var required_unreported := _run_child(FIXTURE_SKIP, ["--require=X03"])
	t.check("T03", true, required_unreported.exit_code != 0 and required_unreported.exit_code != -1)
	# 成功したIDを指定した場合は0のまま
	var required_pass := _run_child(FIXTURE_SKIP, ["--require=X01"])
	t.check("T03", 0, required_pass.exit_code)


# T04: 実行時エラーで打ち切られるフィクスチャを実行する（TST-003, 006, 007）
func _t04(t) -> void:
	for fixture in [FIXTURE_CRASH, FIXTURE_CRASH_NESTED]:
		# --require 付き
		var required := _run_child(fixture, ["--require=X01,X02"])
		t.check("T04", true, _is_failure_exit(required.exit_code))
		t.check("T04", true, "SUMMARY" in required.output)
		# --require なしでも非0。失敗したIDと打ち切りの旨が出る
		var plain := _run_child(fixture)
		t.check("T04", true, _is_failure_exit(plain.exit_code))
		t.check("T04", true, "SUMMARY" in plain.output)
		t.check("T04", true, "ABORT" in plain.output)
		# 1回でも check が成功したIDも、実行されなかったIDも、成功にも未実装のスキップにもならない
		for id in ["X01", "X02", "X03"]:
			t.check("T04", true, ("FAIL " + id) in plain.output)
		t.check("T04", true, "passed=0 failed=3 skipped=0" in plain.output)

	# 打ち切られたファイルは、ほかのファイルの判定を止めない
	var mixed := _run_child("%s,%s" % [FIXTURE_CRASH, FIXTURE_COMPLETE])
	t.check("T04", true, _is_failure_exit(mixed.exit_code))
	t.check("T04", true, "passed=1 failed=3 skipped=0" in mixed.output)
	t.check("T04", false, "FAIL Y01" in mixed.output)
	# 打ち切られたファイルが後ろにあっても、前の完走ファイルは成功のまま
	var reversed := _run_child("%s,%s" % [FIXTURE_COMPLETE, FIXTURE_CRASH_NESTED])
	t.check("T04", true, _is_failure_exit(reversed.exit_code))
	t.check("T04", true, "passed=1 failed=3 skipped=0" in reversed.output)


## 終了コードが、失敗（非0）として正しく返されたか。0でも、プロセスの起動失敗（-1）でもない
func _is_failure_exit(exit_code: int) -> bool:
	return exit_code != 0 and exit_code != -1
