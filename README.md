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

## 版

| 対象 | 版 |
| --- | --- |
| 設計書 | v1.0 |
| 固定データ（`content_version`） | 0.1.0 |
| セーブ形式（`schema_version`） | 1 |
