#!/usr/bin/env node
// issue-implementing の手順8-2で使う。code-explainer が書いた解説のJSONを検証し、
// templates/code-guide.html に埋め込んで、コード解説の資料（1ファイルのHTML）を書き出す。
//
// コードの本文と、このPR・このサイクルで変更した行は、JSONではなく git から取る。
// 解説のJSONが行番号や対象ファイルを誤っていれば、HTMLを書き出さずに終了コード1で止まる。
//
// 使い方:
//   node build-code-guide.mjs --notes <解説のJSON> --out <HTMLのパス> [--cycle <c>] [--cycle-base <sha>]
//                             [--base origin/main] [--head HEAD] [--branch <名前>] [--pr <番号>]
//   node build-code-guide.mjs --notes <解説のJSON> --validate-only true [--cycle <c>] [--cycle-base <sha>]
//     --validate-only true は、検証だけを行い、HTMLを書き出さない（code-explainer が自分で誤りを直すために使う）
//
// 終了コード: 0 = 書き出した（警告は出力に出る） / 1 = 検証の誤りがある / 2 = 引数や git の誤り

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CATEGORIES = ["language", "engine", "design"];
const EDGE_KINDS = ["tree", "signal", "call", "instance", "other"];
const DOCS_PREFIX = "https://docs.godotengine.org/en/4.5/";
const RULE_ID = /^[A-Z]+-\d{3}$/;
/** 行の注釈の件数の目安。変更した行（空行を除く）に対する割合 */
const NOTE_RATIO_LIMIT = 0.3;
/** 習得済みの語の個人ファイル。人ごとに違うため、リポジトリの外（ホーム配下）に置く。worktree でも効く */
const PERSONAL_TERMS_PATH = join(homedir(), ".claude", "wizlike-known-terms.md");

function parseArgs(argv) {
  const args = { base: "origin/main", head: "HEAD", cycle: "1" };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (!key.startsWith("--")) usage("不明な引数: " + key);
    const name = key.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    const value = argv[++i];
    if (value === undefined) usage(key + " に値がない");
    args[name] = value;
  }
  args.validateOnly = args.validateOnly === "true";
  args.showKnownTermsPath = args.showKnownTermsPath === "true";
  if (args.showKnownTermsPath) return args;
  if (!args.notes || (!args.out && !args.validateOnly)) usage("--notes と --out は必須（--validate-only true のときは --out は不要）");
  args.cycle = Number(args.cycle);
  if (!Number.isInteger(args.cycle) || args.cycle < 1) usage("--cycle は1以上の整数");
  if (args.cycle >= 2 && !args.cycleBase) usage("--cycle が2以上のときは --cycle-base（サイクル開始時のコミット）が必須");
  return args;
}

function usage(message) {
  console.error("引数の誤り: " + message);
  console.error("使い方: node build-code-guide.mjs --notes <JSON> --out <HTML> [--cycle <c>] [--cycle-base <sha>] [--base origin/main] [--head HEAD] [--branch <名前>] [--pr <番号>]");
  console.error("        node build-code-guide.mjs --notes <JSON> --validate-only true [--cycle <c>] [--cycle-base <sha>]");
  console.error("        node build-code-guide.mjs --show-known-terms-path true   （習得済みの語の個人ファイルのパスを表示する）");
  process.exit(2);
}

function git(...args) {
  try {
    return execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  } catch (e) {
    console.error("git " + args.join(" ") + " に失敗: " + (e.stderr || e.message));
    process.exit(2);
  }
}

function gitOk(...args) {
  try {
    execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    return true;
  } catch {
    return false;
  }
}

// git diff -U0 の出力から、新しい側で追加・変更された行番号の集合を作る
function addedLines(from, to, path) {
  const out = git("diff", "-U0", "--no-color", "-M", from, to, "--", path);
  const set = new Set();
  for (const line of out.split("\n")) {
    const m = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/.exec(line);
    if (!m) continue;
    const start = Number(m[1]);
    const count = m[2] === undefined ? 1 : Number(m[2]);
    for (let n = start; n < start + count; n++) set.add(n);
  }
  return set;
}

// 習得済みの語は、チーム共通の criteria/known-terms.md と、個人ファイル（PERSONAL_TERMS_PATH）の両方から取る。
// 「- `語`」の行だけを読み、コードブロック（書式の例）の中は読まない。
// 英数字と _ だけの語は単語として、それ以外（@onready や := など）は文字列として照合する
function parseTermLines(text) {
  const terms = [];
  let inFence = false;
  for (const line of text.split("\n")) {
    if (line.trim().startsWith("```")) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = /^- `([^`]+)`\s*$/.exec(line.trim());
    if (m) terms.push(m[1]);
  }
  return terms;
}

function loadKnownTerms() {
  const here = dirname(fileURLToPath(import.meta.url));
  const shared = parseTermLines(readFileSync(join(here, "..", "criteria", "known-terms.md"), "utf8"));
  const personalFound = existsSync(PERSONAL_TERMS_PATH);
  const personal = personalFound ? parseTermLines(readFileSync(PERSONAL_TERMS_PATH, "utf8")) : [];
  const terms = [...new Set([...shared, ...personal])].map((term) => {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pattern = /^[A-Za-z0-9_]+$/.test(term) ? "(?<![A-Za-z0-9_])" + escaped + "(?![A-Za-z0-9_])" : escaped;
    return { term, re: new RegExp(pattern) };
  });
  return { terms, personalFound };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.showKnownTermsPath) {
    console.log(PERSONAL_TERMS_PATH);
    return;
  }
  const errors = [];
  const warnings = [];
  const err = (where, message) => errors.push(where + ": " + message);
  const warn = (where, message) => warnings.push(where + ": " + message);

  let notes;
  try {
    notes = JSON.parse(readFileSync(args.notes, "utf8").replace(/^﻿/, ""));
  } catch (e) {
    console.error("解説のJSONを読めない: " + e.message);
    process.exit(2);
  }

  const head = git("rev-parse", args.head).trim();
  const mergeBase = git("merge-base", args.base, head).trim();
  const branch = args.branch || git("rev-parse", "--abbrev-ref", "HEAD").trim();
  if (args.cycleBase && !gitOk("rev-parse", "--verify", args.cycleBase + "^{commit}")) usage("--cycle-base のコミットが見つからない: " + args.cycleBase);

  // このPRで追加・変更・改名した .gd（削除したものと tests/ 配下は解説しない）
  const changed = git("diff", "--name-status", "-M", "--diff-filter=AMR", mergeBase, head, "--", "*.gd", ":(exclude)tests")
    .split("\n").filter(Boolean).map((row) => {
      const cols = row.split("\t");
      return { status: cols[0][0] === "A" ? "added" : "modified", path: cols[cols.length - 1] };
    });
  const changedPaths = new Set(changed.map((c) => c.path));

  const noteFiles = Array.isArray(notes.files) ? notes.files : [];
  const glossary = Array.isArray(notes.glossary) ? notes.glossary : [];
  const glossaryIds = new Set();
  const ruleIdCache = new Map();
  const ruleExists = (id) => {
    if (!ruleIdCache.has(id)) ruleIdCache.set(id, gitOk("grep", "-q", "-F", "-e", "| " + id + " |", head, "--", "docs"));
    return ruleIdCache.get(id);
  };

  if (!notes.title) err("title", "Issueのタイトルがない");
  if (!Number.isInteger(notes.issue)) err("issue", "Issue番号が整数でない");

  // 習得済みの語（criteria/known-terms.md）は、言語の注釈にも用語集にも書かない
  const { terms: knownTerms, personalFound } = loadKnownTerms();
  if (!personalFound) warn("習得済みの語", "個人ファイルがない（" + PERSONAL_TERMS_PATH + "）。個人の習得済みの語は何も除外していない。作り方は criteria/known-terms.md");
  const checkKnown = (where, text) => {
    const hit = knownTerms.find((k) => k.re.test(text || ""));
    if (hit) err(where, "習得済みの語「" + hit.term + "」の解説は書かない（個人ファイルまたは criteria/known-terms.md）。この解説を外す");
  };

  // 用語集
  glossary.forEach((g, i) => {
    const where = "glossary[" + i + "](" + (g.id || "?") + ")";
    if (g.category === "language") checkKnown(where, g.term);
    if (!/^[a-z0-9-]+$/.test(g.id || "")) err(where, "id は英小文字・数字・ハイフンにする");
    if (glossaryIds.has(g.id)) err(where, "id が重複している");
    glossaryIds.add(g.id);
    if (!g.term) err(where, "term がない");
    if (!g.text) err(where, "text がない");
    if (!CATEGORIES.includes(g.category)) err(where, "category は " + CATEGORIES.join(" / ") + " のどれか");
    checkSource(g, where);
  });

  function checkSource(item, where) {
    if (item.category === "design") {
      if (item.ruleIds !== undefined) checkRuleIds(item.ruleIds, where);
      return;
    }
    const hasSource = typeof item.source === "string" && item.source.startsWith(DOCS_PREFIX);
    if (item.source && !hasSource) err(where, "source は " + DOCS_PREFIX + " 配下だけにする: " + item.source);
    if (hasSource && item.unverified) err(where, "source と unverified を同時に付けない");
    if (!hasSource && item.unverified !== true) err(where, "言語・エンジンの解説には source（Godot 4.5 の公式ドキュメント）か unverified: true が必要");
  }

  function checkRuleIds(ids, where) {
    if (!Array.isArray(ids)) return err(where, "ruleIds は配列にする");
    for (const id of ids) {
      if (!RULE_ID.test(id)) err(where, "規則IDは完全な形で1件ずつ書く（例：ARC-204）: " + id);
      else if (!ruleExists(id)) err(where, "規則IDが設計書（docs/ の定義行）に見つからない: " + id);
    }
  }

  // ファイルごとの解説
  for (const c of changed) {
    if (!noteFiles.some((f) => f.path === c.path)) err("files", "変更した .gd の解説がない: " + c.path);
  }
  const usedTerms = new Set();
  const builtFiles = [];
  let requiredLineCount = 0;
  noteFiles.forEach((f, fi) => {
    const where = "files[" + fi + "](" + (f.path || "?") + ")";
    if (!changedPaths.has(f.path)) return err(where, "このPRで追加・変更した .gd ではない（tests/ 配下は解説の対象外）");
    const info = changed.find((c) => c.path === f.path);
    const source = git("show", head + ":" + f.path).replace(/\r\n/g, "\n").replace(/\n$/, "").split("\n");
    const added = info.status === "added" ? new Set(source.map((_, i) => i + 1)) : addedLines(mergeBase, head, f.path);
    const cycleLines = args.cycle >= 2 ? addedLines(args.cycleBase, head, f.path) : new Set();
    if (!f.summary) err(where, "summary（ファイルの役割）がない");
    const sections = Array.isArray(f.sections) ? f.sections : [];
    if (!sections.length) err(where, "sections がない");

    // 解説が必要な行：新規ファイルは空行以外のすべて、既存ファイルはこのPRで追加・変更した空行以外の行
    const required = [...added].filter((n) => (source[n - 1] ?? "").trim() !== "");
    requiredLineCount += required.length;
    const covered = new Set();
    let lastEnd = 0;
    const builtSections = [];
    sections.forEach((s, si) => {
      const sw = where + ".sections[" + si + "](" + (s.name || "?") + ")";
      if (!s.name) err(sw, "name がない");
      if (!s.summary) err(sw, "summary（何をするか・いつ呼ばれるか）がない");
      if (!Number.isInteger(s.startLine) || !Number.isInteger(s.endLine) || s.startLine < 1 || s.endLine > source.length || s.startLine > s.endLine) {
        return err(sw, "行の範囲が不正: " + s.startLine + "–" + s.endLine + "（ファイルは " + source.length + " 行）");
      }
      if (s.startLine <= lastEnd) err(sw, "前の節と重なっているか、行の順に並んでいない");
      lastEnd = Math.max(lastEnd, s.endLine);
      for (let n = s.startLine; n <= s.endLine; n++) covered.add(n);

      const sNotes = (Array.isArray(s.notes) ? s.notes : []).map((n, ni) => ({ ...n, _order: ni }));
      sNotes.forEach((n) => {
        const nw = sw + ".notes[" + n._order + "]";
        if (!Number.isInteger(n.line) || n.line < s.startLine || n.line > s.endLine) return err(nw, "line が節の範囲外: " + n.line);
        if (!n.match) err(nw, "match（その行に現れる語句）がない");
        else if (!source[n.line - 1].includes(n.match)) err(nw, n.line + " 行に「" + n.match + "」が見つからない。実際の行: " + source[n.line - 1].trim());
        if (!CATEGORIES.includes(n.category)) err(nw, "category は " + CATEGORIES.join(" / ") + " のどれか");
        if (n.category === "language") checkKnown(nw, n.match);
        if (!n.text) err(nw, "text がない");
        checkSource(n, nw);
        if (n.category === "design" && !(Array.isArray(n.ruleIds) && n.ruleIds.length)) err(nw, "設計の解説には ruleIds（根拠の規則ID）が必要");
        for (const t of n.terms || []) {
          if (!glossaryIds.has(t)) err(nw, "用語集にない id を参照している: " + t);
          usedTerms.add(t);
        }
      });
      sNotes.sort((a, b) => a.line - b.line || a._order - b._order);
      const lines = [];
      for (let n = s.startLine; n <= s.endLine; n++) lines.push({ n, text: source[n - 1], added: added.has(n), cycle: cycleLines.has(n) });
      builtSections.push({
        name: s.name, startLine: s.startLine, endLine: s.endLine, summary: s.summary,
        changedInCycle: lines.some((l) => l.cycle),
        lines,
        notes: sNotes.map((n, i) => ({
          no: i + 1, line: n.line, match: n.match, category: n.category, text: n.text,
          terms: n.terms || [], source: n.source || null, unverified: n.unverified === true, ruleIds: n.ruleIds || [],
          cycle: cycleLines.has(n.line),
        })),
      });
    });
    const uncovered = required.filter((n) => !covered.has(n));
    if (uncovered.length) err(where, "どの節にも含まれない行がある: " + compressRanges(uncovered));
    builtFiles.push({
      path: f.path, status: info.status, summary: f.summary, scenes: f.scenes || [],
      changedInCycle: builtSections.some((s) => s.changedInCycle),
      sections: builtSections,
    });
  });
  glossary.forEach((g) => { if (glossaryIds.has(g.id) && !usedTerms.has(g.id)) warn("glossary(" + g.id + ")", "どの解説からも参照されていない"); });

  // 全体像
  const ov = notes.overview || {};
  const nodes = Array.isArray(ov.nodes) ? ov.nodes : [];
  const edges = Array.isArray(ov.edges) ? ov.edges : [];
  const readingOrder = Array.isArray(ov.readingOrder) ? ov.readingOrder : [];
  const nodeIds = new Set();
  nodes.forEach((n, i) => {
    const where = "overview.nodes[" + i + "]";
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(n.id || "")) err(where, "id は英字で始まる英数字にする");
    if (nodeIds.has(n.id)) err(where, "id が重複している: " + n.id);
    nodeIds.add(n.id);
    if (!n.label) err(where, "label がない");
  });
  if (!nodes.length) err("overview.nodes", "関係図のノードがない");
  edges.forEach((e, i) => {
    const where = "overview.edges[" + i + "]";
    if (!nodeIds.has(e.from) || !nodeIds.has(e.to)) err(where, "from / to が nodes にない: " + e.from + " → " + e.to);
    if (!EDGE_KINDS.includes(e.kind)) err(where, "kind は " + EDGE_KINDS.join(" / ") + " のどれか");
    if (!e.label) err(where, "label がない");
  });
  if (edges.length > 12) warn("overview.edges", "矢印が " + edges.length + " 本ある。12本までにまとめる（criteria/code-guide.md の5）");
  const pairs = new Set();
  edges.forEach((e, i) => {
    const key = e.from + "->" + e.to + ":" + e.kind;
    if (pairs.has(key)) warn("overview.edges[" + i + "]", "同じ2つの箱の間に同じ種類の矢印が既にある。1本にまとめる: " + e.from + " → " + e.to);
    pairs.add(key);
  });
  const orderPaths = readingOrder.map((r) => r.file);
  for (const p of changedPaths) if (!orderPaths.includes(p)) err("overview.readingOrder", "読む順にないファイル: " + p);
  orderPaths.forEach((p, i) => {
    if (!changedPaths.has(p)) err("overview.readingOrder[" + i + "]", "このPRで変更した .gd ではない: " + p);
    if (orderPaths.indexOf(p) !== i) err("overview.readingOrder[" + i + "]", "重複している: " + p);
    if (!readingOrder[i].role) err("overview.readingOrder[" + i + "]", "role がない");
  });

  // 解説が多すぎると、PRのレビューで読み切れない。変更した行（空行を除く）の3割を目安にする（criteria/code-guide.md の3）
  const noteTotal = builtFiles.reduce((a, f) => a + f.sections.reduce((b, s) => b + s.notes.length, 0), 0);
  const noteLimit = Math.ceil(requiredLineCount * NOTE_RATIO_LIMIT);
  if (noteTotal > noteLimit) warn("notes", "行の注釈が " + noteTotal + " 件ある。変更した " + requiredLineCount + " 行（空行を除く）の " + NOTE_RATIO_LIMIT * 100 + "% （" + noteLimit + " 件）までにまとめる");

  for (const w of warnings) console.log("警告 " + w);
  if (errors.length) {
    for (const e of errors) console.log("誤り " + e);
    console.log("検証の誤りが " + errors.length + " 件あるため、HTMLを書き出さなかった。");
    process.exit(1);
  }
  if (args.validateOnly) {
    console.log("検証に通った（誤り 0 件、警告 " + warnings.length + " 件）。HTMLは書き出していない。");
    process.exit(0);
  }

  // 読む順に並べ替え、用語集の使用箇所を集める
  builtFiles.sort((a, b) => orderPaths.indexOf(a.path) - orderPaths.indexOf(b.path));
  const builtGlossary = glossary.map((g) => ({
    id: g.id, term: g.term, category: g.category, text: g.text, source: g.source || null, unverified: g.unverified === true, uses: [],
  }));
  builtFiles.forEach((f, fi) => f.sections.forEach((s, si) => s.notes.forEach((n) => n.terms.forEach((t) => {
    builtGlossary.find((g) => g.id === t).uses.push({ file: f.path, line: n.line, fi, si, no: n.no });
  }))));

  const data = {
    meta: {
      issue: notes.issue, title: notes.title, pr: args.pr ? Number(args.pr) : null, branch,
      base: args.base, head, headShort: head.slice(0, 7), cycle: args.cycle,
      generatedAt: new Date().toLocaleString("ja-JP", { hour12: false }),
    },
    overview: { nodes, edges, readingOrder, mermaid: toMermaid(nodes, edges) },
    files: builtFiles,
    glossary: builtGlossary,
  };

  const here = dirname(fileURLToPath(import.meta.url));
  const template = readFileSync(join(here, "..", "templates", "code-guide.html"), "utf8");
  const marker = "/*__GUIDE_DATA__*/";
  if (!template.includes(marker)) {
    console.error("テンプレートに " + marker + " がない");
    process.exit(2);
  }
  const html = template.replace(marker, () => JSON.stringify(data).replace(/</g, "\\u003c"));
  const out = resolve(args.out);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, html, "utf8");

  const count = { language: 0, engine: 0, design: 0 };
  let unverified = 0;
  builtFiles.forEach((f) => f.sections.forEach((s) => s.notes.forEach((n) => { count[n.category]++; if (n.unverified) unverified++; })));
  unverified += builtGlossary.filter((g) => g.unverified).length;
  console.log("書き出した: " + out);
  console.log("ファイル " + builtFiles.length + " / 節 " + builtFiles.reduce((a, f) => a + f.sections.length, 0) +
    " / 解説 言語 " + count.language + "・エンジン " + count.engine + "・設計 " + count.design +
    " / 用語集 " + builtGlossary.length + " / 未確認 " + unverified + " / 警告 " + warnings.length);
}

function compressRanges(nums) {
  const out = [];
  let start = nums[0];
  let prev = nums[0];
  for (const n of nums.slice(1).concat([NaN])) {
    if (n === prev + 1) { prev = n; continue; }
    out.push(start === prev ? String(start) : start + "–" + prev);
    start = prev = n;
  }
  return out.join(", ") + " 行";
}

function toMermaid(nodes, edges) {
  const label = (s) => String(s).replace(/"/g, "#quot;").replace(/[<>]/g, "");
  const lines = ["flowchart TB"];
  for (const n of nodes) lines.push("  " + n.id + '["' + label(n.label) + (n.file ? "<br/><small>" + label(n.file.split("/").pop()) + "</small>" : "") + '"]');
  const arrow = { tree: "-.-", signal: "==>", call: "-->", instance: "-->", other: "-->" };
  for (const e of edges) lines.push("  " + e.from + " " + (arrow[e.kind] || "-->") + '|"' + label(e.label).replace(/`/g, "") + '"| ' + e.to);
  return lines.join("\n");
}

main();
