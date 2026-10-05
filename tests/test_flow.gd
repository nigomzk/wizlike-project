extends RefCounted
## TST-406: 状態遷移（FL）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["FL01", "FL02", "FL03", "FL04", "FL06", "FL07", "FL08", "FL09"]

const MAIN_SCENE := "res://scenes/main.tscn"
const GAME_FLOW_SCRIPT := "res://scripts/core/game_flow.gd"
const TITLE_ITEMS := ["はじめから", "つづきから", "設定", "終了"]
const SLOT_COUNT := 5

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const BACKGROUND_SCENE := "res://scenes/ui/components/screen_background.tscn"
const GAME_THEME := "res://scenes/ui/components/game_theme.tres"
const TITLE_BACKGROUND := "res://assets/backgrounds/title.png"
const MISSING_BACKGROUND := "res://assets/backgrounds/no_such_screen.png"
## FL06 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const FL06_TMP_ROOT := "user://test_flow_fl06"
## 開発者の実際の設定ファイル。FL06 が変更しないことを確かめる（TST-107）
const REAL_SETTINGS_PATH := "user://settings.cfg"
# PRS-300 の色のトークン（bg_base、bg_scrim）
const BG_BASE := Color("#0E1420")
const BG_SCRIM := Color(BG_BASE, 0.35)


## エンジンが出したエラーと警告の件数を数える（FL09。欠落した画像でエンジンの出力が出ないことの確認）。
## `_log_error` は複数のスレッドから呼ばれうるため、`Mutex` で守る。
class EngineLogCounter extends Logger:
	var _mutex := Mutex.new()
	var _count := 0

	func _log_error(
			_function: String,
			_file: String,
			_line: int,
			_code: String,
			_rationale: String,
			_editor_notify: bool,
			_error_type: int,
			_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		_count += 1
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var n := _count
		_mutex.unlock()
		return n


func run(t) -> void:
	await _fl06(t)
	await _fl07(t)
	await _fl09(t)


# FL06: TITLEから設定を開いて変更し、閉じる（FLW-111〜113, FLW-301, PRS-000, PRS-400〜402, PRS-405, PRS-108）。
# 確かめるのは TITLE 側だけである。MENUから開く部分は MENU の実装（#14）で確かめるため、FL06 は成功にせずスキップのまま残す（TST-411）。
func _fl06(t) -> void:
	var real_before := _file_state(REAL_SETTINGS_PATH)
	_remove_dir(FL06_TMP_ROOT)
	_fl06_game_flow(t)
	await _fl06_screen(t)
	_remove_dir(FL06_TMP_ROOT)
	t.check("FL06", real_before, _file_state(REAL_SETTINGS_PATH))
	t.skip("FL06", "MENUから開く部分（FLW-111, FLW-113）は #14 で判定する。TITLE側だけを確かめた")


## GameFlow だけで、設定の初期値・保存・再読込・F11・最小サイズを確かめる。
func _fl06_game_flow(t) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	t.check("FL06", true, script != null)
	if script == null:
		return
	var s = script.State
	var path := FL06_TMP_ROOT + "/settings.cfg"
	var applied := []
	var flow: Node = _new_flow(script, path, applied)
	var changes := [0]
	flow.settings_changed.connect(func(): changes[0] += 1)
	t.root.add_child(flow)

	# 設定ファイルがなくても起動できる。初期値は音量70、フルスクリーンOFF。起動だけではファイルを作らない（PRS-400, PRS-405）
	t.check("FL06", s.TITLE, flow.state)
	t.check("FL06", 70, flow.master_volume)
	t.check("FL06", false, flow.fullscreen)
	t.check("FL06", false, FileAccess.file_exists(path))
	# 起動時にマスターバスへ音量を反映する。OFFのときは、コマンドラインの `--fullscreen` を打ち消さないよう、ウィンドウに触れない（PRS-401）
	t.check("FL06", true, _bus_volume_is(70))
	t.check("FL06", false, AudioServer.is_bus_mute(0))
	t.check("FL06", [], applied)
	# ウィンドウの最小サイズは960×540（PRS-000）
	t.check("FL06", Vector2i(960, 540), t.root.min_size)

	# TITLEから開ける。セッションは存在しない（FLW-111, FLW-112, PRS-405）
	t.check("FL06", true, flow.open_settings())
	t.check("FL06", s.SETTINGS, flow.state)
	t.check("FL06", false, flow.has_session())

	# 音量を変更すると、即時に反映して保存する。範囲は0〜100に収める（PRS-400, PRS-401）
	t.check("FL06", 0, changes[0])
	flow.set_master_volume(30)
	t.check("FL06", 30, flow.master_volume)
	t.check("FL06", true, _bus_volume_is(30))
	t.check("FL06", {"volume": 30, "fullscreen": false}, _read_settings(script, path))
	t.check("FL06", 1, changes[0])
	flow.set_master_volume(150)
	t.check("FL06", 100, flow.master_volume)
	t.check("FL06", true, _bus_volume_is(100))
	flow.set_master_volume(-5)
	t.check("FL06", 0, flow.master_volume)
	t.check("FL06", true, AudioServer.is_bus_mute(0))
	t.check("FL06", {"volume": 0, "fullscreen": false}, _read_settings(script, path))
	flow.set_master_volume(30)
	t.check("FL06", false, AudioServer.is_bus_mute(0))

	# フルスクリーンを切り替えると、即時に反映して保存する（PRS-001, PRS-401）
	flow.set_fullscreen(true)
	t.check("FL06", true, flow.fullscreen)
	t.check("FL06", [true], applied)
	t.check("FL06", {"volume": 30, "fullscreen": true}, _read_settings(script, path))

	# 設定の変更で、セッションも状態も変わらない。設定はセーブスロットの置き場所に作らない（FLW-301, PRS-402）
	t.check("FL06", false, flow.has_session())
	t.check("FL06", s.SETTINGS, flow.state)
	t.check("FL06", false, DirAccess.dir_exists_absolute(flow.save_dir))
	# 閉じるとTITLEへ戻る。TOWNへは遷移しない（FLW-113）
	t.check("FL06", true, flow.go_back())
	t.check("FL06", s.TITLE, flow.state)
	t.check("FL06", false, flow.has_session())

	# 再起動に見立てて読み直すと、値が保持されている。フルスクリーンONは起動時に反映する（PRS-401, PRS-405）
	var applied_again := []
	var again: Node = _new_flow(script, path, applied_again)
	t.root.add_child(again)
	t.check("FL06", 30, again.master_volume)
	t.check("FL06", true, again.fullscreen)
	t.check("FL06", [true], applied_again)
	t.check("FL06", true, _bus_volume_is(30))
	t.root.remove_child(again)
	again.free()

	# F11 は、どの画面でも、入力の遮断中でも、フルスクリーンを切り替えて保存する（PRS-108）
	t.root.push_input(_key_event(KEY_F11))
	t.check("FL06", false, flow.fullscreen)
	t.check("FL06", [true, false], applied)
	t.check("FL06", {"volume": 30, "fullscreen": false}, _read_settings(script, path))
	t.check("FL06", true, flow.open_settings())
	t.root.push_input(_key_event(KEY_F11))
	t.check("FL06", [true, false, true], applied)
	t.check("FL06", s.SETTINGS, flow.state)
	flow.go_back()
	flow.block_input(&"modal")
	t.root.push_input(_key_event(KEY_F11))
	t.check("FL06", [true, false, true, false], applied)
	flow.unblock_input(&"modal")
	# キーの押しっぱなし（echo）と、F11 以外のキーでは切り替えない
	var held := _key_event(KEY_F11)
	held.echo = true
	t.root.push_input(held)
	t.root.push_input(_key_event(KEY_F10))
	t.check("FL06", [true, false, true, false], applied)
	t.check("FL06", false, flow.fullscreen)
	t.root.remove_child(flow)
	flow.free()

	# 読めないファイルと、範囲外・型違いの値は、初期値か範囲内の値に直す（PRS-400）
	var broken := FL06_TMP_ROOT + "/broken.cfg"
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("[settings\nmaster_volume = = =\n")
	file.close()
	var cases := [
		[broken, 70, false],
		[_write_settings(script, "range_high", 250, true), 100, true],
		[_write_settings(script, "range_low", -3, false), 0, false],
		[_write_settings(script, "float", 55.0, false), 55, false],
		[_write_settings(script, "wrong_type", "loud", "yes"), 70, false],
	]
	for c in cases:
		var loaded: Node = _new_flow(script, c[0], [])
		t.root.add_child(loaded)
		t.check("FL06", c[1], loaded.master_volume)
		t.check("FL06", c[2], loaded.fullscreen)
		t.root.remove_child(loaded)
		loaded.free()


## main.tscn の配線のまま、設定画面の表示・操作・戻るを確かめる（FLW-111〜113, FLW-014, PRS-400, PRS-401, PRS-104, PRS-108, ARC-204, ARC-205）。
func _fl06_screen(t) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("FL06", true, packed != null)
	if packed == null or script == null:
		return
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("FL06", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	var s = flow.State
	var path := FL06_TMP_ROOT + "/screen.cfg"
	var applied := []
	flow.save_dir = FL06_TMP_ROOT + "/saves"
	flow.settings_path = path
	flow.fullscreen_handler = func(on: bool): applied.append(on)
	t.root.add_child(main)
	await t.process_frame

	# TITLEの「設定」から開く。仮画面ではなく、設定画面が出る（FLW-111, PRS-208）
	_press(host.current_screen, "設定")
	await t.process_frame
	t.check("FL06", s.SETTINGS, flow.state)
	var screen: Control = host.current_screen
	var volume := screen.get_node_or_null("%Volume") as HSlider
	var volume_value := screen.get_node_or_null("%VolumeValue") as Label
	var fullscreen := screen.get_node_or_null("%Fullscreen") as Button
	var back := screen.get_node_or_null("%Back") as Button
	t.check("FL06", true, volume != null and volume_value != null and fullscreen != null and back != null)
	if volume == null or volume_value == null or fullscreen == null or back == null:
		_free_main(t, main)
		return
	t.check("FL06", false, _label_texts(screen).has("準備中"))

	# 項目：マスター音量（0〜100、1刻み、初期値70）、フルスクリーン（初期値OFF）、戻る（PRS-400, FLW-014）
	t.check("FL06", ["マスター音量", "70", "フルスクリーン"], _label_texts(screen))
	t.check("FL06", [0.0, 100.0, 1.0, 70.0], [volume.min_value, volume.max_value, volume.step, volume.value])
	t.check("FL06", ["OFF", false], [fullscreen.text, fullscreen.button_pressed])
	t.check("FL06", "戻る", back.text)
	t.check("FL06", true, volume.has_focus())
	# ↑ / ↓ も Tab / Shift+Tab と同じく、端から反対の端へ巡回する（PRS-107）
	var items: Array[Control] = [volume, fullscreen, back]
	for i in items.size():
		t.check("FL06", items[(i + 1) % items.size()], items[i].find_valid_focus_neighbor(SIDE_BOTTOM))
		t.check("FL06", items[(i + items.size() - 1) % items.size()], items[i].find_valid_focus_neighbor(SIDE_TOP))
		t.check("FL06", items[(i + 1) % items.size()], items[i].find_next_valid_focus())

	# スライダーで1刻みに変えると、GameFlow が受けて、数値の表示も変わる。保存される（PRS-401）
	volume.value = 41
	t.check("FL06", 41, flow.master_volume)
	t.check("FL06", "41", volume_value.text)
	t.check("FL06", {"volume": 41, "fullscreen": false}, _read_settings(script, path))

	# 左右キーで5ずつ増減する。1刻みの標準の動作と二重にならない。0と100を超えない（PRS-400）
	t.root.push_input(_key_event(KEY_LEFT))
	t.check("FL06", 36, flow.master_volume)
	t.root.push_input(_key_event(KEY_RIGHT))
	t.root.push_input(_key_event(KEY_RIGHT))
	t.check("FL06", 46, flow.master_volume)
	t.check("FL06", 46.0, volume.value)
	t.check("FL06", "46", volume_value.text)
	volume.value = 98
	t.root.push_input(_key_event(KEY_RIGHT))
	t.check("FL06", 100, flow.master_volume)
	volume.value = 2
	t.root.push_input(_key_event(KEY_LEFT))
	t.check("FL06", 0, flow.master_volume)
	t.check("FL06", "0", volume_value.text)

	# フルスクリーンの切替：ON / OFF の文字で示し、反映して保存する（PRS-001, PRS-006, PRS-401）
	fullscreen.button_pressed = true
	t.check("FL06", true, flow.fullscreen)
	t.check("FL06", [true], applied)
	t.check("FL06", "ON", fullscreen.text)
	t.check("FL06", {"volume": 0, "fullscreen": true}, _read_settings(script, path))
	# 設定画面を開いたまま F11 を押すと、表示も追従する。画面が値のコピーを持たない（ARC-204, ARC-205, PRS-108）
	t.root.push_input(_key_event(KEY_F11))
	t.check("FL06", false, flow.fullscreen)
	t.check("FL06", [false, "OFF"], [fullscreen.button_pressed, fullscreen.text])
	flow.set_master_volume(65)
	t.check("FL06", [65.0, "65"], [volume.value, volume_value.text])
	t.check("FL06", s.SETTINGS, flow.state)

	# 「戻る」でTITLEへ戻る。セッションは存在しない（FLW-113, FLW-112）
	_press(screen, "戻る")
	await t.process_frame
	t.check("FL06", s.TITLE, flow.state)
	t.check("FL06", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))
	t.check("FL06", false, flow.has_session())

	# 開き直すと、同じ値が出る。Esc でもTITLEへ戻る（PRS-104）
	_press(host.current_screen, "設定")
	await t.process_frame
	screen = host.current_screen
	t.check("FL06", [65.0, "65"], [screen.get_node("%Volume").value, screen.get_node("%VolumeValue").text])
	t.check("FL06", true, screen.get_node("%Volume").has_focus())
	t.root.push_input(_action_event(&"ui_cancel"))
	t.check("FL06", s.TITLE, flow.state)
	t.check("FL06", false, flow.has_session())

	# 入力の遮断中は、設定画面を開けない（FLW-200）
	flow.block_input(&"modal")
	t.check("FL06", false, flow.open_settings())
	flow.unblock_input(&"modal")

	_free_main(t, main)


# FL07: TITLEで各項目を選ぶ（FLW-001, FLW-108, FLW-112, SAV-003）
func _fl07(t) -> void:
	var tmp_root := "user://test_flow_fl07"
	var save_dir := tmp_root + "/saves"
	_make_slots(save_dir)
	var before := _snapshot(save_dir)
	t.check("FL07", SLOT_COUNT, before.size())

	_fl07_game_flow(t, save_dir, before)
	await _fl07_screens(t, save_dir, before)

	_remove_dir(tmp_root)


## GameFlow だけで、状態・入力遮断・終了の差し替え点を確かめる（FLW-204, TST-106, TST-107）。
func _fl07_game_flow(t, save_dir: String, before: Dictionary) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	t.check("FL07", true, script != null)
	if script == null:
		return
	var s = script.State
	var flow: Node = script.new()
	flow.save_dir = save_dir
	flow.settings_path = save_dir.get_base_dir() + "/settings.cfg"
	var quits := [0]
	flow.quit_handler = func(): quits[0] += 1
	var history: Array = []
	flow.state_changed.connect(func(new_state, old_state): history.append([old_state, new_state]))
	t.root.add_child(flow)

	# 起動するとTITLEになる。TITLEの間はセッションが存在しない（FLW-108, FLW-112）
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", false, flow.has_session())

	# 「はじめから」→ NEW_GAME。既存スロットは変更されない（FLW-002, SAV-003）
	t.check("FL07", true, flow.request_new_game())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", before, _snapshot(save_dir))
	# NEW_GAME から「はじめから」や「つづきから」は受け付けない（FLW-102）
	t.check("FL07", false, flow.request_new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", false, flow.has_session())

	# 「つづきから」→ LOAD。有効なセーブがなくても選べる（FLW-003）
	t.check("FL07", true, flow.open_load())
	t.check("FL07", s.LOAD, flow.state)
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)

	# 「設定」→ SETTINGS。閉じるとTITLEへ戻る。TOWNへは遷移しない（FLW-111, FLW-112, FLW-113）
	t.check("FL07", true, flow.open_settings())
	t.check("FL07", s.SETTINGS, flow.state)
	t.check("FL07", false, flow.has_session())
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)
	# TITLEとMENU以外からSETTINGSは開けない（FLW-111）
	t.check("FL07", true, flow.request_new_game())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.NEW_GAME, flow.state)
	flow.go_back()

	# 「終了」→ 差し替えた終了要求が1回呼ばれる。ランナーは止まらない（FLW-001, TST-106）
	t.check("FL07", 0, quits[0])
	flow.quit_app()
	t.check("FL07", 1, quits[0])

	# 遷移の履歴：TITLEを起点に、押した順にたどる
	t.check("FL07", [
		[s.BOOT, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TITLE],
		[s.TITLE, s.LOAD], [s.LOAD, s.TITLE],
		[s.TITLE, s.SETTINGS], [s.SETTINGS, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TITLE],
	], history)

	# 入力遮断は理由の集合で保持する。1つでも残っている間は遮断が続き、遷移の要求を受け付けない（FLW-204）
	t.check("FL07", false, flow.is_input_blocked())
	flow.block_input(&"modal")
	flow.block_input(&"animation")
	t.check("FL07", true, flow.is_input_blocked())
	t.check("FL07", false, flow.request_new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.TITLE, flow.state)
	flow.unblock_input(&"modal")
	t.check("FL07", true, flow.is_input_blocked())
	flow.unblock_input(&"animation")
	t.check("FL07", false, flow.is_input_blocked())
	t.check("FL07", true, flow.request_new_game())
	flow.go_back()

	t.check("FL07", before, _snapshot(save_dir))
	t.root.remove_child(flow)
	flow.free()


## main.tscn の配線のまま、TITLE画面の4項目と仮画面「準備中」を確かめる（PRS-208, PRS-700）。
func _fl07_screens(t, save_dir: String, before: Dictionary) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("FL07", true, packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("FL07", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	var s = flow.State
	flow.save_dir = save_dir
	flow.settings_path = save_dir.get_base_dir() + "/settings.cfg"
	var quits := [0]
	flow.quit_handler = func(): quits[0] += 1
	t.root.add_child(main)
	# 初期フォーカスは遅延して置かれるため、1フレーム待つ
	await t.process_frame

	# 起動直後のTITLE：ゲーム名と4項目を、この順で表示する（FLW-001, PRS-700）
	t.check("FL07", s.TITLE, flow.state)
	var screen: Control = host.current_screen
	t.check("FL07", true, screen != null)
	if screen != null:
		t.check("FL07", ["迷宮踏査録"], _label_texts(screen))
		var buttons := _buttons(screen)
		t.check("FL07", TITLE_ITEMS, buttons.map(func(b): return b.text))
		# 最初の項目にフォーカスがある（キーボードのみで巡回できる。PRS-007）
		t.check("FL07", true, buttons[0].has_focus())
		# マウスを動かして載せた項目へのフォーカス移動は、ScreenHost の共通の仕組みとして A07 で確かめる（ARC-209）
		# ↑ / ↓ も Tab / Shift+Tab と同じく、端から反対の端へ巡回する（U03）
		for i in buttons.size():
			var next_button: Control = buttons[(i + 1) % buttons.size()]
			var previous_button: Control = buttons[(i + buttons.size() - 1) % buttons.size()]
			t.check("FL07", next_button, buttons[i].find_valid_focus_neighbor(SIDE_BOTTOM))
			t.check("FL07", previous_button, buttons[i].find_valid_focus_neighbor(SIDE_TOP))
			t.check("FL07", next_button, buttons[i].find_next_valid_focus())
			t.check("FL07", previous_button, buttons[i].find_prev_valid_focus())

	# 項目を押して、遷移先と、仮画面「準備中」と戻るを確かめる（PRS-208）
	var expected_states := [s.NEW_GAME, s.LOAD, s.SETTINGS]
	for i in expected_states.size():
		_press(host.current_screen, TITLE_ITEMS[i])
		t.check("FL07", expected_states[i], flow.state)
		if expected_states[i] == s.SETTINGS:
			# 設定は仮画面ではなく、設定画面へ遷移する。中身は FL06 で確かめる（FLW-111）
			t.check("FL07", false, _label_texts(host.current_screen).has("準備中"))
			t.check("FL07", true, host.current_screen.get_node_or_null("%Volume") != null)
			t.check("FL07", false, flow.has_session())
			_press(host.current_screen, "戻る")
			t.check("FL07", s.TITLE, flow.state)
			t.check("FL07", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))
			continue
		var placeholder: Control = host.current_screen
		t.check("FL07", ["準備中"], _label_texts(placeholder))
		t.check("FL07", ["戻る"], _buttons(placeholder).map(func(b): return b.text))
		t.check("FL07", false, flow.has_session())
		await t.process_frame
		t.check("FL07", true, _buttons(placeholder)[0].has_focus())
		if i == 0:
			# Esc でも遷移元へ戻る。画面が差し替わった後に、外れたノードの処理で止まらない（PRS-208）
			t.root.push_input(_action_event(&"ui_cancel"))
		else:
			_press(placeholder, "戻る")
		t.check("FL07", s.TITLE, flow.state)
		t.check("FL07", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))

	# 入力の遮断中は、背景の入力を止める（FLW-200, FLW-204）
	var blocker: Control = host.input_blocker
	t.check("FL07", false, blocker.visible)
	flow.block_input(&"modal")
	t.check("FL07", true, blocker.visible)
	t.check("FL07", Control.MOUSE_FILTER_STOP, blocker.mouse_filter)
	_press(host.current_screen, TITLE_ITEMS[0])
	t.check("FL07", s.TITLE, flow.state)
	flow.unblock_input(&"modal")
	t.check("FL07", false, blocker.visible)

	# 「終了」→ 確認なしで終了要求が呼ばれる（U04）
	t.check("FL07", 0, quits[0])
	_press(host.current_screen, TITLE_ITEMS[3])
	t.check("FL07", 1, quits[0])

	t.check("FL07", before, _snapshot(save_dir))
	t.root.remove_child(main)
	main.free()


# FL09: タイトルの背景画像と、画面背景の部品（PRS-607, PRS-608, PRS-008, PRS-602, FLW-200）
func _fl09(t) -> void:
	# 画像：存在し、Texture2D として読め、1920×1080である（PRS-608）
	t.check("FL09", true, ResourceLoader.exists(TITLE_BACKGROUND))
	var texture: Texture2D = null
	if ResourceLoader.exists(TITLE_BACKGROUND):
		texture = load(TITLE_BACKGROUND) as Texture2D
	t.check("FL09", true, texture != null)
	if texture != null:
		t.check("FL09", Vector2(1920, 1080), texture.get_size())

	# 地と暗幕の色は、共通Theme の Type Variation で持つ（PRS-300, ARC-208）
	var theme := load(GAME_THEME) as Theme
	t.check("FL09", true, theme != null)
	if theme != null:
		for variation in [[&"ScreenBase", BG_BASE], [&"ScreenScrim", BG_SCRIM]]:
			t.check("FL09", &"PanelContainer", theme.get_type_variation_base(variation[0]))
			var style := theme.get_stylebox(&"panel", variation[0]) as StyleBoxFlat
			t.check("FL09", true, style != null)
			if style != null:
				t.check("FL09", true, style.bg_color.is_equal_approx(variation[1]))

	var packed := load(TITLE_SCENE) as PackedScene
	t.check("FL09", true, packed != null)
	if packed == null:
		return
	var title: Control = packed.instantiate()
	t.root.add_child(title)
	await t.process_frame

	# 背景は Center より前の最初の子で、全面に広がる。ゲーム名と4項目は背景の前面にある（PRS-607）
	var background: Control = title.get_child(0)
	var center: Node = title.get_node_or_null("Center")
	t.check("FL09", BACKGROUND_SCENE, background.scene_file_path)
	if background.scene_file_path != BACKGROUND_SCENE:
		t.root.remove_child(title)
		title.free()
		return
	t.check("FL09", true, center != null and background.get_index() < center.get_index())
	t.check("FL09", t.root.get_visible_rect().size, background.size)

	# 背景のすべてのノードが、クリックもフォーカスも受けず、画面を押し広げない（FLW-200, PRS-007）
	var parts: Array = [background] + background.find_children("*", "Control", true, false)
	t.check("FL09", 4, parts.size())
	for part: Control in parts:
		t.check("FL09", Control.MOUSE_FILTER_IGNORE, part.mouse_filter)
		t.check("FL09", Control.FOCUS_NONE, part.focus_mode)
		t.check("FL09", Vector2.ZERO, part.get_combined_minimum_size())

	var base: Control = background.get_node_or_null("%Base")
	var image: TextureRect = background.get_node_or_null("%Image")
	var scrim: Control = background.get_node_or_null("%Scrim")
	t.check("FL09", true, image != null and scrim != null and base != null)
	if image == null or scrim == null or base == null:
		title.free()
		return
	# 下から、地、画像、暗幕の順に重なる。画像は縦横比を保って全面を覆う（PRS-608, PRS-008）
	t.check("FL09", [base, image, scrim], background.get_children())
	t.check("FL09", &"ScreenBase", base.theme_type_variation)
	t.check("FL09", &"ScreenScrim", scrim.theme_type_variation)
	t.check("FL09", TextureRect.EXPAND_IGNORE_SIZE, image.expand_mode)
	t.check("FL09", TextureRect.STRETCH_KEEP_ASPECT_COVERED, image.stretch_mode)

	# 画像がある間は、画像の上に暗幕を重ねる（PRS-008）
	t.check("FL09", TITLE_BACKGROUND, background.texture_path)
	t.check("FL09", texture, image.texture)
	t.check("FL09", [true, true, true], [base.visible, image.visible, scrim.visible])

	# 存在しないパスでは、画像も暗幕も出さず、bg_base の単色になる。実行時エラーを出さない（PRS-607, PRS-602）
	# エンジンのエラーと警告も出さない。この区間の件数を数える（PRS-607）
	t.check("FL09", false, ResourceLoader.exists(MISSING_BACKGROUND))
	var logs := EngineLogCounter.new()
	OS.add_logger(logs)
	background.texture_path = MISSING_BACKGROUND
	t.check("FL09", null, image.texture)
	t.check("FL09", [true, false, false], [base.visible, image.visible, scrim.visible])
	# パスを空にしても同じ。画像のパスを戻すと、再び画像と暗幕が出る
	background.texture_path = ""
	t.check("FL09", [true, false, false], [base.visible, image.visible, scrim.visible])
	background.texture_path = TITLE_BACKGROUND
	t.check("FL09", [true, true, true], [base.visible, image.visible, scrim.visible])

	# 存在しないパスのまま起動した場合も、最初から単色になる
	var missing: Control = load(BACKGROUND_SCENE).instantiate()
	missing.texture_path = MISSING_BACKGROUND
	t.root.add_child(missing)
	await t.process_frame
	t.check("FL09", [true, false, false], [
		missing.get_node("%Base").visible, missing.get_node("%Image").visible, missing.get_node("%Scrim").visible])
	t.root.remove_child(missing)
	missing.free()
	OS.remove_logger(logs)
	t.check("FL09", 0, logs.count())

	t.root.remove_child(title)
	title.free()


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


## 一時的な置き場所を指した、起動前の GameFlow。フルスクリーンの反映は、ウィンドウに触れず `applied` へ記録する（TST-107）。
func _new_flow(script: GDScript, settings_path: String, applied: Array) -> Node:
	var flow: Node = script.new()
	flow.save_dir = FL06_TMP_ROOT + "/saves"
	flow.settings_path = settings_path
	flow.fullscreen_handler = func(on: bool): applied.append(on)
	return flow


## 設定ファイルの内容。`{"volume": ..., "fullscreen": ...}`。読めなければ空。
func _read_settings(script: GDScript, path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return {}
	return {
		"volume": config.get_value(script.SETTINGS_SECTION, script.KEY_MASTER_VOLUME, null),
		"fullscreen": config.get_value(script.SETTINGS_SECTION, script.KEY_FULLSCREEN, null),
	}


## 指定した値で設定ファイルを書き、そのパスを返す。
func _write_settings(script: GDScript, name_: String, volume: Variant, fullscreen: Variant) -> String:
	var path := "%s/%s.cfg" % [FL06_TMP_ROOT, name_]
	DirAccess.make_dir_recursive_absolute(FL06_TMP_ROOT)
	var config := ConfigFile.new()
	config.set_value(script.SETTINGS_SECTION, script.KEY_MASTER_VOLUME, volume)
	config.set_value(script.SETTINGS_SECTION, script.KEY_FULLSCREEN, fullscreen)
	config.save(path)
	return path


## マスターバスの音量が、0〜100の値に対応する値（線形の振幅をdBにしたもの）か。
func _bus_volume_is(percent: int) -> bool:
	return is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(percent / 100.0))


## [存在するか, 内容, 更新時刻]
func _file_state(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return [false, "", 0]
	return [true, FileAccess.get_file_as_string(path), FileAccess.get_modified_time(path)]


func _free_main(t, main: Node) -> void:
	t.root.remove_child(main)
	main.free()


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false)


func _label_texts(root: Node) -> Array:
	return root.find_children("*", "Label", true, false).map(func(l): return l.text)


func _press(root: Node, text: String) -> void:
	for button in _buttons(root):
		if button.text == text:
			button.pressed.emit()
			return


## 5つのスロットに見立てたファイルを、内容を変えて作る。
func _make_slots(save_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	for i in range(1, SLOT_COUNT + 1):
		var file := FileAccess.open("%s/slot_%02d.json" % [save_dir, i], FileAccess.WRITE)
		file.store_string('{"slot": %d}' % i)
		file.close()


## ファイル名 -> [内容, 更新時刻]
func _snapshot(dir_path: String) -> Dictionary:
	var result := {}
	for file_name in DirAccess.get_files_at(dir_path):
		var path := dir_path + "/" + file_name
		result[file_name] = [FileAccess.get_file_as_string(path), FileAccess.get_modified_time(path)]
	return result


func _remove_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		_remove_dir(dir_path + "/" + sub)
	DirAccess.remove_absolute(dir_path)
