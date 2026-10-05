extends Control
## 共通UI部品「画面背景」。画面の全面に背景画像を1枚表示する（ARC-207, PRS-607, PRS-608）。
## 下から、地（bg_base）、画像、暗幕（bg_scrim）の順に重なる。画像が無い、または読めない場合は、
## 画像と暗幕を出さず、地の単色にする（エラーは出さない）。色は共通Theme の Type Variation で決める（ARC-208）。
## クリックもフォーカスも受けない。GameFlow と GameDatabase には依存しない。

## 表示する画像のパス。`res://assets/backgrounds/{画面名}.png`（PRS-607）。
@export var texture_path: String = "":
	set(value):
		texture_path = value
		if is_node_ready():
			_apply()

@onready var _image: TextureRect = %Image
@onready var _scrim: Control = %Scrim


func _ready() -> void:
	_apply()


func _apply() -> void:
	var texture: Texture2D = null
	# 存在を確かめてから読む。無い画像を load() してエンジンのエラーを出さない
	if texture_path != "" and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	_image.texture = texture
	_image.visible = texture != null
	_scrim.visible = texture != null
