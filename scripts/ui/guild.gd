extends Control
## ギルドの画面の presenter（guild.md）。今は登録者の一覧と、冒険者の登録（§3.1）を扱う。
## 編成・名前と顔の変更・削除・訓練場は別のIssueで作り、それまでは「準備中」を出す（PRS-208）。
## 可否はサービスの `can_*` の結果だけで決め、規則を持たない（ARC-302, FLW-204）。状態のコピーを持たず、セッションを参照する（ARC-204, ARC-205）。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。

const FacilityScript := preload("res://scripts/services/facility_service.gd")
const ConfirmDialog := preload("res://scripts/ui/components/confirm_dialog.gd")
const CharacterStatus := preload("res://scripts/ui/components/character_status.gd")
const STATUS_SCENE := preload("res://scenes/ui/components/character_status.tscn")
const BUTTON_SCENE := preload("res://scenes/ui/components/availability_button.tscn")

## 表示する文字。短いラベルで、文章ではない（PRS-702）。
const TEXT_ROSTER := "登録者"
const TEXT_WAITING := "待機"
const TEXT_JOB_HEADING := "職業を選ぶ"
const TEXT_NAME_PROMPT := "名前（%d〜%d文字）"
const TEXT_INITIAL_SKILL := "初期スキル"
const TEXT_PORTRAIT := "顔%d"
## 確認ダイアログの「確定で変更される項目と費用」（TWN-102）。登録は無料（PTY-000）。
const TEXT_DETAIL_NAME := "名前：%s"
const TEXT_DETAIL_JOB := "職業：%s"
const TEXT_DETAIL_PORTRAIT := "顔：%s"
const TEXT_DETAIL_JOIN := "登録後：パーティの%d番目に加わる"
const TEXT_DETAIL_WAIT := "登録後：待機者になる"
const TEXT_DETAIL_COST := "費用：%dG"
const REGISTER_COST := 0
const PORTRAIT_BUTTON_SIZE := Vector2(104, 104)

## 登録以外の操作（guild.md §3.2）。別のIssueで作るまで「準備中」を出す。
const PENDING_ACTIONS: Array[String] = ["編成", "名前と顔の変更", "削除", "訓練場"]
const REGISTER_LABEL := "登録する"

enum View { MAIN, NAME, JOB, PORTRAIT, PENDING }

var _flow: Node = null
var _service = null
var _session: RefCounted = null
## 表示していない画面は、ツリーから外して持つ。`_exit_tree` で解放する。
var _views: Dictionary = {}
var _view: View = View.MAIN
var _jobs: Array[JobDef] = []
var _register_button: Button = null
## 登録の途中の入力。確定するまで、サービスにもセッションにも書かない（PTY-007）。
var _draft_name := ""
var _draft_job: StringName = &""
var _draft_portrait := ""
var _confirming := false

@onready var _gold_header: PanelContainer = %GoldHeader
@onready var _views_root: Control = %Views
@onready var _main: VBoxContainer = %MainView
@onready var _name_view: Control = %NameView
@onready var _name_prompt: Label = %Prompt
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_next: Button = %NameNext
@onready var _name_back: Button = %NameBack
@onready var _job_view: VBoxContainer = %JobView
@onready var _portrait_view: Control = %PortraitView
@onready var _portrait_grid: GridContainer = %PortraitGrid
@onready var _portrait_back: Button = %PortraitBack
@onready var _pending_view: Control = %PendingView
@onready var _pending_back: Button = %PendingBack
@onready var _notice: Label = %Notice


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_service = FacilityScript.new(_flow.database)
	_session = _flow.session
	_jobs = _flow.database.jobs()
	_gold_header.bind(_session)
	_session.changed.connect(_on_session_changed)

	_views = {
		View.MAIN: _main, View.NAME: _name_view, View.JOB: _job_view,
		View.PORTRAIT: _portrait_view, View.PENDING: _pending_view,
	}
	_build_main()
	_build_name()
	_build_jobs()
	_build_portraits()
	_pending_back.pressed.connect(_back)
	# 最初に出す画面以外は、ツリーから外して持つ。「戻る」などの項目が、同時に複数ある状態を作らない
	for view in _views:
		if view != View.MAIN:
			_views_root.remove_child(_views[view])
	_refresh_roster()


func _exit_tree() -> void:
	if _session != null and _session.changed.is_connected(_on_session_changed):
		_session.changed.disconnect(_on_session_changed)
	for view in _views.values():
		if view.get_parent() == null:
			view.queue_free()


## 登録の入口（可能な場合）か、戻るへフォーカスを置く。入力の遮断中は遮断側がフォーカスを持つため、置かない（FLW-200）。遅延呼び出しの前に画面が外された場合も置かない。
func grab_initial_focus() -> void:
	if is_inside_tree() and not _flow.is_input_blocked():
		_focus_view(_view)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 戻る操作は画面を差し替えて、このノードをツリーから外すことがある。外れた後は get_viewport() が null になるため、先に処理済みにする
		get_viewport().set_input_as_handled()
		_back()


# --- 構築 ---

func _build_main() -> void:
	_main.back_pressed.connect(_back)
	_main.item_focused.connect(_on_roster_focused)
	var actions: HBoxContainer = _main.actions()
	_register_button = BUTTON_SCENE.instantiate()
	_register_button.label = REGISTER_LABEL
	_register_button.custom_minimum_size = Vector2(0, 40)
	_register_button.pressed.connect(_on_register_pressed)
	actions.add_child(_register_button)
	for label in PENDING_ACTIONS:
		var button: Button = BUTTON_SCENE.instantiate()
		button.label = label
		button.custom_minimum_size = Vector2(0, 40)
		button.pressed.connect(_show_view.bind(View.PENDING))
		actions.add_child(button)


func _build_name() -> void:
	_name_prompt.text = TEXT_NAME_PROMPT % [FacilityScript.NAME_MIN, FacilityScript.NAME_MAX]
	_name_next.pressed.connect(_on_name_next)
	_name_edit.text_submitted.connect(func(_text: String): _on_name_next())
	_name_edit.gui_input.connect(_on_name_gui_input)
	_name_back.pressed.connect(_back)


func _build_jobs() -> void:
	_job_view.set_heading(TEXT_JOB_HEADING)
	var entries: Array = []
	for job in _jobs:
		entries.append({"label": job.name})
	_job_view.set_items(entries)
	_job_view.item_focused.connect(_on_job_focused)
	_job_view.item_activated.connect(_on_job_activated)
	_job_view.back_pressed.connect(_back)


func _build_portraits() -> void:
	for n in range(1, FacilityScript.PORTRAIT_COUNT + 1):
		var portrait_id := "portrait_%02d" % n
		var button := Button.new()
		button.custom_minimum_size = PORTRAIT_BUTTON_SIZE
		var texture: Texture2D = _flow.database.portrait_texture(portrait_id)
		if texture != null:
			button.icon = texture
			button.expand_icon = true
		else:
			# 画像が無い場合は、番号で区別する（DAT-228, PRS-601）
			button.text = TEXT_PORTRAIT % n
		button.pressed.connect(_on_portrait_pressed.bind(portrait_id))
		_portrait_grid.add_child(button)
	_portrait_back.pressed.connect(_back)


# --- 登録者の一覧 ---

func _on_session_changed(_kind: StringName) -> void:
	_refresh_roster()


## 登録者の一覧と、登録の可否を更新する。
func _refresh_roster() -> void:
	var characters: Array = _session.characters
	_main.set_heading("%s %d/%d" % [TEXT_ROSTER, characters.size(), FacilityScript.ROSTER_LIMIT])
	var entries: Array = []
	for character in characters:
		entries.append({
			"label": CharacterStatus.list_text(_flow.database, character, _slot_text(character)),
			"icon": _flow.database.portrait_texture(character.portrait_id),
		})
	_main.set_items(entries)
	_main.clear_detail()
	# 登録の入口の可否は、サービスの結果で決める（PTY-012）
	_register_button.available = _service.can_start_register(_session).ok


## パーティでの順番か、待機（PTY-013, PTY-116）。
func _slot_text(character) -> String:
	var position: int = _session.party_ids.find(character.id)
	return TEXT_WAITING if position < 0 else "%d番" % (position + 1)


func _on_roster_focused(index: int) -> void:
	_main.clear_detail()
	var character = _session.characters[index]
	var status: HBoxContainer = STATUS_SCENE.instantiate()
	_main.detail().add_child(status)
	status.show_character(_flow.database, character, _slot_text(character))


# --- 登録（guild.md §3.1） ---

func _on_register_pressed() -> void:
	var result: Dictionary = _service.can_start_register(_session)
	if not result.ok:
		_show_error(result.error_code)
		return
	_draft_name = ""
	_draft_job = &""
	_draft_portrait = ""
	_name_edit.text = ""
	_show_view(View.NAME)


## 手順1：名前。条件を満たさない場合は `error_invalid_name` を表示し、次へ進めない（PTY-003）。
func _on_name_next() -> void:
	var result: Dictionary = _service.can_name(_name_edit.text)
	if not result.ok:
		_show_error(result.error_code)
		return
	_draft_name = result.changes.name
	_show_view(View.JOB)


## 入力欄は、フォーカス中の Esc を自分で消費して、画面の戻る操作へ届かない。ここで受け止めて、1つ前へ戻す（PRS-104）。
func _on_name_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_name_edit.accept_event()
		_back()


## 手順2：職業。選択中の職業の初期能力と初期スキルを詳細に表示する（PTY-210）。
func _on_job_focused(index: int) -> void:
	var job: JobDef = _jobs[index]
	var stats := job.base_stats
	var skill = _flow.database.skill(job.initial_skill_id)
	_job_view.clear_detail()
	var lines: Array[String] = [
		job.name,
		"HP %d　SP %d" % [stats.hp, stats.sp],
		"STR %d　VIT %d　TEC %d" % [stats.str, stats.vit, stats.tec],
		"AGI %d　LUC %d" % [stats.agi, stats.luc],
		"%s：%s" % [TEXT_INITIAL_SKILL, skill.name if skill != null else String(job.initial_skill_id)],
	]
	for line in lines:
		var label := Label.new()
		label.text = line
		_job_view.detail().add_child(label)


func _on_job_activated(index: int) -> void:
	_draft_job = _jobs[index].id
	_show_view(View.PORTRAIT)


## 手順3：顔。選ぶと、手順4の確認へ進む。
func _on_portrait_pressed(portrait_id: String) -> void:
	_draft_portrait = portrait_id
	_ask_confirm()


## 手順4：確認ダイアログ。確認を出す前にも、サービスの可否を確かめる（PTY-012）。
func _ask_confirm() -> void:
	if _confirming:
		return
	var result: Dictionary = _service.can_register(_session, _draft_name, _draft_job, _draft_portrait)
	if not result.ok:
		_show_error(result.error_code)
		return
	_confirming = true
	var message: String = _flow.database.text(&"guild_register_confirm", {"name": result.changes.name})
	var dialog: Control = ConfirmDialog.open(_modal_host(), _flow, message, _confirm_details(result.changes.name))
	dialog.answered.connect(_on_confirm_answered)


## 確定で変更される項目と費用（TWN-102）。
func _confirm_details(registered_name: String) -> Array[String]:
	var job: JobDef = _flow.database.job(_draft_job)
	var party_size: int = _session.party_ids.size()
	var fate := TEXT_DETAIL_JOIN % (party_size + 1) if party_size < FacilityScript.PARTY_LIMIT else TEXT_DETAIL_WAIT
	return [
		TEXT_DETAIL_NAME % registered_name,
		TEXT_DETAIL_JOB % job.name,
		TEXT_DETAIL_PORTRAIT % _draft_portrait.trim_prefix("portrait_"),
		fate,
		TEXT_DETAIL_COST % REGISTER_COST,
	]


## 「はい」で登録する。「いいえ」とEscでは何も消費しない（PTY-007）。
func _on_confirm_answered(confirmed: bool) -> void:
	_confirming = false
	if not confirmed:
		return
	var result: Dictionary = _service.register(_session, _draft_name, _draft_job, _draft_portrait)
	_show_view(View.MAIN)
	if not result.ok:
		_show_error(result.error_code)
		return
	# 登録した冒険者を選ぶ。決定を重ねて押しても、登録は一度だけで、次の操作は始まらない
	_focus_roster_member(result.changes.character_id)


func _focus_roster_member(character_id: int) -> void:
	for i in _session.characters.size():
		if _session.characters[i].id == character_id:
			_main.focus_item.call_deferred(i)
			return


## サービスの失敗の理由を表示する。文は `error_` + 小文字のコードで引く（ARC-402）。
func _show_error(error_code: StringName) -> void:
	_notice.show_error(_flow.database, error_code, {"min": FacilityScript.NAME_MIN, "max": FacilityScript.NAME_MAX})


# --- 画面の切り替え ---

func _modal_host() -> Node:
	var host := get_parent()
	if host != null and host.get("modal_host") != null:
		return host.modal_host
	return self


## 1つ前へ戻る。最初の画面では、街へ戻る（PRS-104）。登録の途中で戻っても、何も消費しない（PTY-007）。
func _back() -> void:
	if _flow.is_input_blocked():
		return
	match _view:
		View.MAIN:
			_flow.go_back()
		View.NAME, View.PENDING:
			_show_view(View.MAIN)
		View.JOB:
			_show_view(View.NAME)
		View.PORTRAIT:
			_show_view(View.JOB)


func _show_view(view: View) -> void:
	var current: Control = _views[_view]
	if current.get_parent() == _views_root:
		_views_root.remove_child(current)
	_view = view
	_views_root.add_child(_views[view])
	_notice.clear()
	# 追加した直後より、遅延させたほうが確実にフォーカスが付く
	_focus_view.call_deferred(view)


func _focus_view(view: View) -> void:
	if not is_inside_tree() or _flow.is_input_blocked() or view != _view:
		return
	match view:
		View.MAIN:
			if _register_button.available:
				_register_button.grab_focus()
			else:
				_main.focus_back()
		View.NAME:
			_name_edit.grab_focus()
		View.JOB:
			_job_view.focus_item(0)
		View.PORTRAIT:
			_portrait_grid.get_child(0).grab_focus()
		View.PENDING:
			_pending_back.grab_focus()
