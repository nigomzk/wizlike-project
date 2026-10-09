# wizlike-project

探索・パーティ編成を楽しむ、一人称視点のダンジョン探索RPGプロジェクト。

Godot 4.5.1 / GDScript で制作する、Windows 11向けの1人用ダンジョンRPGです。初回版の仕様は確定しており、ゲーム本体は未実装です。

## 設計書

- **[docs/index.md](docs/index.md)** — 設計書の入口。読む順、規則IDの引き方、実装時の原則
- [docs/spec/](docs/spec/) — ゲームルール（用語・範囲・遷移・街・冒険者・所持品・探索・戦闘・クエスト・セーブ）
- [docs/tech/](docs/tech/) — 技術設計（構成・データモデル・マップ制作・画面・テスト）
- [data/](data/) — 数値・ID・文章の唯一の正。CSV形式
- [docs/plan/](docs/plan/) — マイルストーンとIssueの共通要件
- [docs/decisions/log.md](docs/decisions/log.md) — 決定記録

実装は `docs/index.md` から読み始め、`docs/plan/milestones.md` の順序に沿って進めてください。

## テストの実行

Godot 4.5.1 の実行ファイルのパスを、環境変数 `GODOT` に設定しておく（リポジトリには絶対パスを書かない）。標準出力と終了コードを得るため、Windows ではコンソール版（`..._console.exe`）を指す。

```powershell
$env:GODOT = "<Godot 4.5.1 の実行ファイル>"
```

プロジェクトのルートで、ヘッドレスのテストを実行する。

```powershell
& $env:GODOT --headless --path . --script tests/run_all.gd; $LASTEXITCODE
```

段階やIssueの完了判定では、その範囲の受入IDを `--require` に指定する。指定したIDが成功以外（失敗またはスキップ）なら、終了コードは非0になる。

```powershell
& $env:GODOT --headless --path . --script tests/run_all.gd -- --require=T01,T02,T03,T04,A01; $LASTEXITCODE
```

| 結果 | 終了コード |
| --- | --- |
| 失敗が0件で、`--require` の指定をすべて満たす | 0 |
| 失敗が1件以上、または `--require` のIDに成功以外がある | 非0 |

- 未実装の受入IDは、スキップとして一覧に出力される。スキップは成功に数えない
- 失敗したテストのID、期待値、実測値は標準出力に出る
- 初回の `--import` は不要。`.godot/` を削除した状態からも、そのまま完走する
- `.godot/` がない状態では、フォントのインポート結果がないため、テストの出力にフォントの読込エラーが出る。テストの結果には影響しない。エディターで一度開く（または `--headless --import` を実行する）と出なくなる
- テストはエディターを起動しない
- `-- --files=res://a.gd,res://b.gd` で、実行するテストファイルを差し替えられる（TST-109）。ランナーの検証（T01〜T04）が、`tests/fixtures/` のフィクスチャを子プロセスで実行するために使う

## Claude Code の個人設定

`/issue-implementing` のコード解説では、習得済みの GDScript の語を解説から外せる。一覧は人ごとに違うため、リポジトリではなく個人ファイルに書く。

| 項目 | 内容 |
| --- | --- |
| 場所 | `~/.claude/wizlike-known-terms.md`（Windows では `%USERPROFILE%\.claude\wizlike-known-terms.md`） |
| 作り方 | `/issue-implementing` を実行すると、ファイルがなければ Claude が作るかを確認する。雛形は `.claude/skills/issue-implementing/templates/known-terms-personal.md` |
| 追記 | 「`signal` は習得した」のように Claude に伝える。自分で1行ずつ書いてもよい |
| git | 管理しない。コミットもpushも不要 |

ファイルがなくても動くが、習得済みの語は何も除外されず、検証で警告が出る。書式の詳細は [known-terms.md](.claude/skills/issue-implementing/criteria/known-terms.md)。

### コード解説の出力先

`/issue-implementing` が作るコード解説の資料（HTML）は、リポジトリの外のフォルダに `issue-<N>.html` として書き出す。フォルダは環境変数 `CODE_GUIDE_DIR` で指定する。

```powershell
[Environment]::SetEnvironmentVariable("CODE_GUIDE_DIR", "<出力先フォルダ>", "User")
```

- 設定後に、Claude Code（デスクトップアプリ）とターミナルを開き直す。開いたままだと、新しい値が見えない
- 未設定のままでも、Claude がパスを尋ねる。ただし、そのセッションの資料の出力先にしか使われない
- 資料はコミットしない。リポジトリは公開されているため、PR本文にもパスを書かない
- Node.js が必要（資料を作るスクリプトが `node` で動く）

## 仮素材

初回版は、自作の単純な図形による仮素材を使う（PRS-601）。文字は画像へ焼き込まない（PRS-003）。正式な画像は、同じパスと拡張子で上書きすれば、ロジックを変えずに差し替えられる（PRS-602, PRS-607, DAT-228）。

| 素材 | パス | 内容 |
| --- | --- | --- |
| 街の背景 | `assets/backgrounds/town.png`（1920×1080） | 夜明け前の空、月、丘、遺跡の塔、灯りのついた家々、中央へ延びる道。重要な図柄は中央の4:3の範囲に置く（PRS-608） |
| 顔 | `assets/portraits/portrait_01.png` 〜 `portrait_10.png`（128×128） | 背景の色・髪の形と色・肌・服の色を変えた、胸から上の図形（DAT-522） |

生成方法：使い捨ての Godot スクリプトで、`Image.create()` と `fill_rect()`、楕円の塗りつぶしだけで描き、`save_png()` で書き出した。スクリプトはリポジトリに置かない。下のスクリプトで再現できる。書き出した後に、`--import` で `.import` を作る。

```powershell
& $env:GODOT --headless --path . --script <スクリプトのパス>
& $env:GODOT --headless --path . --import
```

<details>
<summary>生成スクリプト（gen_assets.gd）</summary>

```gdscript
extends SceneTree
## 使い捨ての仮素材の生成スクリプト（Issue #11）。単純な図形だけを Image に描き、PNG で書き出す。文字は描かない（PRS-003）。
## 実行: godot --headless --path <プロジェクト> --script <このファイル>

const OUT_PORTRAITS := "res://assets/portraits/"
const OUT_BACKGROUND := "res://assets/backgrounds/town.png"

# 顔10枚の配色: [背景, 髪, 肌, 服]
const PORTRAIT_COLORS := [
	[Color("#2F6A78"), Color("#3A2A20"), Color("#F0C8A0"), Color("#8C3A3A")],
	[Color("#3C4A8C"), Color("#C8A040"), Color("#F4D0B0"), Color("#E4ECF4")],
	[Color("#4A7A4A"), Color("#6A3A20"), Color("#D8A878"), Color("#3A5A9A")],
	[Color("#7A4A7A"), Color("#202028"), Color("#F0C8A0"), Color("#C8C0A0")],
	[Color("#8C6A2F"), Color("#B03A30"), Color("#F4D0B0"), Color("#2F3A5A")],
	[Color("#2F5A6A"), Color("#E4ECF4"), Color("#D8A878"), Color("#5A3A6A")],
	[Color("#6A2F3C"), Color("#403028"), Color("#F0C8A0"), Color("#3A7A6A")],
	[Color("#3A3A4A"), Color("#8C5A30"), Color("#C89868"), Color("#A04A2F")],
	[Color("#2F7A6A"), Color("#2A2A5A"), Color("#F4D0B0"), Color("#D8C060")],
	[Color("#5A4A3A"), Color("#6A8C3A"), Color("#D8A878"), Color("#2A3A4A")],
]
const PORTRAIT_SIZE := 128


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PORTRAITS))
	for i in PORTRAIT_COLORS.size():
		var image := _portrait(i)
		image.save_png(ProjectSettings.globalize_path(OUT_PORTRAITS + "portrait_%02d.png" % (i + 1)))
	_town().save_png(ProjectSettings.globalize_path(OUT_BACKGROUND))
	print("generated")
	quit()


func _portrait(index: int) -> Image:
	var colors: Array = PORTRAIT_COLORS[index]
	var image := Image.create(PORTRAIT_SIZE, PORTRAIT_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(colors[0])
	# 肩（服）
	_ellipse(image, Vector2(64, 138), Vector2(54, 38), colors[3])
	# 首
	image.fill_rect(Rect2i(56, 82, 16, 18), colors[2])
	# 髪（後ろ側）。番号で形を変える
	var style := index % 5
	match style:
		0: _ellipse(image, Vector2(64, 56), Vector2(34, 36), colors[1])
		1: image.fill_rect(Rect2i(26, 40, 76, 62), colors[1])
		2: _ellipse(image, Vector2(64, 50), Vector2(30, 30), colors[1])
		3: image.fill_rect(Rect2i(30, 30, 68, 30), colors[1])
		4: _ellipse(image, Vector2(64, 60), Vector2(38, 42), colors[1])
	# 顔
	_ellipse(image, Vector2(64, 62), Vector2(24, 28), colors[2])
	# 前髪
	image.fill_rect(Rect2i(42, 36, 44, 10), colors[1])
	# 目
	var eye := Color("#1A1A24")
	_ellipse(image, Vector2(54, 62), Vector2(3, 4), eye)
	_ellipse(image, Vector2(74, 62), Vector2(3, 4), eye)
	# 口
	image.fill_rect(Rect2i(58, 76, 12, 2), Color("#8C4A40"))
	return image


func _town() -> Image:
	var width := 1920
	var height := 1080
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	# 夜明け前の空。上から下へ、濃い紺から青緑へ
	var top := Color("#0B1230")
	var bottom := Color("#3A7A8C")
	for y in 640:
		image.fill_rect(Rect2i(0, y, width, 1), top.lerp(bottom, float(y) / 640.0))
	# 月
	_ellipse(image, Vector2(1280, 170), Vector2(60, 60), Color("#E4ECF4"))
	# 遠くの丘（中央の4:3の外へも広がる）
	_ellipse(image, Vector2(400, 700), Vector2(700, 190), Color("#1C3A4A"))
	_ellipse(image, Vector2(1500, 720), Vector2(800, 210), Color("#17323F"))
	# 遺跡の塔（中央やや右。重要な図柄は中央の4:3に置く）
	var ruin := Color("#10222C")
	image.fill_rect(Rect2i(1010, 330, 90, 380), ruin)
	image.fill_rect(Rect2i(1000, 320, 22, 40), ruin)
	image.fill_rect(Rect2i(1044, 320, 22, 40), ruin)
	image.fill_rect(Rect2i(1088, 320, 22, 40), ruin)
	image.fill_rect(Rect2i(930, 520, 60, 190), ruin)
	image.fill_rect(Rect2i(1120, 560, 70, 150), ruin)
	# 地面
	image.fill_rect(Rect2i(0, 700, width, height - 700), Color("#142A33"))
	image.fill_rect(Rect2i(0, 700, width, 6), Color("#2F6A78"))
	# 道（中央へ向かって細くなる）
	for y in range(706, height):
		var t := float(y - 706) / float(height - 706)
		var half := int(lerpf(40.0, 300.0, t))
		image.fill_rect(Rect2i(960 - half, y, half * 2, 1), Color("#2A4A52").lerp(Color("#3A6068"), t))
	# 家々（左右に並べる）
	var houses := [
		[300, 520, 180, 190], [520, 560, 150, 150], [1230, 540, 170, 170],
		[1440, 500, 200, 210], [120, 580, 140, 130], [1680, 570, 150, 140],
	]
	for house in houses:
		_house(image, house[0], house[1], house[2], house[3])
	return image


func _house(image: Image, x: int, y: int, w: int, h: int) -> void:
	var wall := Color("#1E3A46")
	var roof := Color("#0F2630")
	var window := Color("#F0C878")
	image.fill_rect(Rect2i(x, y + h / 3, w, h - h / 3), wall)
	# 三角の屋根
	var roof_h := h / 3
	for row in roof_h:
		var inset := int(float(w) / 2.0 * (1.0 - float(row + 1) / float(roof_h)))
		image.fill_rect(Rect2i(x - 8 + inset, y + row, w + 16 - inset * 2, 1), roof)
	# 灯りのついた窓
	var win := maxi(w / 6, 12)
	image.fill_rect(Rect2i(x + w / 5, y + h / 2, win, win), window)
	image.fill_rect(Rect2i(x + w - w / 5 - win, y + h / 2, win, win), window)
	image.fill_rect(Rect2i(x + w / 2 - win / 2, y + h - win * 2, win, win * 2), Color("#0A161C"))


func _ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	var x0 := maxi(int(center.x - radius.x), 0)
	var x1 := mini(int(center.x + radius.x), image.get_width() - 1)
	var y0 := maxi(int(center.y - radius.y), 0)
	var y1 := mini(int(center.y + radius.y), image.get_height() - 1)
	for y in range(y0, y1 + 1):
		var dy := (float(y) - center.y) / radius.y
		var span := 1.0 - dy * dy
		if span < 0.0:
			continue
		var half := radius.x * sqrt(span)
		var xa := maxi(int(center.x - half), 0)
		var xb := mini(int(center.x + half), image.get_width() - 1)
		if xb >= xa:
			image.fill_rect(Rect2i(xa, y, xb - xa + 1, 1), color)
```

</details>

## 版

| 対象 | 版 |
| --- | --- |
| 設計書 | v1.0 |
| 固定データ（`content_version`） | 0.1.0 |
| セーブ形式（`schema_version`） | 1 |
