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
//   node scripts/fileverse-probe/probe.mjs --backup <ddocs backup-keys .json>
//     (a legacy account's portals, which no Developer Mode key covers: the
//     file's secp256k1 app key and RSA keys are tried on every lock; the file
//     is read from disk and no value it holds is ever printed)
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
import { createPrivateKey, privateDecrypt, publicEncrypt, generateKeyPairSync, randomBytes, constants as cryptoConstants } from "node:crypto";

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
// Recovery (prd §1346): keep files the log deleted, and write each opened
// doc to --out <dir> as text plus its decrypted Yjs update. Local only.
const INCLUDE_DELETED = flag("--include-deleted");
const OUT = opt("--out", null);

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

  // The legacy RSA lock. No legacy vector exists (nobody has run one), so
  // this one is built here to @fileverse/crypto 0.0.21's webcrypto/core.js:
  // base64(nonce 24 ‖ RSA-OAEP-SHA256), and its envelope's AES half is aes24.
  const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const der = new Uint8Array(rsa.privateKey.export({ format: "der", type: "pkcs8" }));
  const rsaSeal = (bytes, hash = "sha256") =>
    Buffer.from([...randomBytes(24), ...publicEncrypt({ key: rsa.publicKey, padding: cryptoConstants.RSA_PKCS1_OAEP_PADDING, oaepHash: hash }, bytes)]).toString("base64");
  const aesKey = randomBytes(32);
  const nonce = randomBytes(24);
  const aesHalf = Buffer.from([...nonce, ...gcm(aesKey, nonce).encrypt(fileKey)]).toString("base64");
  const opener = rsaOpener("rsa test", der);
  const same = (a, b) => a && b && Buffer.from(a).equals(Buffer.from(b));
  check("legacy: RSA envelope opens to the file key", same(asFileKey(opener.open(rsaSeal(aesKey) + SEPARATOR + aesHalf)).key, fileKey));
  check("legacy: a bare RSA lock opens", same(asFileKey(opener.open(rsaSeal(fileKey))).key, fileKey));
  check("legacy: a base64-string file key is read as the key", same(asFileKey(enc.encode(Buffer.from(fileKey).toString("base64"))).key, fileKey));
  check("legacy: the ECIES opener passes an RSA lock by", secpOpener("t", fileKey).open(rsaSeal(fileKey)) === null);
  check("mutant: RSA-OAEP with SHA-1 is refused", throws(() => opener.open(rsaSeal(fileKey, "sha1"))));
  check("mutant: an RSA lock read with its nonce left on is refused", throws(() =>
    privateDecrypt({ key: createPrivateKey({ key: Buffer.from(der), format: "der", type: "pkcs8" }), padding: cryptoConstants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" }, b64(rsaSeal(fileKey)))));

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
// Two portal generations log files. The ddocs.new-era portal names the app's
// file id, type and version; the legacy portal (`@fileverse/agents`'
// abi/Portal.json, the RSA-key accounts) logs the three CIDs and nothing else.
const EVENTS = {
  [topic("AddedFile(uint256,string,uint8,string,string,string,uint256,address)")]: { kind: "added", layout: "ddocs" },
  [topic("EditedFile(uint256,string,uint8,string,string,string,uint256,address)")]: { kind: "edited", layout: "ddocs" },
  [topic("DeletedFile(uint256,string,address)")]: { kind: "deleted", layout: "ddocs" },
  [topic("AddedFile(uint256,string,string,string,address)")]: { kind: "added", layout: "legacy" },
  [topic("EditedFile(uint256,string,string,string,address)")]: { kind: "edited", layout: "legacy" },
};

// The legacy ABI's other events, named so a portal holding only setup reads
// as setup, not as an unknown layout.
const NAMES = Object.fromEntries(
  ["AddedCollaborator(address,address)", "OwnershipTransferStarted(address,address)", "OwnershipTransferred(address,address)",
   "RegisteredCollaboratorKeys(address)", "RemovedCollaborator(address,address)", "RemovedCollaboratorKeys(address)",
   "UpdatedKeyVerifiers(bytes32,bytes32,bytes32,bytes32)", "UpdatedPortalMetadata(string,address)"].map((sig) => [topic(sig), sig.split("(")[0]]));

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
const FILE_FIELDS = {
  ddocs: ["string", "uint8", "string", "string", "string", "uint256"],
  legacy: ["string", "string", "string"],
};
const fileFields = (layout, data) => {
  if (layout === "legacy") {
    const [metadataCID, contentCID, gateCID] = decodeData(data, FILE_FIELDS.legacy);
    return { appFileId: null, fileType: null, metadataCID, contentCID, gateCID, version: null };
  }
  const [appFileId, fileType, metadataCID, contentCID, gateCID, version] = decodeData(data, FILE_FIELDS.ddocs);
  return { appFileId, fileType: Number(fileType), metadataCID, contentCID, gateCID, version: Number(version) };
};

// Every log the portal ever wrote, unfiltered, so an event layout nobody
// expected shows up as a topic count instead of as an empty portal.
const portalLogs = async (portal) => {
  let logs = null;
  try {
    logs = await rpc("eth_getLogs", [{ address: portal, fromBlock: "0x0", toBlock: "latest" }]);
    log("logs", "ok", `rpc full range · ${logs.length} logs`);
  } catch (e) {
    log("logs", "rpc refused", e.message.slice(0, 120));
  }
  if (!logs?.length) {
    // A public RPC may answer [] for a range it will not scan, so an empty
    // answer is asked again of Blockscout before it counts as a finding.
    const all = [];
    for (let page = 1; page < 50; page++) {
      const { status, body } = await getJSON(`${BLOCKSCOUT}?module=logs&action=getLogs&address=${portal}&fromBlock=0&toBlock=latest&page=${page}&offset=1000`);
      if (status !== 200 || !Array.isArray(body?.result)) {
        if (!/no (records|logs)/i.test(body?.message ?? "")) log("logs", "blockscout refused", `HTTP ${status} ${body?.message ?? ""}`);
        break;
      }
      all.push(...body.result);
      if (body.result.length < 1000) break;
    }
    log("logs", "blockscout", `${all.length} logs`);
    if (all.length) logs = all;
    else {
      const code = await rpc("eth_getCode", [portal, "latest"]).catch((e) => `err ${e.message}`);
      log("logs", "portal code", typeof code === "string" && code.startsWith("0x") ? `${(code.length - 2) / 2} bytes` : code);
      const counters = await getJSON(`https://gnosis.blockscout.com/api/v2/addresses/${portal}/counters`);
      log("logs", "blockscout counters", counters.status === 200 ? `txs ${counters.body?.transactions_count} · transfers ${counters.body?.token_transfers_count}` : `HTTP ${counters.status}`);
    }
  }
  logs ??= [];
  const kinds = new Map();
  for (const l of logs) {
    const e = EVENTS[l.topics[0]];
    const name = e ? `${e.kind}/${e.layout}` : NAMES[l.topics[0]] ?? `unknown ${l.topics[0]?.slice(0, 10)}`;
    kinds.set(name, (kinds.get(name) ?? 0) + 1);
  }
  log("logs", "events", [...kinds].map(([k, c]) => `${k}×${c}`).join(", ") || "none");
  return logs;
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

  // 4 · the portal's files, off the chain, and 5 · open the newest few
  verdict(await openPortal(portal, [secpOpener("portal seed", secret)]));
};

// ---- openers: one per key that might open a lock ---------------------------

// ddocs.new-era lock: ECIES to a secp256k1 scalar, four parts.
const secpOpener = (name, secret) => ({
  name,
  open: (s) => (s.split(SEPARATOR).length === 4 ? eciesOpen(secret, s) : null),
});

// Legacy lock, @fileverse/crypto's webcrypto/core.js rsaDecrypt: base64 of
// nonce (24, which RSA-OAEP ignores) ‖ RSA-OAEP-SHA256 ciphertext. Its
// envelope (webcrypto/envelope.js) is "<rsa(aesKey)>__n__<aes24(message)>".
const rsaOpen = (key, bytes) =>
  new Uint8Array(privateDecrypt({ key, padding: cryptoConstants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" }, bytes.slice(24)));
const rsaOpener = (name, der) => {
  const key = createPrivateKey({ key: Buffer.from(der), format: "der", type: "pkcs8" });
  return {
    name,
    open: (s) => {
      const parts = s.split(SEPARATOR);
      if (parts.length === 2) return aesOpen24(rsaOpen(key, b64(parts[0])), b64(parts[1]));
      if (parts.length === 1) return rsaOpen(key, b64(s));
      return null;
    },
  };
};

// A lock may seal the raw 32 key bytes or a base64 string of them.
const asFileKey = (bytes) => {
  if (bytes.length === 32) return { key: bytes, as: "raw" };
  const s = dec.decode(bytes).trim();
  if (/^[A-Za-z0-9+/=_-]+$/.test(s) && b64(s).length === 32) return { key: b64(s), as: "base64" };
  return { key: null, as: `${bytes.length} bytes, not a key` };
};

// Every string under a metadata field named like a lock or a key.
const lockStrings = (meta) => {
  const out = [];
  for (const [k, v] of Object.entries(meta)) {
    if (!/lock|key/i.test(k)) continue;
    if (typeof v === "string") out.push([k, v]);
    else if (v && typeof v === "object")
      for (const [f, s] of Object.entries(v)) if (typeof s === "string" && s.length > 40) out.push([`${k}.${f}`, s]);
  }
  return out;
};

const openContent = (fileKey, blob) => {
  for (const [how, fn] of [["tail iv", contentOpen], ["front nonce", aesOpen24]]) {
    try {
      return { how, plain: fn(fileKey, blob) };
    } catch {}
  }
  try {
    return { how: "base64 · front nonce", plain: aesOpen24(fileKey, b64(dec.decode(blob))) };
  } catch {}
  throw new Error("no content layout opened");
};

// What the opened bytes are: the ddocs JSON around a Yjs update, a bare Yjs
// update, other JSON, or text.
const readBody = (plain) => {
  const text = dec.decode(plain);
  try {
    const j = JSON.parse(text);
    if (typeof j.file === "string") return { shape: `json {${Object.keys(j).sort().join(", ")}} · source ${j.source ?? "?"}`, yjs: b64(j.file) };
    return { shape: `json {${Object.keys(j).sort().join(", ")}}`, text: null };
  } catch {}
  try {
    if (yjsLines(plain).lines.length) return { shape: "bare yjs", yjs: plain };
  } catch {}
  return { shape: "text", text };
};

// ---- one portal: list its files off the chain, open the newest few ----------

const openPortal = async (portal, openers) => {
  const logs = await portalLogs(portal);
  const files = new Map();
  const counts = { added: 0, edited: 0, deleted: 0 };
  // Blockscout's etherscan-style API spells a zero index "0x".
  const n = (hex) => BigInt(hex && hex !== "0x" ? hex : 0);
  logs.sort((a, b) => Number(n(a.blockNumber) - n(b.blockNumber)) || Number(n(a.logIndex) - n(b.logIndex)));
  for (const l of logs) {
    const e = EVENTS[l.topics[0]];
    if (!e) continue;
    counts[e.kind]++;
    const fileId = BigInt(l.topics[1]).toString();
    if (e.kind === "deleted") {
      if (INCLUDE_DELETED) { if (files.has(fileId)) files.get(fileId).deleted = true; } else files.delete(fileId);
      continue;
    }
    const by = "0x" + l.topics[2].slice(26);
    files.set(fileId, { fileId, layout: e.layout, ...fileFields(e.layout, l.data), by });
  }
  const tally = (key) => [...files.values()].reduce((m, f) => m.set(f[key], (m.get(f[key]) ?? 0) + 1), new Map());
  log("files", "listed", `${files.size} live · added ${counts.added} · edited ${counts.edited} · deleted ${counts.deleted}`);
  log("files", "layout", [...tally("layout")].map(([k, c]) => `${k}×${c}`).join(" "));
  log("files", "fileType", [...tally("fileType")].map(([k, c]) => `${k}×${c}`).join(" "));
  log("files", "writers", `${tally("by").size} addresses`);

  const newest = [...files.values()].sort((a, b) => Number(b.fileId) - Number(a.fileId)).slice(0, LIMIT);
  const outcome = { opened: 0, failed: 0, total: newest.length };
  for (const f of newest) {
    const tag = `file ${f.fileId}`;
    try {
      log(tag, "cids", `metadata ${f.metadataCID ? "yes" : "empty"} · content ${f.contentCID ? "yes" : "empty"} · gate ${f.gateCID ? "yes" : "empty"}`);
      if (!f.metadataCID) throw new Error("no metadata CID (deleted in place?)");
      const meta = JSON.parse(dec.decode(await ipfs(f.metadataCID)));
      log(tag, "metadata", `fields: ${Object.keys(meta).sort().join(", ")} · version ${meta.version ?? "?"} · sourceApp ${meta.sourceApp ?? "?"}`);

      const sealed = lockStrings(meta);
      log(tag, "locks", sealed.map(([p, s]) => `${p} (${s.split(SEPARATOR).length} parts, ${s.length} chars)`).join(", ") || "none");
      let fileKey = null;
      for (const [path, s] of sealed) {
        for (const o of openers) {
          try {
            const bytes = o.open(s);
            if (!bytes) continue;
            const k = asFileKey(bytes);
            log(tag, "lock", `${path} opened by ${o.name} · ${k.as}`);
            if (k.key) {
              fileKey = k.key;
              break;
            }
          } catch (e) {
            log(tag, "lock", `${path} refused by ${o.name} · ${e.message.slice(0, 60)}`);
          }
        }
        if (fileKey) break;
      }
      if (sealed.length && !fileKey) throw new Error("no lock opened");

      let title = null;
      const rawTitle = meta.title ?? meta.name;
      if (typeof rawTitle === "string" && fileKey) {
        try {
          title = dec.decode(aesOpen24(fileKey, b64(rawTitle)));
          log(tag, "title", `opened · ${title.length} chars`);
        } catch {
          title = rawTitle;
          log(tag, "title", `not sealed · ${rawTitle.length} chars`);
        }
      } else log(tag, "title", typeof rawTitle === "string" ? `plain · ${rawTitle.length} chars` : "absent");
      title ??= rawTitle ?? null;

      if (!f.contentCID) throw new Error("no content CID");
      const blob = await ipfs(f.contentCID);
      let plain = blob;
      if (fileKey) {
        const c = openContent(fileKey, blob);
        plain = c.plain;
        log(tag, "content", `opened · ${blob.length} bytes · ${c.how}`);
      } else log(tag, "content", `public · ${blob.length} bytes`);
      const body = readBody(plain);
      let lines = body.text != null ? body.text.split("\n").filter(Boolean) : [];
      if (body.yjs) {
        const y = yjsLines(body.yjs);
        lines = y.lines;
        log(tag, "body", `${body.shape} · ${lines.length} blocks · nodes: ${[...y.kinds].map(([k, c]) => `${k}×${c}`).join(" ")}`);
      } else log(tag, "body", `${body.shape} · ${lines.length} lines`);
      log(tag, "chars", String(lines.reduce((m, s) => m + s.length, 0)));
      if (OUT) {
        const { mkdirSync, writeFileSync } = await import("node:fs");
        mkdirSync(OUT, { recursive: true });
        const name = `${f.fileId}-${(title ?? "untitled").replace(/[^\w .-]+/g, "_").slice(0, 60)}`;
        writeFileSync(`${OUT}/${name}.txt`, `${title ?? ""}\n\n${lines.join("\n\n")}\n`);
        if (body.yjs) writeFileSync(`${OUT}/${name}.yjs`, body.yjs);
        writeFileSync(`${OUT}/${name}.content.json`, dec.decode(plain));
        log(tag, "written", `${OUT}/${name}.txt${f.deleted ? " (deleted on chain)" : ""}`);
      }
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
  return outcome;
};

const verdict = (o) => {
  log("verdict", o.opened > 0 && o.failed === 0 ? "READ WORKS" : o.opened > 0 ? "PARTIAL" : "READ FAILED", `${o.opened} opened · ${o.failed} failed of ${o.total}`);
  process.exit(o.failed === 0 && o.opened > 0 ? 0 : 1);
};

// ---- --backup: the keys ddocs.new exports, for a portal no API key covers ---
// Prints which keys each entry carries and what they open, never a value.
const backup = async (path) => {
  const data = JSON.parse(readFileSync(path, "utf8"));
  const total = { opened: 0, failed: 0, total: 0 };
  let i = 0;
  for (const [id, entry] of Object.entries(data)) {
    const tag = `backup ${++i}`;
    const portal = entry?.portalAddress;
    if (!portal) {
      log(tag, "skipped", "no portalAddress");
      continue;
    }
    const openers = [];
    if (entry.appDecryptionKey) {
      const secret = b64(entry.appDecryptionKey);
      const matches = entry.appEncryptionKey
        ? bytesToHex(secp256k1.getPublicKey(secret, true)) === bytesToHex(b64(entry.appEncryptionKey))
        : "no public key";
      log(tag, "app key", `${secret.length} bytes · public key matches ${matches}`);
      openers.push(secpOpener("app key", secret));
    }
    for (const [k, v] of Object.entries(entry)) {
      if (!/PrivateKey$/.test(k) || typeof v !== "string") continue;
      try {
        openers.push(rsaOpener(`rsa ${k.replace("PrivateKey", "")}`, b64(v)));
      } catch (e) {
        log(tag, k, `not an RSA PKCS#8 key · ${e.message.slice(0, 60)}`);
      }
    }
    log(tag, "portal", `${short(portal)} · entry id is the portal ${id.toLowerCase() === portal.toLowerCase()} · source ${entry.source ?? "?"} · openers: ${openers.map((o) => o.name).join(", ") || "none"}`);
    const o = await openPortal(portal, openers);
    log(tag, "result", `${o.opened} opened · ${o.failed} failed of ${o.total}`);
    for (const k of Object.keys(total)) total[k] += o[k];
  }
  verdict(total);
};

if (flag("--self-test")) selfTest();
else (opt("--backup", null) ? backup(opt("--backup")) : live()).catch((e) => {
  log("error", e.name, e.message.slice(0, 200));
  process.exit(1);
});
