#!/usr/bin/env node
// Fileverse probe — can a client read your dDocs with the Developer Mode key
// alone, with no satellite standing? (prd §669 measured a minified bundle and
// never ran; this runs.)
//
// WHY A NODE SCRIPT, NOT A `-fileverseProbe` HOOK. The answer decides whether
// a Swift seat gets built. The read path needs secp256k1 ECDH with noble's
// seed-to-scalar map, AES-GCM on a 24-byte nonce, and a Yjs decoder — porting
// all three to Swift before knowing the path works is the cost this spike
// exists to avoid. Every step below calls a plain primitive (@noble/*, yjs),
// never `@fileverse/*`, so a green run is the Swift port's spec, step for step.
//
// WHAT THE SATELLITE DOES, read from @fileverse/api 1.0.10's own sources (the
// package ships them in its source maps):
//   1. GET apps-storage.fileverse.io/api-access/<sha256(key bytes)>
//      → { encryptedKeyMaterial, encryptedAppMaterial, id }
//   2. each is AES-GCM (nonce = first 24 bytes) under
//      HKDF-SHA256(key bytes, salt [0], "SAVED_DATA_ENCRYPTION_KEY")
//      → appMaterial { portalAddress, portalSeed, ownerAddress }
//   3. portalSeed (48 bytes) → secp256k1 secret by noble's mapHashToField
//   4. a file's metadata.appLock.lockedFileKey is ECIES to that key:
//      "<ephPub>__n__<nonce12>__n__<ct>__n__<mac>", AES-GCM under
//      HKDF-SHA256(compressed ECDH point, ephPub, "ECIES-AES256-GCM-SHA256")
//   5. the content blob is ciphertext ‖ tag(16) ‖ iv(12), AES-GCM under the
//      file key → { file: base64 Yjs update, source }, fragment "default"
//   6. the title is AES-GCM (24-byte nonce prefix) under the same file key
// The satellite NEVER reads a document it did not write: `GET /api/ddocs`
// answers from its own SQLite. Listing the portal's files off the chain and
// opening one written in the ddocs.new editor is the part nobody has run.
//
// USAGE (the key goes in on stdin, never argv, per the dev-keys rule):
//   npm ci --prefix scripts/fileverse-probe
//   scripts/dev-keys.sh get fileverse | node scripts/fileverse-probe/probe.mjs
//   node scripts/fileverse-probe/probe.mjs --self-test
// Flags: --limit <n> (files opened, default 5), --gateway <url ending /ipfs/>,
//        --rpc <url>, --show (print titles and the first 160 characters; the
//        default prints shapes and counts only, never a word you wrote).
//
// OUTPUT: one `fileverse| <step> | <outcome> | <detail>` line per step.

import { hkdf } from "@noble/hashes/hkdf.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { keccak_256 } from "@noble/hashes/sha3.js";
import { bytesToHex } from "@noble/hashes/utils.js";
import { gcm } from "@noble/ciphers/aes.js";
import { secp256k1 } from "@noble/curves/secp256k1.js";
import * as Y from "yjs";
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const STORAGE = "https://apps-storage.fileverse.io/";
const RPC = opt("--rpc", "https://rpc.gnosischain.com");
const BLOCKSCOUT = "https://gnosis.blockscout.com/api";
// No gateway is named in the satellite (it only uploads). Each is asked in
// turn on the first fetch and the first to answer is kept.
const GATEWAYS = opt("--gateway", null)
  ? [opt("--gateway")]
  : [
      "https://apps-storage.fileverse.io/ipfs/",
      "https://ipfs.io/ipfs/",
      "https://dweb.link/ipfs/",
      "https://w3s.link/ipfs/",
      "https://gateway.pinata.cloud/ipfs/",
    ];
const LIMIT = Number(opt("--limit", "5"));
const SHOW = flag("--show");

const enc = new TextEncoder();
const dec = new TextDecoder();
const b64 = (s) => new Uint8Array(Buffer.from(s, "base64")); // accepts url-safe too
const log = (step, outcome, detail = "") =>
  console.log(`fileverse| ${step} | ${outcome}${detail === "" ? "" : ` | ${detail}`}`);
const short = (hex) => `${hex.slice(0, 6)}…${hex.slice(-4)}`;

// ---- primitives, each one a step the Swift port mirrors ---------------------

const savedDataKey = (apiKeyBytes) =>
  hkdf(sha256, apiKeyBytes, new Uint8Array([0]), enc.encode("SAVED_DATA_ENCRYPTION_KEY"), 32);

// WebCrypto's AES-GCM as @fileverse/crypto calls it: nonce (24) ‖ ct ‖ tag.
const aesOpen24 = (key, bytes) => gcm(key, bytes.slice(0, 24)).decrypt(bytes.slice(24));

const portalSecret = (portalSeed) => secp256k1.utils.randomSecretKey(portalSeed);

const SEPARATOR = "__n__";
const eciesOpen = (secret, sealed) => {
  const parts = sealed.split(SEPARATOR);
  if (parts.length !== 4) throw new Error(`ECIES string has ${parts.length} parts, want 4`);
  const [eph, nonce, ct, mac] = parts.map(b64);
  const shared = secp256k1.getSharedSecret(secret, eph); // 33 bytes, compressed
  const key = hkdf(sha256, shared, eph, enc.encode("ECIES-AES256-GCM-SHA256"), 32);
  const body = new Uint8Array(ct.length + mac.length);
  body.set(ct, 0);
  body.set(mac, ct.length);
  return gcm(key, nonce).decrypt(body);
};

// The content file: ciphertext ‖ tag (16) ‖ iv (12).
const contentOpen = (key, blob) => {
  const iv = blob.slice(-12);
  const body = blob.slice(0, -12); // ciphertext ‖ tag, noble's order
  return gcm(key, iv).decrypt(body);
};

// One line per leaf block of the Tiptap tree (heading, paragraph, …).
const yjsLines = (updateBytes) => {
  const doc = new Y.Doc();
  Y.applyUpdate(doc, updateBytes);
  const lines = [];
  const kinds = new Map();
  const walk = (node) => {
    let text = "";
    let leaf = false;
    for (const child of node.toArray()) {
      if (child instanceof Y.XmlText) {
        leaf = true;
        text += child.toDelta().map((op) => (typeof op.insert === "string" ? op.insert : "")).join("");
      } else {
        kinds.set(child.nodeName, (kinds.get(child.nodeName) ?? 0) + 1);
        walk(child);
      }
    }
    if (leaf) lines.push(text);
  };
  walk(doc.getXmlFragment("default"));
  doc.destroy();
  return { lines, kinds };
};

// ---- self-test: Fileverse's own ciphertexts through the primitives above ----

const selfTest = () => {
  const v = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
  let failed = 0;
  const check = (name, ok) => {
    console.log(`selftest| ${name} | ${ok ? "pass" : "FAIL"}`);
    if (!ok) failed++;
  };
  const throws = (fn) => {
    try {
      fn();
      return false;
    } catch {
      return true;
    }
  };
  const flip = (bytes, at) => {
    const out = bytes.slice();
    out[at] ^= 1;
    return out;
  };

  const apiKey = b64(v.apiKey);
  const saved = b64(v.encryptedAppMaterial);
  const app = JSON.parse(dec.decode(aesOpen24(savedDataKey(apiKey), saved)));
  check("saved data opens, portalSeed matches", app.portalSeed === v.portalSeed);

  const secret = portalSecret(b64(app.portalSeed));
  const fileKey = eciesOpen(secret, v.metadata.appLock.lockedFileKey);
  check("ECIES file key is 32 bytes", fileKey.length === 32);

  const title = dec.decode(aesOpen24(fileKey, b64(v.metadata.title)));
  check("title opens", title === v.expect.title);

  const content = JSON.parse(dec.decode(contentOpen(fileKey, b64(v.content))));
  check("content is { file, source: ddoc }", typeof content.file === "string" && content.source === "ddoc");
  const { lines } = yjsLines(b64(content.file));
  check("Yjs lines match", JSON.stringify(lines) === JSON.stringify(v.expect.lines));

  // Mutations: each must make the read fail, or the passes above prove nothing.
  check("mutant: wrong HKDF info is refused", throws(() =>
    aesOpen24(hkdf(sha256, apiKey, new Uint8Array([0]), enc.encode("SAVED_DATA_KEY"), 32), saved)));
  check("mutant: 12-byte nonce on saved data is refused", throws(() =>
    gcm(savedDataKey(apiKey), saved.slice(0, 12)).decrypt(saved.slice(12))));
  check("mutant: a flipped saved-data byte is refused", throws(() =>
    aesOpen24(savedDataKey(apiKey), flip(saved, 40))));
  check("mutant: raw seed as the secret is refused", throws(() =>
    eciesOpen(b64(app.portalSeed).slice(0, 32), v.metadata.appLock.lockedFileKey)));
  check("mutant: x-only shared secret is refused", throws(() => {
    const [eph, nonce, ct, mac] = v.metadata.appLock.lockedFileKey.split(SEPARATOR).map(b64);
    const x = secp256k1.getSharedSecret(secret, eph).slice(1);
    const key = hkdf(sha256, x, eph, enc.encode("ECIES-AES256-GCM-SHA256"), 32);
    const body = new Uint8Array([...ct, ...mac]);
    gcm(key, nonce).decrypt(body);
  }));
  check("mutant: iv read from the front of the content is refused", throws(() => {
    const blob = b64(v.content);
    gcm(fileKey, blob.slice(0, 12)).decrypt(blob.slice(12));
  }));
  check("mutant: a flipped content byte is refused", throws(() => contentOpen(fileKey, flip(b64(v.content), 7))));

  console.log(`selftest| ${failed === 0 ? "ok" : `${failed} FAILED`}`);
  process.exit(failed === 0 ? 0 : 1);
};

// ---- the live read ---------------------------------------------------------

const readStdin = async () => {
  if (process.stdin.isTTY) {
    console.error("Pipe the key in: scripts/dev-keys.sh get fileverse | node scripts/fileverse-probe/probe.mjs");
    process.exit(2);
  }
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString("utf8").trim();
};

const getJSON = async (url, init) => {
  let res;
  try {
    res = await fetch(url, { ...init, signal: AbortSignal.timeout(20000) });
  } catch (e) {
    throw new Error(`${new URL(url).host}: ${e.cause?.code ?? e.name}`);
  }
  const text = await res.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {}
  return { status: res.status, body, text };
};

const rpc = async (method, params) => {
  const { status, body } = await getJSON(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  if (body?.error) throw new Error(`${body.error.code} ${body.error.message}`);
  if (status !== 200 || body?.result === undefined) throw new Error(`HTTP ${status}`);
  return body.result;
};

const topic = (sig) => "0x" + bytesToHex(keccak_256(enc.encode(sig)));
const EVENTS = {
  [topic("AddedFile(uint256,string,uint8,string,string,string,uint256,address)")]: "added",
  [topic("EditedFile(uint256,string,uint8,string,string,string,uint256,address)")]: "edited",
  [topic("DeletedFile(uint256,string,address)")]: "deleted",
};

// ABI head/tail decode for the events' non-indexed fields.
const decodeData = (hex, types) => {
  const data = Buffer.from(hex.slice(2), "hex");
  const word = (i) => BigInt("0x" + data.subarray(i * 32, i * 32 + 32).toString("hex"));
  return types.map((type, i) => {
    if (type !== "string") return word(i);
    const at = Number(word(i));
    const len = Number(BigInt("0x" + data.subarray(at, at + 32).toString("hex")));
    return data.subarray(at + 32, at + 32 + len).toString("utf8");
  });
};
const FILE_FIELDS = ["string", "uint8", "string", "string", "string", "uint256"];

const portalLogs = async (portal) => {
  const topics = [Object.keys(EVENTS)];
  try {
    const logs = await rpc("eth_getLogs", [{ address: portal, fromBlock: "0x0", toBlock: "latest", topics }]);
    log("logs", "ok", `rpc full range · ${logs.length} logs`);
    return logs;
  } catch (e) {
    log("logs", "rpc refused", e.message.slice(0, 120));
  }
  const all = [];
  for (const t0 of Object.keys(EVENTS)) {
    for (let page = 1; page < 50; page++) {
      const url = `${BLOCKSCOUT}?module=logs&action=getLogs&address=${portal}&fromBlock=0&toBlock=latest&topic0=${t0}&page=${page}&offset=1000`;
      const { status, body } = await getJSON(url);
      if (status !== 200 || !Array.isArray(body?.result)) {
        if (body?.message === "No records found") break;
        throw new Error(`blockscout HTTP ${status} ${body?.message ?? ""}`);
      }
      all.push(...body.result);
      if (body.result.length < 1000) break;
    }
  }
  log("logs", "ok", `blockscout · ${all.length} logs`);
  return all;
};

let gateway = null;
const ipfs = async (cid) => {
  const order = gateway ? [gateway] : GATEWAYS;
  for (const g of order) {
    try {
      const res = await fetch(g + cid, { signal: AbortSignal.timeout(30000) });
      if (!gateway) log("gateway", res.ok ? "ok" : `HTTP ${res.status}`, g);
      if (!res.ok) continue;
      gateway = g;
      return new Uint8Array(await res.arrayBuffer());
    } catch (e) {
      if (!gateway) log("gateway", "no answer", `${g} · ${e.name}`);
    }
  }
  throw new Error("no gateway served the CID");
};

const live = async () => {
  const keyText = await readStdin();
  if (!keyText) {
    log("key", "empty");
    process.exit(2);
  }
  const apiKey = b64(keyText);
  log("key", "read", `${apiKey.length} bytes after base64`);

  // 1 · the key's saved material
  const hash = "0x" + bytesToHex(sha256(apiKey));
  const access = await getJSON(`${STORAGE}api-access/${hash}`);
  if (access.status !== 200 || !access.body) {
    log("api-access", `HTTP ${access.status}`, access.text.slice(0, 160));
    process.exit(1);
  }
  log("api-access", "200", `fields: ${Object.keys(access.body).sort().join(", ")}`);

  // 2 · open it
  const savedKey = savedDataKey(apiKey);
  let keyMaterial, appMaterial;
  try {
    keyMaterial = JSON.parse(dec.decode(aesOpen24(savedKey, b64(access.body.encryptedKeyMaterial))));
    appMaterial = JSON.parse(dec.decode(aesOpen24(savedKey, b64(access.body.encryptedAppMaterial))));
  } catch (e) {
    log("saved-data", "FAILED", e.message);
    process.exit(1);
  }
  log("saved-data", "opened", `key fields: ${Object.keys(keyMaterial).sort().join(", ")} · app fields: ${Object.keys(appMaterial).sort().join(", ")}`);
  log("saved-data", "apiKeySeed is the pasted key", String(keyMaterial.apiKeySeed === keyText));

  // 3 · the portal's key
  const portal = appMaterial.portalAddress;
  const seed = b64(appMaterial.portalSeed);
  log("portal", "address", short(portal));
  log("portal", "seed", `${seed.length} bytes`);
  const secret = portalSecret(seed);

  // 4 · the portal's files, off the chain
  const logs = await portalLogs(portal);
  const files = new Map();
  const counts = { added: 0, edited: 0, deleted: 0 };
  // Blockscout's etherscan-style API spells a zero index "0x".
  const n = (hex) => BigInt(hex && hex !== "0x" ? hex : 0);
  logs.sort((a, b) => Number(n(a.blockNumber) - n(b.blockNumber)) || Number(n(a.logIndex) - n(b.logIndex)));
  for (const l of logs) {
    const kind = EVENTS[l.topics[0]];
    if (!kind) continue;
    counts[kind]++;
    const fileId = BigInt(l.topics[1]).toString();
    if (kind === "deleted") {
      files.delete(fileId);
      continue;
    }
    const [appFileId, fileType, metadataCID, contentCID, gateCID, version] = decodeData(l.data, FILE_FIELDS);
    files.set(fileId, { fileId, appFileId, fileType: Number(fileType), metadataCID, contentCID, gateCID, version: Number(version), by: "0x" + l.topics[2].slice(26) });
  }
  const tally = (key) => [...files.values()].reduce((m, f) => m.set(f[key], (m.get(f[key]) ?? 0) + 1), new Map());
  log("files", "listed", `${files.size} live · added ${counts.added} · edited ${counts.edited} · deleted ${counts.deleted}`);
  log("files", "fileType", [...tally("fileType")].map(([k, n]) => `${k}×${n}`).join(" "));
  log("files", "version", [...tally("version")].map(([k, n]) => `${k}×${n}`).join(" "));
  log("files", "writers", `${tally("by").size} addresses`);

  // 5 · open the newest few
  const newest = [...files.values()].sort((a, b) => Number(b.fileId) - Number(a.fileId)).slice(0, LIMIT);
  const outcome = { opened: 0, failed: 0 };
  for (const f of newest) {
    const tag = `file ${f.fileId}`;
    try {
      const meta = JSON.parse(dec.decode(await ipfs(f.metadataCID)));
      log(tag, "metadata", `fields: ${Object.keys(meta).sort().join(", ")} · version ${meta.version ?? "?"} · sourceApp ${meta.sourceApp ?? "?"}`);

      let fileKey = null;
      for (const lock of ["appLock", "ownerLock"]) {
        const sealed = meta[lock]?.lockedFileKey;
        if (!sealed) {
          log(tag, lock, "absent");
          continue;
        }
        try {
          fileKey = eciesOpen(secret, sealed);
          log(tag, lock, `opened · ${fileKey.length}-byte key`);
          break;
        } catch (e) {
          log(tag, lock, `refused · ${e.message.slice(0, 80)}`);
        }
      }
      if (!fileKey) throw new Error("no lock opened");

      let title = null;
      try {
        title = dec.decode(aesOpen24(fileKey, b64(meta.title)));
        log(tag, "title", `opened · ${title.length} chars`);
      } catch (e) {
        log(tag, "title", `refused · ${e.message.slice(0, 80)}`);
      }

      const blob = await ipfs(f.contentCID);
      const plain = contentOpen(fileKey, blob);
      const content = JSON.parse(dec.decode(plain));
      log(tag, "content", `opened · ${blob.length} bytes · fields: ${Object.keys(content).sort().join(", ")} · file is ${typeof content.file} · source ${content.source ?? "?"}`);

      if (typeof content.file !== "string") throw new Error("content.file is not a Yjs string");
      const { lines, kinds } = yjsLines(b64(content.file));
      const chars = lines.reduce((n, s) => n + s.length, 0);
      log(tag, "yjs", `${lines.length} blocks · ${chars} chars · nodes: ${[...kinds].map(([k, n]) => `${k}×${n}`).join(" ")}`);
      if (SHOW) {
        console.log(`  title: ${title ?? "(none)"}`);
        console.log(`  text:  ${lines.join(" / ").slice(0, 160)}`);
      }
      outcome.opened++;
    } catch (e) {
      log(tag, "FAILED", e.message.slice(0, 160));
      outcome.failed++;
    }
  }
  log("verdict", outcome.opened > 0 && outcome.failed === 0 ? "READ WORKS" : outcome.opened > 0 ? "PARTIAL" : "READ FAILED", `${outcome.opened} opened · ${outcome.failed} failed of ${newest.length}`);
  process.exit(outcome.failed === 0 && outcome.opened > 0 ? 0 : 1);
};

if (flag("--self-test")) selfTest();
else live().catch((e) => {
  log("error", e.name, e.message.slice(0, 200));
  process.exit(1);
});
