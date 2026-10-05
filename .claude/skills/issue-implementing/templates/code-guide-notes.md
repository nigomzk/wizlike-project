# コード解説のJSONの型

手順8-2で `code-explainer` が `<scratchpad>/issue-<N>/cycle-<c>/code-guide-notes.json` に書き出す。メインエージェントは `scripts/build-code-guide.mjs` でこのJSONを検証し、`templates/code-guide.html` に埋め込んでHTMLにする。

**コードの本文と、変更した行の印は書かない。** スクリプトが git から取る。JSONに書くのは解説だけである。

---

```json
{
  "issue": 2,
  "title": "<Issueのタイトル>",
  "overview": {
    "nodes": [
      { "id": "main", "label": "main.tscn" },
      { "id": "flow", "label": "GameFlow", "file": "scripts/core/game_flow.gd" },
      { "id": "host", "label": "ScreenHost", "file": "scripts/ui/screen_host.gd" }
    ],
    "edges": [
      { "from": "main", "to": "flow", "kind": "tree", "label": "子ノード" },
      { "from": "flow", "to": "host", "kind": "signal", "label": "state_changed" }
    ],
    "readingOrder": [
      { "file": "scripts/core/game_flow.gd", "role": "状態と遷移の判定を持つ中心。ほかの全ファイルがこれを参照する" }
    ]
  },
  "files": [
    {
      "path": "scripts/ui/placeholder.gd",
      "summary": "遷移先が未実装の操作が開く仮画面。`ScreenHost` が生成し、戻る操作を `GameFlow` へ伝える",
      "scenes": ["scenes/ui/placeholder.tscn"],
      "sections": [
        {
          "name": "宣言部",
          "startLine": 1,
          "endLine": 7,
          "summary": "`Control` を継承した画面のスクリプト。GameFlow への参照と「戻る」ボタンを持つ",
          "notes": [
            {
              "line": 6,
              "match": "@onready",
              "category": "language",
              "text": "「戻る」ボタンを、`_ready()` の直前に `placeholder.tscn` の `Back` ノードから取得する",
              "terms": ["onready", "unique-name"]
            }
          ]
        },
        {
          "name": "_unhandled_input(event)",
          "startLine": 24,
          "endLine": 28,
          "summary": "どのUIも処理しなかった入力をエンジンから受け取り、Esc ならタイトルへ戻る",
          "notes": [
            {
              "line": 27,
              "match": "set_input_as_handled",
              "category": "engine",
              "text": "入力を処理済みにして、ほかのノードへ伝わらないようにする。直後の `go_back()` でこの画面がツリーから外れると `get_viewport()` が null になるため、先に呼んでいる",
              "source": "https://docs.godotengine.org/en/4.5/classes/class_viewport.html"
            }
          ]
        }
      ]
    }
  ],
  "glossary": [
    {
      "id": "onready",
      "term": "@onready",
      "category": "language",
      "text": "変数の初期化を、ノードの `_ready()` が呼ばれる直前まで遅らせる注釈。…",
      "source": "https://docs.godotengine.org/en/4.5/tutorials/scripting/gdscript/gdscript_basics.html"
    }
  ]
}
```

---

## 項目

| 項目 | 必須 | 書き方 |
| --- | --- | --- |
| `issue` / `title` | ○ | Issue番号（整数）とタイトル |
| `overview.nodes[]` | ○ | 関係図の箱。`id` は英字で始まる英数字。`label` はノード名やクラス名。スクリプトを持つものは `file` にパスを書く。シーン（`main.tscn` など）を箱にしてよい |
| `overview.edges[]` | ○ | 関係図の矢印。12本まで。同じ2つの箱の間の同じ向きの呼び出しは1本にまとめる（`criteria/code-guide.md` の5）。`kind` は `tree`（シーンの親子）/ `signal`（シグナルでの通知）/ `call`（メソッドの呼び出し）/ `instance`（シーンの生成）/ `other`。`label` はシグナル名やメソッド名 |
| `overview.readingOrder[]` | ○ | 変更した `.gd`（`tests/` を除く）をすべて1回ずつ、依存される側から順に並べる。`role` は1文 |
| `files[].path` | ○ | このPRで追加・変更した `.gd`（`tests/` を除く）。過不足があるとスクリプトが止まる |
| `files[].summary` | ○ | `criteria/code-guide.md` の3 |
| `files[].scenes` | — | このスクリプトを付けたシーンや、注釈から参照するシーンのパス |
| `sections[]` | ○ | 行の順に並べ、重ねない。新規ファイルは空行以外の全行を、既存ファイルは変更した行を、どれかの節に含める |
| `sections[].name` | ○ | 関数は `name(引数名)`、宣言部は「宣言部」 |
| `notes[].line` / `match` | ○ | 注釈を付ける行と、その行に実際に現れる語句。語句が見つからないとスクリプトが止まる |
| `notes[].category` | ○ | `language` / `engine` / `design` |
| `notes[].terms` | — | 参照する用語集の `id` |
| `notes[].source` / `unverified` | 言語・エンジンで○ | どちらか一方。`source` は `https://docs.godotengine.org/en/4.5/` 配下だけ |
| `notes[].ruleIds` | 設計で○ | 根拠の規則ID。設計書（`docs/`）の定義行にないIDはスクリプトが止める |
| `glossary[].id` | ○ | 英小文字・数字・ハイフン（例：`onready`、`unique-name`、`call-deferred`） |
| `glossary[].source` / `unverified` | 言語・エンジンで○ | 注釈と同じ |

前のサイクルのJSONがある場合は、それを引き継いで書き直す。変更のない節の解説は、コードと食い違っていなければそのまま残し、行番号のずれだけを直す。
