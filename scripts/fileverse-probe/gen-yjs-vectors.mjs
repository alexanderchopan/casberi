#!/usr/bin/env node
// Writes yjs-vectors.json: Yjs updates made by the real `yjs` library, each
// with the tree Yjs itself reads back, for `fileverse-selftest.sh` to hold the
// Swift decoder (`Model/Yjs.swift`) to. Committed, so the harness needs no npm.
//
// Each vector is a random edit history over the XmlFragment "default" — the
// shape y-prosemirror writes (elements with attributes, XmlText with formats)
// — made by three clients editing concurrently and syncing at random, with
// deletes, re-formats, attribute overwrites and astral characters (emoji, so a
// UTF-16 surrogate pair can straddle an edit). Half run with gc on, half off.
// A fixed seed: rerunning writes the same file.
//
//   node scripts/fileverse-probe/gen-yjs-vectors.mjs   (after npm ci there)

import * as Y from "yjs";
import { writeFileSync } from "node:fs";

let seed = 20261016;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (n) => Math.floor(rnd() * n);

const WORDS = ["plan", "ship", "read", "Fileverse", "naïve", "déjà", "日本語", "🙂", "👩‍💻", "a", " ", "\n", "x y"];
const NODES = ["paragraph", "heading", "dBlock", "bulletList", "listItem", "table", "tableRow", "tableCell", "blockquote"];
const MARKS = [["bold", true], ["italic", true], ["link", { href: "https://example.com/a" }], ["code", true], ["strike", true]];

// Yjs's own reading, in the shape the Swift side exports.
const readNode = (n) => {
  if (n instanceof Y.XmlText) {
    return { text: n.toDelta().map((op) => ({ insert: typeof op.insert === "string" ? op.insert : { embed: op.insert }, attributes: op.attributes ?? {} })) };
  }
  const attrs = n.getAttributes();
  const sorted = Object.fromEntries(Object.keys(attrs).sort().map((k) => [k, attrs[k]]));
  return { name: n.nodeName, attrs: sorted, children: n.toArray().map(readNode) };
};
const readDoc = (doc) => doc.getXmlFragment("default").toArray().map(readNode);

const allNodes = (frag) => {
  const out = [frag];
  const walk = (n) => n.toArray().forEach((c) => { out.push(c); if (!(c instanceof Y.XmlText)) walk(c); });
  walk(frag);
  return out;
};

const op = (doc) => {
  const frag = doc.getXmlFragment("default");
  const nodes = allNodes(frag);
  const containers = nodes.filter((n) => !(n instanceof Y.XmlText));
  const texts = nodes.filter((n) => n instanceof Y.XmlText);
  const r = rnd();
  if (r < 0.22 || texts.length === 0) {
    const parent = pick(containers);
    const at = int(parent.length + 1);
    if (rnd() < 0.5) {
      const el = new Y.XmlElement(pick(NODES));
      if (rnd() < 0.5) el.setAttribute("level", 1 + int(3));
      const t = new Y.XmlText();
      el.insert(0, [t]);
      parent.insert(at, [el]);
      t.insert(0, pick(WORDS) + pick(WORDS));
    } else {
      const t = new Y.XmlText();
      parent.insert(at, [t]);
      t.insert(0, pick(WORDS));
    }
  } else if (r < 0.55) {
    const t = pick(texts);
    const at = int(t.length + 1);
    const [k, v] = pick(MARKS);
    t.insert(at, pick(WORDS), rnd() < 0.4 ? { [k]: v } : undefined);
  } else if (r < 0.7) {
    const t = pick(texts);
    if (t.length > 0) { const at = int(t.length); t.delete(at, 1 + int(Math.min(4, t.length - at))); }
  } else if (r < 0.8) {
    const t = pick(texts);
    if (t.length > 0) { const at = int(t.length); const [k, v] = pick(MARKS); t.format(at, 1 + int(t.length - at), { [k]: rnd() < 0.25 ? null : v }); }
  } else if (r < 0.88) {
    const el = pick(containers.filter((c) => c instanceof Y.XmlElement));
    if (el) el.setAttribute(pick(["level", "checked", "src"]), pick([1, 2, true, false, "ipfs://x", null]));
  } else if (r < 0.95) {
    const parent = pick(containers);
    if (parent.length > 0) parent.delete(int(parent.length), 1);
  } else if (texts.length) {
    const t = pick(texts);
    t.insertEmbed(int(t.length + 1), { image: "ipfs://cid" });
  }
};

const vectors = [];
for (let v = 0; v < 160; v++) {
  const gc = v % 2 === 0;
  const docs = [0, 1, 2].map((i) => { const d = new Y.Doc({ gc }); d.clientID = 1000 + v * 3 + i * (i === 2 ? 7 : 1); return d; });
  const steps = 5 + int(v < 20 ? 10 : 60);
  for (let s = 0; s < steps; s++) {
    op(pick(docs));
    if (rnd() < 0.3) {
      const a = pick(docs), b = pick(docs);
      Y.applyUpdate(b, Y.encodeStateAsUpdate(a, Y.encodeStateVector(b)));
    }
  }
  for (const a of docs) for (const b of docs) Y.applyUpdate(b, Y.encodeStateAsUpdate(a, Y.encodeStateVector(b)));
  const update = Y.encodeStateAsUpdate(docs[0]);
  const fresh = new Y.Doc();
  Y.applyUpdate(fresh, update);
  vectors.push({ gc, update: Buffer.from(update).toString("base64"), tree: readDoc(fresh) });
}

writeFileSync(new URL("./yjs-vectors.json", import.meta.url), JSON.stringify({ yjs: "13.6.33", seed: 20261016, vectors }));
console.log(`wrote ${vectors.length} vectors · ${vectors.reduce((n, v) => n + Buffer.from(v.update, "base64").length, 0)} update bytes`);
