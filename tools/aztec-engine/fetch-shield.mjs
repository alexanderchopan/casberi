// Fetches Shield's Aztec contract interfaces (prd §1700d) from Shield's own
// web app — the only place they are published — and PINS them: each
// interface's contract class, computed here, must equal the class Aztec
// mainnet runs at Shield's addresses (measured 2026-11-04), or nothing is
// written. Output goes to shield/ (not committed: Shield's compiled code is
// theirs to publish, and it changes when they redeploy).
//
//   node fetch-shield.mjs           fetch what is missing
//   node fetch-shield.mjs --force   fetch again
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadContractArtifact } from '@aztec-labs/aztec.js/abi';
import { getContractClassFromArtifact } from '@aztec-labs/stdlib/contract';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, 'shield');
const ORIGIN = 'https://shield.human.tech';
// Webpack module ids in Shield's bundle, and the class each must compute to.
export const PINS = {
  bridge: { module: '40417', class: '0x28fe903cd306bbc46fd908cc03989601c32368c4694b508499f18516062fefd3' },
  token: { module: '52811', class: '0x2ff0939914ff64bd3f7979926dbe8cf3332bc2fee55928bf3cc9ca802568ea9f' },
  proxy: { module: '68897', class: '0x18fa95a66c31125278bf4d07166e30fff3ad7e12b232710bf7e376f36f2d4b8a' },
};

const force = process.argv.includes('--force');
if (!force && Object.keys(PINS).every(k => existsSync(join(out, `${k}.json`)))) process.exit(0);
mkdirSync(out, { recursive: true });

const text = async url => {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} → ${r.status}`);
  return r.text();
};

// The page names its webpack runtime; the runtime maps chunk ids to files.
const page = await text(ORIGIN + '/');
const runtimePath = page.match(/\/_next\/static\/chunks\/webpack-[0-9a-f]+\.js/)?.[0];
if (!runtimePath) throw new Error('Shield page names no webpack runtime');
const runtime = await text(ORIGIN + runtimePath);
const named = Object.fromEntries([...runtime.matchAll(/(\d+):"([0-9a-f]{8})"/g)].map(m => [m[1], m[2]]));
const hashes = [...runtime.matchAll(/(\d+):"([0-9a-f]{16})"/g)].map(m => [m[1], m[2]]);
const chunkUrls = hashes.map(([id, h]) => `${ORIGIN}/_next/static/chunks/${named[id] ?? id}.${h}.js`);

// Undoes a single-quoted JavaScript string literal's escapes, by hand: their
// code is data here and is never evaluated.
function unquote(literal) {
  let out = '';
  for (let i = 0; i < literal.length; i++) {
    const c = literal[i];
    if (c !== '\\') { out += c; continue; }
    const n = literal[++i];
    if (n === 'n') out += '\n';
    else if (n === 't') out += '\t';
    else if (n === 'r') out += '\r';
    else if (n === 'b') out += '\b';
    else if (n === 'f') out += '\f';
    else if (n === 'v') out += '\v';
    else if (n === '0') out += '\0';
    else if (n === 'x') { out += String.fromCharCode(parseInt(literal.slice(i + 1, i + 3), 16)); i += 2; }
    else if (n === 'u') { out += String.fromCharCode(parseInt(literal.slice(i + 1, i + 5), 16)); i += 4; }
    else out += n; // \\ \' \" and anything else stand for themselves
  }
  return out;
}

const found = {};
for (const url of chunkUrls) {
  if (Object.keys(found).length === Object.keys(PINS).length) break;
  let body;
  try { body = await text(url); } catch { continue; }
  for (const [name, pin] of Object.entries(PINS)) {
    if (found[name]) continue;
    const at = body.indexOf(`${pin.module}:`);
    if (at < 0) continue;
    const m = body.slice(at).match(/JSON\.parse\('([\s\S]*?)'\)\}/);
    if (!m) continue;
    found[name] = JSON.parse(unquote(m[1]));
  }
}

for (const [name, pin] of Object.entries(PINS)) {
  const json = found[name];
  if (!json) throw new Error(`Shield's ${name} interface was not found in its bundle`);
  const id = (await getContractClassFromArtifact(loadContractArtifact(json))).id.toString();
  if (id !== pin.class) throw new Error(`Shield's ${name} interface computes class ${id}, not the pinned ${pin.class}: refused`);
  writeFileSync(join(out, `${name}.json`), JSON.stringify(json));
  console.error(`fetch-shield: ${name} pinned (${id.slice(0, 10)}…)`);
}
