extends Control
## タイトル画面の presenter。押下は GameFlow へ要求を送るだけで、遷移の判断をしない（ARC-204, 205）。

var _flow: Node = null

@onready var _new_game: Button = %NewGame
@onready var _load_game: Button = %LoadGame
@onready var _settings: Button = %Settings
@onready var _quit: Button = %Quit


func setup(flow: Node) -> void:
	_flow = flow


func _ready() -> void:
	_new_game.pressed.connect(func(): _flow.request_new_game())
	_load_game.pressed.connect(func(): _flow.open_load())
	_settings.pressed.connect(func(): _flow.open_settings())
	_quit.pressed.connect(func(): _flow.quit_app())
	_new_game.grab_focus()
