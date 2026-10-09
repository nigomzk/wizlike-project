#!/usr/bin/env node
// issue-implementing の手順5-1と手順9で使う。PR本文の「対応した規則ID」節と「受入IDごとの結果」表の下書きを、
// 差分・Issue本文・設計書・テストのログから機械的に作り、PR本文に転記する前の検査もする。
//
// 機械が決めるもの：規則IDの集合（省略表記の展開を含む）、仕様根拠／参照のみの区分、対応ファイル、
// 受入IDの一覧と、検証する規則ID、先に書いたとき・実装後の結果。
// 人が書くもの：「規則（要約）」と「確認する内容（要約）」。下書きには、設計書の原文の抜粋を「※」付きで入れる。
// 抜粋を、条件と例外を残した要約に書き直し、「※」を消す。
//
// draft は、id-table.md のほかに rules-excerpt.md（今回のIDの原文。定義行を省略せずに載せたもの）も書く。
// レビュー担当が、設計書を各自で開き直さずにIDの原文を読めるようにするため。
//
// lint は、差分の追加行にある規則IDと受入IDの省略表記（範囲、接頭辞の省略）を検出する。LLMのレビューに頼らず、
// レビューを依頼する前に機械で直すため。docs/、.claude/、Markdown、.import、.uid は対象外。
//
// 使い方:
//   node draft-id-table.mjs draft --issue <issue.md> --latest <実装後のログ> --out <id-table.md>
//                           [--red <先に書いたときのログ>] [--excerpt-out <rules-excerpt.md>]
//                           [--base origin/main] [--head HEAD] [--cwd <リポジトリ>]
//   node draft-id-table.mjs check --file <id-table.md> [--pr-body <PR本文>]
//   node draft-id-table.mjs lint [--base origin/main] [--head HEAD] [--cwd <リポジトリ>]
//
// 終了コード: 0 = 成功 / 1 = check か lint で誤りがある / 2 = 引数や git の誤り

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const EXCERPT_MARK = "※";

function usage(message) {
  console.error("誤り: " + message);
  console.error("使い方: node draft-id-table.mjs draft --issue <issue.md> --latest <log> --out <id-table.md> [--red <log>] [--base origin/main] [--head HEAD] [--cwd <dir>]");
  console.error("        node draft-id-table.mjs check --file <id-table.md> [--pr-body <file>]");
  console.error("        node draft-id-table.mjs lint [--base origin/main] [--head HEAD] [--cwd <dir>]");
  process.exit(2);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (command !== "draft" && command !== "check" && command !== "lint") usage("最初の引数は draft か check か lint");
  const args = { command, base: "origin/main", head: "HEAD", cwd: process.cwd() };
  for (let i = 0; i < rest.length; i += 2) {
    if (!rest[i].startsWith("--")) usage("不明な引数: " + rest[i]);
    const name = rest[i].slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (rest[i + 1] === undefined) usage(rest[i] + " に値がない");
    args[name] = rest[i + 1];
  }
  if (command === "draft" && (!args.issue || !args.latest || !args.out)) usage("--issue, --latest, --out は必須");
  if (command === "check" && !args.file) usage("--file は必須");
  return args;
}

// ---------- ID の抽出 ----------

/** 「PRS-008」「TST-003, 004」「FLW-111〜113」を、1件ずつの完全な形に展開する。範囲で展開したIDには ranged を付ける。 */
function expandRuleIds(text) {
  const found = [];
  const re = /([A-Z]{3})-(\d{3})(?:〜(\d{3}))?((?:\s*[,、]\s*\d{3}(?:〜\d{3})?(?!\d))*)/g;
  for (const m of text.matchAll(re)) {
    const prefix = m[1];
    const push = (from, to) => {
      const a = Number(from);
      const b = to === undefined ? a : Number(to);
      for (let n = a; n <= b; n++) found.push({ id: `${prefix}-${String(n).padStart(3, "0")}`, ranged: to !== undefined && n !== a && n !== b });
    };
    push(m[2], m[3]);
    for (const t of m[4].matchAll(/(\d{3})(?:〜(\d{3}))?/g)) push(t[1], t[2]);
  }
  return found;
}

/** 受入ID（T01、FL09、U36）を、範囲（U03〜U05）を展開して返す。 */
function expandAcceptanceIds(text) {
  const out = [];
  for (const m of text.matchAll(/\b([A-Z]{1,2})(\d{2})(?:〜(?:[A-Z]{1,2})?(\d{2}))?/g)) {
    const a = Number(m[2]);
    const b = m[3] === undefined ? a : Number(m[3]);
    for (let n = a; n <= b; n++) out.push(`${m[1]}${String(n).padStart(2, "0")}`);
  }
  return out;
}

// ---------- git ----------

function makeGit(cwd) {
  return (...a) => {
    try {
      return execFileSync("git", a, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
    } catch (e) {
      console.error("git " + a.join(" ") + " が失敗した: " + (e.stderr || e.message));
      process.exit(2);
    }
  };
}

/** head のコミットにある docs/ 配下の Markdown を、{パス: 本文} で返す。 */
function readDocs(git, head) {
  const docs = {};
  const names = git("ls-tree", "-r", "--name-only", head, "--", "docs").split("\n").filter((n) => n.endsWith(".md"));
  for (const name of names) docs[name] = git("show", `${head}:${name}`);
  return docs;
}

/** 規則の定義行（| PRS-607 | ... |）と受入IDの定義行（| FL09 | ... |）を引く索引を作る。 */
function indexDefinitions(docs) {
  const rules = {};
  const acceptances = {};
  for (const [file, text] of Object.entries(docs)) {
    text.split("\n").forEach((line, i) => {
      const cells = splitRow(line);
      if (!cells) return;
      if (/^[A-Z]{3}-\d{3}$/.test(cells[0]) && !rules[cells[0]]) rules[cells[0]] = { file, line: i + 1, cells: cells.slice(1) };
      else if (/^[A-Z]{1,2}\d{2}$/.test(cells[0]) && !acceptances[cells[0]]) acceptances[cells[0]] = { file, line: i + 1, cells: cells.slice(1) };
    });
  }
  return { rules, acceptances };
}

function splitRow(line) {
  if (!line.startsWith("|")) return null;
  const cells = line.replace(/^\|/, "").replace(/\|\s*$/, "").split(/(?<!\\)\|/).map((c) => c.trim());
  return cells.length >= 2 ? cells : null;
}

/** 差分の追加行を {file, text} で返す。画像などのバイナリは追加行を持たない。 */
function addedLines(git, base, head) {
  const diff = git("diff", "--no-color", "--text", "-U0", `${base}...${head}`);
  const out = [];
  let file = null;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ ")) file = line.slice(4).replace(/^b\//, "");
    else if (line.startsWith("+") && file && file !== "/dev/null") out.push({ file, text: line.slice(1) });
  }
  return out;
}

// ---------- 集計 ----------

function collectCitations(lines, defined) {
  const files = new Map(); // id -> Set(file)
  const add = (id, file) => {
    if (!files.has(id)) files.set(id, new Set());
    files.get(id).add(file);
  };
  for (const { file, text } of lines) {
    if (file.startsWith("docs/")) {
      const own = text.match(/^\|\s*([A-Z]{3}-\d{3})\s*\|/);
      if (own) {
        // 規則の定義行：その規則自身のIDだけを集める。本文に現れるIDは集めない
        add(own[1], file);
        continue;
      }
      if (/^\|\s*[A-Z]{1,2}\d{2}\s*\|/.test(text)) continue; // 受入条件の定義行：本文のIDは集めない
    }
    for (const { id, ranged } of expandRuleIds(text)) if (!ranged || defined[id]) add(id, file);
  }
  return files;
}

function section(markdown, heading) {
  const m = markdown.match(new RegExp(`^##\\s+${heading}[^\\n]*\\n([\\s\\S]*?)(?=^##\\s|(?![\\s\\S]))`, "m"));
  return m ? m[1] : "";
}

function automatedPrefixes(docs) {
  for (const text of Object.values(docs)) {
    const m = text.match(/自動検証は\s*([A-Z](?:[A-Z]?,\s*[A-Z][A-Z]?)*)\s*の計/);
    if (m) return new Set(m[1].split(",").map((s) => s.trim()));
  }
  console.error("設計書に「自動検証は T, A, ... の計」の文が見つからない（受入IDの索引。TST-3xx）");
  process.exit(2);
}

function logResult(log, id) {
  if (log === null) return "記録なし";
  const esc = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (new RegExp(`^(FAIL ${esc}\\b|REQUIRE ${esc}: failed)`, "m").test(log)) return "失敗";
  if (new RegExp(`^SKIP ${esc}\\b`, "m").test(log)) return "スキップ";
  const exit = log.match(/^exit=(\d+)\s*$/m);
  if (!exit) return "実行不能（終了コードの記録なし）";
  return exit[1] === "0" ? "成功" : "未確認（ログにIDなし）";
}

function excerpt(cells, max = 140) {
  const text = cells.join(" / ").replace(/\s+/g, " ");
  return text.length > max ? text.slice(0, max) + "…" : text;
}

// ---------- draft ----------

function draft(args) {
  const git = makeGit(args.cwd);
  const docs = readDocs(git, args.head);
  const { rules, acceptances } = indexDefinitions(docs);
  const issue = readFileSync(args.issue, "utf8");
  const latest = readFileSync(args.latest, "utf8");
  const red = args.red ? readFileSync(args.red, "utf8") : null;
  const auto = automatedPrefixes(docs);

  const lines = addedLines(git, args.base, args.head);
  const citations = collectCitations(lines, rules);

  // Issue の仕様根拠
  const specIds = new Set(expandRuleIds(section(issue, "仕様根拠")).filter((x) => !x.ranged || rules[x.id]).map((x) => x.id));

  // 受入ID：DoD と、壊してはいけないもの
  const dod = new Set(expandAcceptanceIds(section(issue, "DoD")));
  const keep = new Set(expandAcceptanceIds(section(issue, "壊してはいけないもの")).filter((id) => !dod.has(id)));
  const automated = [...dod, ...keep].filter((id) => auto.has(id.replace(/\d+$/, "")));
  const manual = [...dod, ...keep].filter((id) => !auto.has(id.replace(/\d+$/, "")));

  // 受入IDの根拠の規則ID。DoD のものだけを集める。壊してはいけないものの規則IDは、このPRで触っていない既存の規則への参照のため、
  // 載せない（PR本文を長くしない）。受入IDの索引から引ける
  const accRules = new Map();
  for (const id of automated.filter((x) => dod.has(x))) {
    const def = acceptances[id];
    const ids = def ? expandRuleIds(def.cells[def.cells.length - 1]).filter((x) => !x.ranged || rules[x.id]).map((x) => x.id) : [];
    accRules.set(id, [...new Set(ids)]);
  }

  const allIds = new Set([...specIds, ...citations.keys(), ...[...accRules.values()].flat()]);
  const refOnly = [...allIds].filter((id) => !specIds.has(id)).sort();
  const spec = [...specIds].sort();

  const filesFor = (id, fallback) => {
    const set = citations.get(id);
    if (!set || set.size === 0) return fallback;
    return [...set].sort((a, b) => Number(a.startsWith("docs/")) - Number(b.startsWith("docs/")) || a.localeCompare(b)).join(", ");
  };
  const ruleRow = (id, fallback) => {
    const def = rules[id];
    const summary = def ? `${EXCERPT_MARK}${excerpt(def.cells)}` : "（設計書に存在しない）";
    return `| ${id} | ${summary} | ${filesFor(id, fallback)} |`;
  };
  const table = (ids, fallback) =>
    ids.length === 0
      ? ["なし", ""]
      : ["| 規則ID | 規則（要約） | 対応ファイル |", "| --- | --- | --- |", ...ids.map((id) => ruleRow(id, fallback)), ""];

  const out = [];
  out.push(`# ID一覧の下書き（${args.head}。${args.base} との差分）`, "");
  out.push(`${EXCERPT_MARK}の付いた行は、設計書の原文の抜粋である。条件と例外を残した要約に書き直し、${EXCERPT_MARK}を消す。`, "");
  out.push("## 対応した規則ID", "");
  out.push("<details>", `<summary>仕様根拠（${spec.length}件）</summary>`, "", ...table(spec, "（差分に引用なし）"), "</details>", "");
  out.push("<details>", `<summary>参照のみ（${refOnly.length}件）</summary>`, "", ...table(refOnly, "（PR本文のみ）"), "</details>", "");
  const content = (id) => {
    const def = acceptances[id];
    return def ? `${EXCERPT_MARK}${excerpt(def.cells.slice(0, -1))}` : "（設計書に存在しない）";
  };
  const dodIds = automated.filter((id) => dod.has(id));
  const keepIds = automated.filter((id) => !dod.has(id));
  out.push("## 受入IDごとの結果", "");
  out.push("### DoD", "");
  if (dodIds.length === 0) out.push("なし", "");
  else {
    out.push("| 受入ID | 確認する内容（要約） | 検証する規則ID | 先に書いたとき（TDD） | 実装後 |");
    out.push("| --- | --- | --- | --- | --- |");
    for (const id of dodIds) {
      const ruleList = accRules.get(id).join(", ") || "（根拠なし）";
      out.push(`| ${id} | ${content(id)} | ${ruleList} | ${logResult(red, id)} | ${logResult(latest, id)} |`);
    }
    out.push("");
  }
  // 壊してはいけないもの：折りたたむ。表は消さない（何のテストを実施したかをPR上に残す）。規則IDの列は設けない
  const keepResults = keepIds.map((id) => logResult(latest, id));
  const passed = keepResults.filter((r) => r === "成功").length;
  const keepSummary = keepIds.length === 0 ? "なし" : passed === keepIds.length ? `${keepIds.length}件・全件成功` : `${keepIds.length}件・成功 ${passed}件・それ以外 ${keepIds.length - passed}件`;
  out.push("<details>", `<summary>壊してはいけない（${keepSummary}）</summary>`, "");
  if (keepIds.length === 0) out.push("なし", "");
  else {
    out.push("| 受入ID | 確認する内容（要約） | 実装後 |");
    out.push("| --- | --- | --- |");
    keepIds.forEach((id, i) => out.push(`| ${id} | ${content(id)} | ${keepResults[i]} |`));
    out.push("");
  }
  out.push("</details>", "");
  out.push("## 手動確認の受入ID（参考。PR本文の「Godotでの手動確認」に書く）", "");
  out.push(manual.length === 0 ? "なし" : manual.map((id) => `- ${id}（${dod.has(id) ? "DoD" : "壊してはいけない"}）`).join("\n"), "");

  writeFileSync(args.out, out.join("\n"), "utf8");

  // レビュー担当向けの原文。設計書の定義行を、省略せずに載せる
  const excerptPath = args.excerptOut || join(dirname(args.out), "rules-excerpt.md");
  const excerptLines = [
    `# 規則IDと受入IDの原文（${args.head}。${args.base} との差分）`,
    "",
    "draft-id-table.mjs が、設計書の定義行をそのまま抜き出したもの。レビュー担当は、ここに載っているIDのために設計書を開き直さない。",
    "載っていない規則や、周辺の文脈が要る場合だけ、設計書を開く。",
    "",
    "## 規則ID",
    "",
    ...[...allIds].sort().map((id) => (rules[id] ? `- **${id}**（${rules[id].file}:${rules[id].line}）：${rules[id].cells.join(" / ")}` : `- **${id}**：（設計書に存在しない）`)),
    "",
    "## 受入ID（DoD と壊してはいけないもの。手動確認を含む）",
    "",
    ...[...automated, ...manual].map((id) => {
      const def = acceptances[id];
      return def ? `- **${id}**（${def.file}:${def.line}）：${def.cells.join(" / ")}` : `- **${id}**：（設計書に存在しない）`;
    }),
    "",
  ];
  writeFileSync(excerptPath, excerptLines.join("\n"), "utf8");

  const undefinedIds = [...allIds].filter((id) => !rules[id]);
  console.log(`規則ID ${allIds.size}件（仕様根拠 ${spec.length}、参照のみ ${refOnly.length}）、自動検証の受入ID ${automated.length}件、手動確認 ${manual.length}件`);
  if (undefinedIds.length) console.log("設計書に存在しないID: " + undefinedIds.join(", "));
  const missing = automated.filter((id) => !acceptances[id]);
  if (missing.length) console.log("受入IDの定義が見つからない: " + missing.join(", "));
  console.log("書き出した: " + args.out);
  console.log("書き出した: " + excerptPath);
}

// ---------- lint ----------

/** lint の対象外のファイル。設計書・スキル・Markdown は、IDの範囲表記を使ってよい（本文の書き方は別に決まっている） */
const LINT_SKIP = /^(docs\/|\.claude\/)|\.(md|import|uid)$/;
const LINT_RULES = [
  { re: /[A-Z]{3}-\d{3}\s*〜/, label: "規則IDの範囲表記（1件ずつ書く）" },
  { re: /[A-Z]{3}-\d{3}(?:\s*[,、]\s*\d{3}(?!\d))+/, label: "規則IDの接頭辞の省略（TST-003, TST-004 のように1件ずつ書く）" },
  { re: /(?<![A-Za-z-])[A-Z]{1,2}\d{2}\s*〜\s*[A-Z]{0,2}\d{2}(?!\d)/, label: "受入IDの範囲表記（1件ずつ書く）" },
];

function lint(args) {
  const git = makeGit(args.cwd);
  const diff = git("diff", "--no-color", "--text", "-U0", `${args.base}...${args.head}`);
  const problems = [];
  let file = null;
  let lineNo = 0;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ ")) {
      file = line.slice(4).replace(/^b\//, "");
      continue;
    }
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)/.exec(line);
    if (hunk) {
      lineNo = Number(hunk[1]);
      continue;
    }
    if (!line.startsWith("+") || !file || file === "/dev/null") continue;
    if (!LINT_SKIP.test(file)) {
      for (const { re, label } of LINT_RULES) {
        const m = re.exec(line);
        if (m) problems.push(`${file}:${lineNo}: ${label}: ${m[0]}`);
      }
    }
    lineNo++;
  }
  if (problems.length) {
    console.error(`lint の誤り（${problems.length}件）:\n- ` + problems.join("\n- "));
    process.exit(1);
  }
  console.log("lint に通った（IDの省略表記なし）");
}

// ---------- check ----------

function check(args) {
  const errors = [];
  const table = readFileSync(args.file, "utf8");

  if (table.includes(EXCERPT_MARK)) {
    const n = table.split("\n").filter((l) => l.includes(EXCERPT_MARK)).length;
    errors.push(`${EXCERPT_MARK}（原文の抜粋）が${n}行に残っている。要約に書き直す`);
  }
  for (const m of table.matchAll(/<summary>([^<（]+)（(\d+)件）<\/summary>([\s\S]*?)<\/details>/g)) {
    const rows = m[3].split("\n").filter((l) => /^\| [A-Z]{3}-\d{3} \|/.test(l)).length;
    if (rows !== Number(m[2])) errors.push(`「${m[1]}」の件数が表と合わない（見出し ${m[2]}、表 ${rows}）`);
  }
  for (const l of table.split("\n")) {
    if (/^\| [A-Z]{3}-\d{3} \|/.test(l) && /\|\s*\|/.test(l)) errors.push("空の欄がある行: " + l.slice(0, 40));
    if (/^\| [A-Z]{1,2}\d{2} \|/.test(l) && /\|\s*\|/.test(l)) errors.push("空の欄がある行: " + l.slice(0, 40));
  }
  const tableIds = new Set([...table.matchAll(/^\| ([A-Z]{3}-\d{3}) \|/gm)].map((m) => m[1]));

  if (args.prBody) {
    const body = readFileSync(args.prBody, "utf8");
    const abbreviated = [...body.matchAll(/[A-Z]{3}-\d{3}(?:\s*[,、]\s*\d{3}(?!\d)|〜)/g)].map((m) => m[0]);
    for (const a of abbreviated) errors.push(`IDの省略表記がある: ${a}`);
    const outside = body.replace(/## 対応した規則ID[\s\S]*?(?=\n## )/, "");
    for (const m of outside.matchAll(/[A-Z]{3}-\d{3}/g)) if (!tableIds.has(m[0])) errors.push(`本文に現れるIDが「対応した規則ID」の表にない: ${m[0]}`);
  }
  const unique = [...new Set(errors)];
  if (unique.length) {
    console.error("検査の誤り:\n- " + unique.join("\n- "));
    process.exit(1);
  }
  console.log(`検査に通った（規則ID ${tableIds.size}件）`);
}

const args = parseArgs(process.argv.slice(2));
if (args.command === "draft") draft(args);
else if (args.command === "lint") lint(args);
else check(args);
