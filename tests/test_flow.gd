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
const TEXT_SCREEN_SCENE := "res://scenes/ui/text_screen.tscn"
const TOWN_SCENE := "res://scenes/ui/town.tscn"
const TOWN_BACKGROUND := "res://assets/backgrounds/town.png"
const FACILITY_SCRIPT := "res://scripts/services/facility_service.gd"
## 街の項目（town.md §2）。表示名の順と、GameFlow へ送る操作（FLW-004）
const TOWN_ITEMS := ["ギルド", "教会", "商店", "宿屋", "酒場", "ダンジョンへ", "メニュー", "セーブ", "タイトルへ"]
const TOWN_ACTIONS: Array[StringName] = [&"guild", &"temple", &"shop", &"inn", &"tavern", &"departure", &"menu", &"save", &"title"]
## 登録者が0人の間も使える項目（TWN-112）
const TOWN_ITEMS_ALWAYS := ["ギルド", "タイトルへ"]
const TOWN_ACTIONS_ALWAYS: Array[StringName] = [&"guild", &"title"]
## 選択不可の項目名に添える文字（PRS-305）と、所持金ヘッダーの表示（components.md）
const UNAVAILABLE_SUFFIX := "（不可）"
const GOLD_FORMAT := "所持金 %dG"
## FL08 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const FL08_TMP_ROOT := "user://test_flow_fl08"
## FL06 が GameFlow に渡す、設定とスロットの一時的な置き場所（TST-107）
const FL06_TMP_ROOT := "user://test_flow_fl06"
## 開発者の実際の設定ファイル。FL06 が変更しないことを確かめる（TST-107）
const REAL_SETTINGS_PATH := "user://settings.cfg"
# PRS-300 の色のトークン（bg_base、bg_scrim）
const BG_BASE := Color("#0E1420")
const BG_SCRIM := Color(BG_BASE, 0.35)
## 起動時の検証（FLW-015, FLW-016, DAT-900）。FL07 が不正を入れる複写の置き場所（TST-107, TST-108）
const DATA_DIR := "res://data"
const DATABASE_SCRIPT := "res://scripts/core/game_database.gd"
const BOOT_ROOT := "user://test_flow_boot"
const BOOT_DATA_DIR := BOOT_ROOT + "/data"
## 起動エラーの画面
const BOOT_ERROR_SCENE := "res://scenes/ui/boot_error.tscn"
const BOOT_ERROR_TEXT_ID := "boot_error"
## 参照切れを入れる箇所（skills.csv の power_slash の job_id）
const BROKEN_FROM := "power_slash,強撃,warrior,"
const BROKEN_TO := "power_slash,強撃,no_such_job,"


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
	await _fl08(t)
	await _fl09(t)


# FL06: TITLEから設定を開いて変更し、閉じる（FLW-111, FLW-112, FLW-113, FLW-301, PRS-000, PRS-400, PRS-401, PRS-402, PRS-405, PRS-108）。
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


## main.tscn の配線のまま、設定画面の表示・操作・戻るを確かめる（FLW-111, FLW-112, FLW-113, FLW-014, PRS-400, PRS-401, PRS-104, PRS-108, ARC-204, ARC-205）。
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
	_fl07_boot_game_flow(t)
	await _fl07_boot_screen(t)

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
	t.check("FL07", true, flow.new_game())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", before, _snapshot(save_dir))
	# NEW_GAME から「はじめから」や「つづきから」は受け付けない（FLW-102）
	t.check("FL07", false, flow.new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", s.NEW_GAME, flow.state)
	# NEW_GAME は仮画面ではなく、戻る操作はない。決定で TOWN へ進む（FLW-002）。街の「タイトルへ」でセッションを破棄して TITLE へ戻る（FLW-108）
	t.check("FL07", false, flow.go_back())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", true, flow.go_town())
	t.check("FL07", s.TOWN, flow.state)
	t.check("FL07", true, flow.return_title())
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
	t.check("FL07", true, flow.new_game())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.NEW_GAME, flow.state)
	flow.go_town()
	flow.return_title()

	# 「終了」→ 差し替えた終了要求が1回呼ばれる。ランナーは止まらない（FLW-001, TST-106）
	t.check("FL07", 0, quits[0])
	flow.quit_app()
	t.check("FL07", 1, quits[0])

	# 遷移の履歴：TITLEを起点に、押した順にたどる
	t.check("FL07", [
		[s.BOOT, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TOWN], [s.TOWN, s.TITLE],
		[s.TITLE, s.LOAD], [s.LOAD, s.TITLE],
		[s.TITLE, s.SETTINGS], [s.SETTINGS, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TOWN], [s.TOWN, s.TITLE],
	], history)

	# 入力遮断は理由の集合で保持する。1つでも残っている間は遮断が続き、遷移の要求を受け付けない（FLW-204）
	t.check("FL07", false, flow.is_input_blocked())
	flow.block_input(&"modal")
	flow.block_input(&"animation")
	t.check("FL07", true, flow.is_input_blocked())
	t.check("FL07", false, flow.new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", false, flow.has_session())
	flow.unblock_input(&"modal")
	t.check("FL07", true, flow.is_input_blocked())
	flow.unblock_input(&"animation")
	t.check("FL07", false, flow.is_input_blocked())
	t.check("FL07", true, flow.new_game())
	flow.go_town()
	flow.return_title()

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
	# 「はじめから」は仮画面ではなく導入の画面へ進む。下の FL08 の確認へ続く
	var expected_states := [s.NEW_GAME, s.LOAD, s.SETTINGS]
	for i in expected_states.size():
		if i == 0:
			continue
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
		if i == 1:
			# Esc でも遷移元へ戻る。画面が差し替わった後に、外れたノードの処理で止まらない（PRS-208）
			t.root.push_input(_action_event(&"ui_cancel"))
		else:
			_press(placeholder, "戻る")
		t.check("FL07", s.TITLE, flow.state)
		t.check("FL07", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))

	# 「はじめから」で導入の文章画面へ進む。中身は FL08 で確かめる（PRS-208 の仮画面ではない）。ここでは遷移と、TITLEへ戻るまでを確かめる
	_press(host.current_screen, TITLE_ITEMS[0])
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", false, _label_texts(host.current_screen).has("準備中"))
	flow.go_town()
	flow.return_title()
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))
	t.check("FL07", false, flow.has_session())

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


## 起動時に検証し、成功ならTITLE、失敗ならBOOT_ERROR へ進む。GameFlow だけで確かめる（FLW-015, FLW-016, DAT-900, DAT-908, TST-108）。
## 受入IDの索引に起動エラー専用のIDがないため、起動の入口である FL07 で確かめる。
func _fl07_boot_game_flow(t) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	t.check("FL07", true, script != null)
	if script == null:
		return
	var s = script.State
	_remove_dir(BOOT_ROOT)

	# 正常なデータ：BOOT から TITLE へ進み、BOOT_ERROR を経由しない。ログは出ない
	var good := _boot_flow(script, DATA_DIR)
	t.root.add_child(good["flow"])
	t.check("FL07", s.TITLE, good["flow"].state)
	t.check("FL07", [[s.BOOT, s.TITLE]], good["history"])
	t.check("FL07", true, good["flow"].database.is_loaded())
	t.check("FL07", [], good["log"])
	_free_boot_flow(t, good)

	# 参照切れのID：TITLE を経由せず BOOT_ERROR へ進む。問題のファイル名とIDをログへ出す（DAT-908）
	_copy_data()
	t.check("FL07", true, _replace_in_data("skills.csv", BROKEN_FROM, BROKEN_TO))
	var bad := _boot_flow(script, BOOT_DATA_DIR)
	t.root.add_child(bad["flow"])
	t.check("FL07", s.BOOT_ERROR, bad["flow"].state)
	t.check("FL07", [[s.BOOT, s.BOOT_ERROR]], bad["history"])
	t.check("FL07", false, bad["flow"].database.is_loaded())
	t.check("FL07", true, bad["log"].any(func(line: String): return line.contains("skills.csv id=power_slash:")))
	# BOOT_ERROR から、ほかの状態へは進めない。終了だけができる（FLW-016）
	t.check("FL07", false, bad["flow"].new_game())
	t.check("FL07", false, bad["flow"].open_load())
	t.check("FL07", false, bad["flow"].open_settings())
	t.check("FL07", false, bad["flow"].go_back())
	t.check("FL07", s.BOOT_ERROR, bad["flow"].state)
	t.check("FL07", 0, bad["quits"][0])
	bad["flow"].quit_app()
	t.check("FL07", 1, bad["quits"][0])
	_free_boot_flow(t, bad)

	# 元に戻すと、再び TITLE へ進む（U07 の後半）
	_remove_dir(BOOT_ROOT)
	var restored := _boot_flow(script, DATA_DIR)
	t.root.add_child(restored["flow"])
	t.check("FL07", s.TITLE, restored["flow"].state)
	_free_boot_flow(t, restored)
	_remove_dir(BOOT_ROOT)


## main.tscn の配線のまま、起動不可のエラー画面の表示と操作を確かめる（FLW-016, DAT-900, PRS-704, ARC-204）。
func _fl07_boot_screen(t) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("FL07", true, packed != null)
	var error_scene := load(BOOT_ERROR_SCENE) as PackedScene
	t.check("FL07", true, error_scene != null)
	if packed == null or error_scene == null:
		return
	var message := _read_text(DATA_DIR + "/texts.csv", BOOT_ERROR_TEXT_ID)
	t.check("FL07", false, message == "")
	var sample := error_scene.instantiate()
	var fallback: String = sample.get_script().FALLBACK_MESSAGE
	sample.free()
	t.check("FL07", false, fallback == "")

	# 参照切れ：texts.csv は読めるので、その文を表示する。TITLEの項目や「準備中」は出さない
	_remove_dir(BOOT_ROOT)
	_copy_data()
	t.check("FL07", true, _replace_in_data("skills.csv", BROKEN_FROM, BROKEN_TO))
	await _fl07_boot_screen_case(t, packed, message)

	# texts.csv 自体を読み込めない：コードに固定した文を表示する（PRS-704）
	_remove_dir(BOOT_ROOT)
	_copy_data()
	DirAccess.remove_absolute(BOOT_DATA_DIR + "/texts.csv")
	await _fl07_boot_screen_case(t, packed, fallback)
	_remove_dir(BOOT_ROOT)


## 不正なデータで main.tscn を起動し、エラー画面が `expected_message` を表示して、終了できることを確かめる。
func _fl07_boot_screen_case(t, packed: PackedScene, expected_message: String) -> void:
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("FL07", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	var s = flow.State
	var quits := [0]
	flow.save_dir = BOOT_ROOT + "/saves"
	flow.settings_path = BOOT_ROOT + "/settings.cfg"
	flow.quit_handler = func(): quits[0] += 1
	flow.fullscreen_handler = func(_on: bool): pass
	flow.data_dir = BOOT_DATA_DIR
	flow.log_sink = func(_line: String): pass
	flow.database = load(DATABASE_SCRIPT).new()
	var logs := EngineLogCounter.new()
	OS.add_logger(logs)
	t.root.add_child(main)
	await t.process_frame

	t.check("FL07", s.BOOT_ERROR, flow.state)
	var screen: Control = host.current_screen
	t.check("FL07", true, screen != null and screen.scene_file_path == BOOT_ERROR_SCENE)
	if screen != null:
		# メッセージと終了ボタンだけを出す。問題のIDとファイル名は画面に出さない（DAT-908）
		t.check("FL07", [expected_message], _label_texts(screen))
		var buttons := _buttons(screen)
		t.check("FL07", ["終了"], buttons.map(func(b): return b.text))
		if not buttons.is_empty():
			var quit_button: Button = buttons[0]
			t.check("FL07", true, quit_button.has_focus())
			# 終了ボタンで終了する
			t.check("FL07", 0, quits[0])
			quit_button.pressed.emit()
			t.check("FL07", 1, quits[0])
			# Enter でも終了する。フォーカスのあるボタンが受けて、二重に呼ばない
			t.root.push_input(_key_event(KEY_ENTER))
			t.check("FL07", 2, quits[0])
			# フォーカスが外れていても、Enter で終了する
			quit_button.release_focus()
			t.check("FL07", false, quit_button.has_focus())
			t.root.push_input(_key_event(KEY_ENTER))
			t.check("FL07", 3, quits[0])
			# 入力の遮断中は、Enter でも終了しない（FLW-200）
			flow.block_input(&"modal")
			t.root.push_input(_key_event(KEY_ENTER))
			t.check("FL07", 3, quits[0])
			flow.unblock_input(&"modal")
	# 起動エラーの画面を出しても、エンジンのエラーは出ない
	OS.remove_logger(logs)
	t.check("FL07", 0, logs.count())
	t.root.remove_child(main)
	flow.database.free()
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


# FL08: 登録者を作成した後、TOWNから「タイトルへ」を選び、再度「はじめから」を選ぶ（FLW-002, FLW-004, FLW-108, FLW-110, FLW-204, TWN-110, TWN-111, TWN-112, PRS-205, PRS-208, PRS-503, ARC-202, ARC-203）。
# 登録は `FacilityService` で行う（ARC-302）。最後の登録者の削除は、削除を実装する Issue まで、テストが直接セッションから取り除く。
# 確かめるのは、NEW_GAMEでのセッションの作成、導入文から街への遷移、登録前の制限と登録による解除、タイトルへ戻るときの破棄、再度の「はじめから」で別のセッションになること。
func _fl08(t) -> void:
	_fl08_game_flow(t)
	await _fl08_screens(t)


## GameFlow だけで、セッションの作成と破棄、街の項目の可否と遷移を確かめる（FLW-002, FLW-108, FLW-110, FLW-204, TWN-110, TWN-111, TWN-112, ARC-203）。
func _fl08_game_flow(t) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	t.check("FL08", true, script != null)
	if script == null:
		return
	var s = script.State
	var db = load(DATABASE_SCRIPT).new()
	t.check("FL08", true, db.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))
	var flow: Node = script.new()
	flow.save_dir = FL08_TMP_ROOT + "/saves"
	flow.settings_path = FL08_TMP_ROOT + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool) -> void: pass
	flow.database = db
	var history: Array = []
	flow.state_changed.connect(func(new_state, old_state): history.append([old_state, new_state]))
	t.root.add_child(flow)

	# 作成に失敗した場合は、何も変えず TITLE に留まる（ARC-403, FLW-002）。データベースがない場合と、初期の所持品を収められない場合
	flow.database = null
	t.check("FL08", false, flow.new_game())
	t.check("FL08", s.TITLE, flow.state)
	t.check("FL08", false, flow.has_session())
	var overflowing = load(DATABASE_SCRIPT).new()
	t.check("FL08", true, overflowing.load_and_validate(DATA_DIR, func(_line: String) -> void: pass))
	var heap: Array[ItemStackDef] = []
	for i in 31:
		var stack := ItemStackDef.new()
		stack.item_id = overflowing.items()[0].id
		stack.quantity = overflowing.items()[0].max_stack
		heap.append(stack)
	overflowing.new_game_items = heap
	flow.database = overflowing
	t.check("FL08", false, flow.new_game())
	t.check("FL08", s.TITLE, flow.state)
	t.check("FL08", false, flow.has_session())
	flow.database = db
	overflowing.free()

	# TITLE：セッションがなく、街の操作はできない
	t.check("FL08", s.TITLE, flow.state)
	t.check("FL08", false, flow.has_session())
	t.check("FL08", false, flow.go_town())
	t.check("FL08", false, flow.return_title())
	t.check("FL08", false, flow.select_town_action(&"guild").ok)
	t.check("FL08", s.TITLE, flow.state)

	# 「はじめから」：NEW_GAMEに入る時点で、導入を表示する前にセッションを作る（FLW-002）
	t.check("FL08", true, flow.new_game())
	t.check("FL08", s.NEW_GAME, flow.state)
	t.check("FL08", true, flow.has_session())
	var first = flow.session
	var first_id: String = first.session_id
	t.check("FL08", true, first_id != "")
	# 導入の間は、街の操作とタイトルへ戻る操作を受け付けない（FLW-002）
	t.check("FL08", false, flow.return_title())
	t.check("FL08", false, flow.select_town_action(&"guild").ok)
	t.check("FL08", s.NEW_GAME, flow.state)
	t.check("FL08", true, flow.has_session())

	# 入力の遮断中は、導入から街へ進めない（FLW-204）
	flow.block_input(&"modal")
	t.check("FL08", false, flow.go_town())
	t.check("FL08", s.NEW_GAME, flow.state)
	flow.unblock_input(&"modal")

	# 導入の決定で TOWN へ進む。セッションは同じものを引き継ぐ（FLW-002）
	t.check("FL08", true, flow.go_town())
	t.check("FL08", s.TOWN, flow.state)
	t.check("FL08", true, flow.session == first)
	t.check("FL08", false, flow.go_town())

	# 登録者が0人の間：ギルドとタイトルへ以外は選べず、`LOCKED` を返す（TWN-110, TWN-112, FLW-110）
	t.check("FL08", true, flow.is_town_restricted())
	for action in TOWN_ACTIONS:
		var result: Dictionary = flow.check_town_action(action)
		var open: bool = TOWN_ACTIONS_ALWAYS.has(action)
		t.check("FL08", open, result.ok)
		t.check("FL08", "" if open else "LOCKED", String(result.error_code))
	t.check("FL08", false, flow.check_town_action(&"no_such_action").ok)
	t.check("FL08", "INVALID_TARGET", String(flow.check_town_action(&"no_such_action").error_code))
	for action in TOWN_ACTIONS:
		if TOWN_ACTIONS_ALWAYS.has(action):
			continue
		var locked: Dictionary = flow.select_town_action(action)
		t.check("FL08", false, locked.ok)
		t.check("FL08", "LOCKED", String(locked.error_code))
		t.check("FL08", s.TOWN, flow.state)
	t.check("FL08", true, flow.session == first)
	t.check("FL08", false, first.dirty)

	# ギルドは選べる。選択できるが未実装の遷移先は FACILITY へ遷移し、戻るで TOWN へ戻る（PRS-208）
	var opened: Dictionary = flow.select_town_action(&"guild")
	t.check("FL08", true, opened.ok)
	t.check("FL08", s.FACILITY, flow.state)
	t.check("FL08", "guild", String(flow.facility))
	t.check("FL08", true, flow.go_back())
	t.check("FL08", s.TOWN, flow.state)
	t.check("FL08", true, flow.session == first)

	# 登録者が1人以上になると、すべて選べる。各項目の遷移先と、戻るで TOWN へ戻ること（TWN-111, FLW-110）
	var service = load(FACILITY_SCRIPT).new(db)
	t.check("FL08", false, service.register(first, "", &"warrior", "portrait_01").ok)
	t.check("FL08", true, flow.is_town_restricted())
	t.check("FL08", true, service.register(first, "アリス", &"warrior", "portrait_01").ok)
	t.check("FL08", 1, first.characters.size())
	t.check("FL08", false, flow.is_town_restricted())
	var destinations := {
		&"guild": s.FACILITY, &"temple": s.FACILITY, &"shop": s.FACILITY, &"inn": s.FACILITY, &"tavern": s.FACILITY,
		&"departure": s.DEPARTURE, &"menu": s.MENU, &"save": s.SAVE,
	}
	for action in destinations:
		t.check("FL08", true, flow.check_town_action(action).ok)
		t.check("FL08", true, flow.select_town_action(action).ok)
		t.check("FL08", destinations[action], flow.state)
		if destinations[action] == s.FACILITY:
			t.check("FL08", String(action), String(flow.facility))
		# 入力の遮断中は、戻れない（FLW-204）
		flow.block_input(&"modal")
		t.check("FL08", false, flow.go_back())
		t.check("FL08", destinations[action], flow.state)
		flow.unblock_input(&"modal")
		t.check("FL08", true, flow.go_back())
		t.check("FL08", s.TOWN, flow.state)
	# 入力の遮断中は、街の項目を選べない（FLW-204）
	flow.block_input(&"modal")
	t.check("FL08", false, flow.select_town_action(&"guild").ok)
	t.check("FL08", false, flow.return_title())
	t.check("FL08", s.TOWN, flow.state)
	flow.unblock_input(&"modal")
	# 最後の登録者を削除すると、再び制限される（TWN-111）
	first.characters.clear()
	first.party_ids.clear()
	t.check("FL08", true, flow.is_town_restricted())
	t.check("FL08", false, flow.check_town_action(&"menu").ok)

	# 登録し直して、セッションの状態を変えてから「タイトルへ」。セッションを破棄する（FLW-108, ARC-203）。IDは再利用しない（GLS-403）
	t.check("FL08", true, service.register(first, "ボブ", &"mage", "portrait_02").ok)
	t.check("FL08", 2, first.characters[0].id)
	first.gold += 100
	first.day = 4
	first.dirty = true
	t.check("FL08", true, flow.select_town_action(&"title").ok)
	t.check("FL08", s.TITLE, flow.state)
	t.check("FL08", false, flow.has_session())
	t.check("FL08", null, flow.session)
	# TITLE へ戻った後は、街の操作を受け付けない
	t.check("FL08", false, flow.select_town_action(&"guild").ok)
	t.check("FL08", false, flow.go_town())

	# 再度の「はじめから」：別の session_id の新しいセッションが、ニューゲームの初期状態で作られる。旧セッションの内容は残らない（FLW-002, ARC-202）
	t.check("FL08", true, flow.new_game())
	var second = flow.session
	t.check("FL08", true, second != first)
	t.check("FL08", true, second.session_id != first_id)
	t.check("FL08", db.new_game_gold, second.gold)
	t.check("FL08", 1, second.day)
	t.check("FL08", 0, second.characters.size())
	t.check("FL08", 0, second.party_ids.size())
	t.check("FL08", 1, second.next_character_id)
	t.check("FL08", false, second.dirty)
	t.check("FL08", 1, first.characters.size())

	# 履歴：NEW_GAME → TOWN → 各項目 → TOWN ... → TITLE → NEW_GAME
	var expected_history: Array = [[s.BOOT, s.TITLE], [s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TOWN]]
	expected_history.append_array([[s.TOWN, s.FACILITY], [s.FACILITY, s.TOWN]])
	for action in destinations:
		expected_history.append_array([[s.TOWN, destinations[action]], [destinations[action], s.TOWN]])
	expected_history.append_array([[s.TOWN, s.TITLE], [s.TITLE, s.NEW_GAME]])
	t.check("FL08", expected_history, history)

	t.root.remove_child(flow)
	flow.free()
	db.free()


## main.tscn の配線のまま、導入の文章画面と街の画面を確かめる（FLW-002, PRS-205, PRS-208, PRS-503, TWN-110, TWN-112, ARC-205）。
func _fl08_screens(t) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("FL08", true, packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("FL08", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	var s = flow.State
	flow.save_dir = FL08_TMP_ROOT + "/saves"
	flow.settings_path = FL08_TMP_ROOT + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool) -> void: pass
	t.root.add_child(main)
	await t.process_frame
	t.check("FL08", s.TITLE, flow.state)

	var intro := _read_text(DATA_DIR + "/texts.csv", "intro")
	var guide := _read_text(DATA_DIR + "/texts.csv", "town_need_register")
	t.check("FL08", false, intro == "" or guide == "")
	var start_gold: int = flow.database.new_game_gold

	# タイトルで Enter を押す。押した Enter は導入に持ち越されず、キーリピートでも導入は進まない（PRS-503）
	t.check("FL08", true, _buttons(host.current_screen)[0].has_focus())
	t.root.push_input(_key_event_full(KEY_ENTER, true, false))
	t.root.push_input(_key_event_full(KEY_ENTER, false, false))
	t.check("FL08", s.NEW_GAME, flow.state)
	t.root.push_input(_key_event_full(KEY_ENTER, true, true))
	t.root.push_input(_key_event_full(KEY_ENTER, true, true))
	t.root.push_input(_key_event_full(KEY_ENTER, false, false))
	await t.process_frame
	t.check("FL08", s.NEW_GAME, flow.state)

	# 導入：`intro` だけを表示する。セッションは表示の前にある。仮画面ではない（FLW-002, PRS-208）
	var screen: Control = host.current_screen
	t.check("FL08", TEXT_SCREEN_SCENE, screen.scene_file_path)
	t.check("FL08", [intro], _label_texts(screen))
	t.check("FL08", [], _buttons(screen))
	t.check("FL08", true, flow.has_session())
	var first_id: String = flow.session.session_id
	t.check("FL08", true, first_id != "")

	# 決定以外では進まない：右クリック、マウスボタンの解放、ほかのキー、キーの解放（PRS-503）
	t.root.push_input(_mouse_click(t, MOUSE_BUTTON_RIGHT, true))
	t.root.push_input(_mouse_click(t, MOUSE_BUTTON_LEFT, false))
	t.root.push_input(_key_event_full(KEY_A, true, false))
	t.root.push_input(_key_event_full(KEY_ENTER, false, false))
	await t.process_frame
	t.check("FL08", s.NEW_GAME, flow.state)
	# 入力の遮断中は、決定でも進まない（FLW-200）
	flow.block_input(&"modal")
	t.root.push_input(_key_event_full(KEY_ENTER, true, false))
	t.check("FL08", s.NEW_GAME, flow.state)
	flow.unblock_input(&"modal")

	# Enter の決定で、最後の文章から TOWN へ進む（FLW-002, PRS-503）
	t.root.push_input(_key_event_full(KEY_ENTER, true, false))
	t.check("FL08", s.TOWN, flow.state)
	await t.process_frame
	await _fl08_town_screen(t, flow, host, guide, start_gold)

	# 「タイトルへ」：セッションを破棄して TITLE へ戻る。確認は出さない（段階D まで。FLW-108）
	_press(host.current_screen, "タイトルへ")
	t.check("FL08", s.TITLE, flow.state)
	t.check("FL08", false, flow.has_session())
	t.check("FL08", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))

	# 再度の「はじめから」：左クリックの決定でも進む。別の session_id で、ニューゲームの初期状態になる
	_press(host.current_screen, "はじめから")
	t.check("FL08", s.NEW_GAME, flow.state)
	t.check("FL08", true, flow.session.session_id != first_id)
	t.root.push_input(_mouse_click(t, MOUSE_BUTTON_LEFT, true))
	t.check("FL08", s.TOWN, flow.state)
	await t.process_frame
	t.check("FL08", start_gold, flow.session.gold)
	t.check("FL08", 0, flow.session.characters.size())
	t.check("FL08", true, _shown_label_texts(host.current_screen).has(guide))

	_free_main(t, main)
	_remove_dir(FL08_TMP_ROOT)


## 街の画面：登録前の制限の表示、選択不可、遷移、登録後の表示、所持金（town.md, components.md, TWN-110, TWN-112, PRS-205, PRS-305）。
func _fl08_town_screen(t, flow: Node, host: Control, guide: String, start_gold: int) -> void:
	var s = flow.State
	var screen: Control = host.current_screen
	t.check("FL08", TOWN_SCENE, screen.scene_file_path)

	# 背景は共通部品「画面背景」を最初の子に置く（PRS-607）。画像は #11 まで無く、あっても無くても同じ部品が扱う
	var background: Control = screen.get_child(0)
	t.check("FL08", BACKGROUND_SCENE, background.scene_file_path)
	t.check("FL08", TOWN_BACKGROUND, background.texture_path)

	# 表示：9項目を順に並べ、登録者が0人の間は、ギルドとタイトルへ以外に「（不可）」を添えて無効にする（TWN-110, PRS-305）
	var buttons := _buttons(screen)
	var expected_text := []
	var expected_disabled := []
	for item in TOWN_ITEMS:
		var open: bool = TOWN_ITEMS_ALWAYS.has(item)
		expected_text.append(item if open else item + UNAVAILABLE_SUFFIX)
		expected_disabled.append(not open)
	t.check("FL08", expected_text, buttons.map(func(b): return b.text))
	t.check("FL08", expected_disabled, buttons.map(func(b): return b.disabled))
	# 案内文と所持金ヘッダー（PRS-205）
	var labels := _shown_label_texts(screen)
	t.check("FL08", true, labels.has(guide))
	t.check("FL08", true, labels.has(GOLD_FORMAT % start_gold))
	# 最初の項目（ギルド）にフォーカスがある（PRS-007）。選べない項目はフォーカスを受けず、Tab と矢印キーは選べる項目だけを巡る（PRS-304）
	t.check("FL08", true, buttons[0].has_focus())
	t.check("FL08", expected_disabled.map(func(d): return Control.FOCUS_NONE if d else Control.FOCUS_ALL), buttons.map(func(b): return b.focus_mode))
	t.check("FL08", buttons[8], buttons[0].find_next_valid_focus())
	t.check("FL08", buttons[0], buttons[8].find_next_valid_focus())
	t.check("FL08", buttons[8], buttons[0].find_prev_valid_focus())
	# 矢印キーも、二列に分かれたギルドとタイトルへの間を移る
	t.check("FL08", [buttons[8], buttons[8]], [buttons[0].find_valid_focus_neighbor(SIDE_RIGHT), buttons[0].find_valid_focus_neighbor(SIDE_BOTTOM)])
	t.check("FL08", [buttons[0], buttons[0]], [buttons[8].find_valid_focus_neighbor(SIDE_LEFT), buttons[8].find_valid_focus_neighbor(SIDE_TOP)])

	# 選べない項目は、押しても遷移しない。GameFlow が `LOCKED` を返し、画面は判断しない（FLW-204）
	_press(screen, "教会（不可）")
	_press(screen, "メニュー（不可）")
	t.check("FL08", s.TOWN, flow.state)

	# ギルドは仮画面へ。戻るで街へ戻る（PRS-208）
	_press(screen, "ギルド")
	t.check("FL08", s.FACILITY, flow.state)
	t.check("FL08", ["準備中"], _label_texts(host.current_screen))
	_press(host.current_screen, "戻る")
	t.check("FL08", s.TOWN, flow.state)
	await t.process_frame
	screen = host.current_screen
	t.check("FL08", TOWN_SCENE, screen.scene_file_path)

	# セッションの変更の通知で、表示を更新する（ARC-205）。登録者が1人入ると、案内文が消えて、すべて選べる
	var service = load(FACILITY_SCRIPT).new(flow.database)
	t.check("FL08", true, service.register(flow.session, "アリス", &"warrior", "portrait_01").ok)
	buttons = _buttons(screen)
	t.check("FL08", TOWN_ITEMS, buttons.map(func(b): return b.text))
	t.check("FL08", [false, false, false, false, false, false, false, false, false], buttons.map(func(b): return b.disabled))
	t.check("FL08", [Control.FOCUS_ALL], buttons.map(func(b): return b.focus_mode).reduce(func(modes, m): return modes if modes.has(m) else modes + [m], []))
	t.check("FL08", false, _shown_label_texts(screen).has(guide))
	# 所持金が変わると、ヘッダーが直後に更新される
	flow.session.gold = start_gold + 321
	flow.session.notify_changed(&"gold")
	t.check("FL08", true, _label_texts(screen).has(GOLD_FORMAT % (start_gold + 321)))

	# 登録後は、すべての項目を選べる。選択できるが未実装の遷移先は、仮画面へ遷移する（PRS-208）
	var expected_states := {
		"教会": s.FACILITY, "商店": s.FACILITY, "宿屋": s.FACILITY, "酒場": s.FACILITY,
		"ダンジョンへ": s.DEPARTURE, "メニュー": s.MENU, "セーブ": s.SAVE,
	}
	for item in expected_states:
		_press(host.current_screen, item)
		t.check("FL08", expected_states[item], flow.state)
		t.check("FL08", ["準備中"], _label_texts(host.current_screen))
		# Esc でも戻る
		t.root.push_input(_action_event(&"ui_cancel"))
		t.check("FL08", s.TOWN, flow.state)
		t.check("FL08", TOWN_SCENE, host.current_screen.scene_file_path)
		await t.process_frame

	# 登録者を削除すると、再び制限して案内文を出す（TWN-111）
	flow.session.characters.clear()
	flow.session.party_ids.clear()
	flow.session.notify_changed(&"characters")
	t.check("FL08", true, _shown_label_texts(host.current_screen).has(guide))
	t.check("FL08", expected_text, _buttons(host.current_screen).map(func(b): return b.text))


## 起動前の GameFlow。読込元とログの出力先を差し替え、終了要求は回数だけ数える（TST-106, TST-107, TST-108）。
## データベースもテスト用に作り直し、アプリのAutoloadの状態を変えない。
func _boot_flow(script: GDScript, data_dir: String) -> Dictionary:
	var flow: Node = script.new()
	flow.save_dir = BOOT_ROOT + "/saves"
	flow.settings_path = BOOT_ROOT + "/settings.cfg"
	flow.fullscreen_handler = func(_on: bool): pass
	var quits := [0]
	flow.quit_handler = func(): quits[0] += 1
	var log_lines: Array = []
	flow.data_dir = data_dir
	flow.log_sink = func(line: String): log_lines.append(line)
	flow.database = load(DATABASE_SCRIPT).new()
	var history: Array = []
	flow.state_changed.connect(func(new_state, old_state): history.append([old_state, new_state]))
	return {"flow": flow, "history": history, "log": log_lines, "quits": quits}


func _free_boot_flow(t, booted: Dictionary) -> void:
	var flow: Node = booted["flow"]
	t.root.remove_child(flow)
	flow.database.free()
	flow.free()


## `res://data` の全CSVを、`user://` 配下の置き場所へ複写する（開発者の `data/` を変えない）
func _copy_data() -> void:
	DirAccess.make_dir_recursive_absolute(BOOT_DATA_DIR)
	for file in DirAccess.get_files_at(DATA_DIR):
		if file.ends_with(".csv"):
			var out := FileAccess.open("%s/%s" % [BOOT_DATA_DIR, file], FileAccess.WRITE)
			out.store_buffer(FileAccess.get_file_as_bytes("%s/%s" % [DATA_DIR, file]))


## 複写したCSVの文字列を置き換える。見つからなければ false
func _replace_in_data(file: String, from: String, to: String) -> bool:
	var path := "%s/%s" % [BOOT_DATA_DIR, file]
	var text := FileAccess.get_file_as_string(path)
	if not text.contains(from):
		return false
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(text.replace(from, to))
	out.close()
	return true


## texts.csv から、IDの文章を読む。なければ空
func _read_text(path: String, id: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and row[0] == id:
			return row[1]
	return ""


func _key_event_full(keycode: Key, pressed: bool, echo: bool) -> InputEventKey:
	var event := _key_event(keycode)
	event.pressed = pressed
	event.echo = echo
	return event


## ビューポートの中央での、マウスボタンの押下または解放
func _mouse_click(t, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = t.root.get_visible_rect().get_center()
	event.global_position = event.position
	return event


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


## 表示されているラベルの文字（非表示のラベルを除く）
func _shown_label_texts(root: Node) -> Array:
	return root.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return l.text)


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
